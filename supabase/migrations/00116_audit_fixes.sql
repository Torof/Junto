-- Migration 00116: post-audit fixes (process + technical passes).
-- Bundles 14 fixes uncovered by the comprehensive audit:
-- (1) suspension cascade: cron skips activities with suspended creator
-- (2) suspended recipients: create_notification returns NULL early
-- (3) block cascade: pending join + seat requests auto-cancelled
-- (4) creator self-leave: leave_activity rejects activity creator
-- (5) driver leave: passenger seat_requests cancelled + notified
-- (6) remove_participant clears confirmed_present
-- (7) update_activity emits change-set in notif data for client rendering
-- (8) accept_participation honors hidden 50-soft-cap when max_participants IS NULL
-- (9) set_participation_transport bounds transport_departs_at within ±12h/+6h
-- (10) request_seat bounds requested_pickup_at <= transport_departs_at
-- (11) accept_seat_request locks driver participation + checks transport_seats > 0
-- (12) decline_seat_request notifies requester
-- (13) activity_participants + get_user_public_stats expose reliability_tier (not raw score)
-- (14) recalculate_reliability_score wraps in per-user advisory lock
-- (15) peer_validate_presence: dynamic threshold (1 if accepted ≤ 3, else 2)
-- (16) join_activity: 24h cooldown after refused

-- ============================================================================
-- 1. Schema: refused_at on participations (anchors the 24h cooldown)
-- ============================================================================
ALTER TABLE participations ADD COLUMN IF NOT EXISTS refused_at TIMESTAMPTZ;

-- ============================================================================
-- 2. reliability_tier helper — single source of truth for tier bands
-- ============================================================================
CREATE OR REPLACE FUNCTION reliability_tier(p_score FLOAT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_score IS NULL THEN 'new'
    WHEN p_score >= 90 THEN 'excellent'
    WHEN p_score >= 75 THEN 'good'
    WHEN p_score >= 50 THEN 'fair'
    ELSE 'poor'
  END;
$$;

REVOKE EXECUTE ON FUNCTION reliability_tier FROM anon;
GRANT EXECUTE ON FUNCTION reliability_tier TO authenticated;

-- ============================================================================
-- 3. create_notification — skip suspended recipients
-- ============================================================================
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id UUID;
  v_prefs JSONB;
  v_pref_value TEXT;
  v_suspended TIMESTAMPTZ;
BEGIN
  SELECT suspended_at, notification_preferences
  INTO v_suspended, v_prefs
  FROM users WHERE id = p_user_id;

  IF v_suspended IS NOT NULL THEN
    RETURN NULL;
  END IF;

  IF v_prefs IS NOT NULL AND v_prefs ? p_type THEN
    v_pref_value := v_prefs ->> p_type;
    IF v_pref_value IS NOT NULL AND v_pref_value NOT IN ('true', '1') THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (p_user_id, p_type, p_title, p_body, p_data, now())
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_notification FROM anon, authenticated;

-- ============================================================================
-- 4. transition_statuses_only — skip notif loops for suspended creators
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_statuses_only()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();

  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now();

  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'published'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND a.starts_at - INTERVAL '30 minutes' <= now()
      AND a.starts_at > now()
  LOOP
    PERFORM notify_presence_pre_warning(v_activity_id);
  END LOOP;

  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    PERFORM notify_presence_reminders(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() <= a.starts_at + a.duration + INTERVAL '1 hour'
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.status = 'accepted' AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM notify_presence_last_call(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_statuses_only TO postgres;

-- ============================================================================
-- 5. Block cascade trigger: cancel pending join + seat requests both directions
-- ============================================================================
CREATE OR REPLACE FUNCTION cascade_block_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Refuse pending join requests where blocker is creator and blocked is requester (or vice-versa)
  UPDATE participations p
  SET status = 'refused', refused_at = now()
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND ((a.creator_id = NEW.blocker_id AND p.user_id = NEW.blocked_id)
      OR (a.creator_id = NEW.blocked_id AND p.user_id = NEW.blocker_id));

  -- Cancel pending/accepted seat requests in both directions
  UPDATE seat_requests
  SET status = 'cancelled'
  WHERE status IN ('pending', 'accepted')
    AND ((requester_id = NEW.blocker_id AND driver_id = NEW.blocked_id)
      OR (requester_id = NEW.blocked_id AND driver_id = NEW.blocker_id));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_blocked_users_cascade ON blocked_users;
CREATE TRIGGER trg_blocked_users_cascade
  AFTER INSERT ON blocked_users
  FOR EACH ROW EXECUTE FUNCTION cascade_block_cleanup();

-- ============================================================================
-- 6. leave_activity — reject creator, release passenger seats if driver leaves
-- ============================================================================
CREATE OR REPLACE FUNCTION leave_activity(
  p_activity_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
  v_reason TEXT;
  v_was_driver BOOLEAN;
  v_passenger RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

  SELECT p.id, p.status, p.transport_type, p.transport_seats
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  -- Block creator from leaving their own activity (would orphan the activity)
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_late := v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now());

  v_was_driver := v_participation.transport_type IN ('car', 'carpool');

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL
  WHERE id = v_participation.id;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté l''activité',
    CASE
      WHEN v_is_late AND v_reason IS NOT NULL THEN v_reason || ' · Pénalité appliquée'
      WHEN v_is_late THEN 'Pénalité de fiabilité appliquée — tu peux la lever'
      WHEN v_reason IS NOT NULL THEN v_reason
      ELSE v_activity.title
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late)
  );

  -- If the leaver was offering rides, cancel their pending/accepted seat_requests
  -- and notify each affected requester so they can find another ride.
  IF v_was_driver THEN
    FOR v_passenger IN
      SELECT id, requester_id FROM seat_requests
      WHERE activity_id = p_activity_id AND driver_id = v_user_id
        AND status IN ('pending', 'accepted')
    LOOP
      UPDATE seat_requests SET status = 'cancelled' WHERE id = v_passenger.id;
      PERFORM create_notification(
        v_passenger.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_user_name, 'Le conducteur') || ' a quitté « ' || v_activity.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', p_activity_id, 'driver_id', v_user_id)
      );
    END LOOP;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION leave_activity FROM anon;
GRANT EXECUTE ON FUNCTION leave_activity TO authenticated;

-- ============================================================================
-- 7. refuse_participation — set refused_at (anchors the 24h cooldown)
-- ============================================================================
CREATE OR REPLACE FUNCTION refuse_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'refused', refused_at = now()
  WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_refused',
    'Demande refusée',
    'Ta demande pour ' || v_participation.title || ' a été refusée',
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION refuse_participation FROM public;
GRANT EXECUTE ON FUNCTION refuse_participation TO authenticated;

-- ============================================================================
-- 8. remove_participant — clear confirmed_present so stale TRUE doesn't survive
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_participant(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, a.creator_id, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.user_id = v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'removed',
      confirmed_present = NULL
  WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'participant_removed',
    'Retiré de l''activité',
    'Tu as été retiré de ' || v_participation.title,
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_participant FROM public;
GRANT EXECUTE ON FUNCTION remove_participant TO authenticated;

-- ============================================================================
-- 9. update_activity — emit changes set in notif data so client renders specifics
-- ============================================================================
CREATE OR REPLACE FUNCTION update_activity(
  p_activity_id UUID,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_level TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_start_lng FLOAT DEFAULT NULL,
  p_start_lat FLOAT DEFAULT NULL,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_old RECORD;
  v_new RECORD;
  v_participant RECORD;
  v_trimmed_title TEXT;
  v_changes JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, location_start, max_participants, level, visibility
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_starts_at IS NOT NULL AND p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    max_participants = COALESCE(p_max_participants, max_participants),
    location_start = CASE
      WHEN p_start_lng IS NOT NULL AND p_start_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography
      ELSE location_start END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting END,
    starts_at = COALESCE(p_starts_at, starts_at),
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE duration END,
    visibility = COALESCE(p_visibility, visibility)
  WHERE id = p_activity_id;

  -- Re-fetch after the UPDATE (whitelist trigger may have forced privileged
  -- columns back to OLD when participants exist — only notify on real changes).
  SELECT title, description, starts_at, duration, location_meeting, location_start,
         max_participants, level, visibility
  INTO v_new FROM activities WHERE id = p_activity_id;

  v_changes := '{}'::jsonb;
  IF v_old.title IS DISTINCT FROM v_new.title THEN
    v_changes := v_changes || jsonb_build_object('title', true);
  END IF;
  IF v_old.starts_at IS DISTINCT FROM v_new.starts_at THEN
    v_changes := v_changes || jsonb_build_object('starts_at', true);
  END IF;
  IF v_old.duration IS DISTINCT FROM v_new.duration THEN
    v_changes := v_changes || jsonb_build_object('duration', true);
  END IF;
  IF v_old.location_meeting IS DISTINCT FROM v_new.location_meeting THEN
    v_changes := v_changes || jsonb_build_object('location_meeting', true);
  END IF;
  IF v_old.location_start IS DISTINCT FROM v_new.location_start THEN
    v_changes := v_changes || jsonb_build_object('location_start', true);
  END IF;
  IF v_old.description IS DISTINCT FROM v_new.description THEN
    v_changes := v_changes || jsonb_build_object('description', true);
  END IF;
  IF v_old.level IS DISTINCT FROM v_new.level THEN
    v_changes := v_changes || jsonb_build_object('level', true);
  END IF;
  IF v_old.max_participants IS DISTINCT FROM v_new.max_participants THEN
    v_changes := v_changes || jsonb_build_object('max_participants', true);
  END IF;
  IF v_old.visibility IS DISTINCT FROM v_new.visibility THEN
    v_changes := v_changes || jsonb_build_object('visibility', true);
  END IF;

  -- No real change happened (every requested field was rejected by trigger or unchanged) — skip notif
  IF v_changes = '{}'::jsonb THEN RETURN; END IF;

  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_updated',
      'Activité modifiée',
      v_new.title || ' a été modifiée',
      jsonb_build_object('activity_id', p_activity_id, 'changes', v_changes)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_activity FROM anon;
GRANT EXECUTE ON FUNCTION update_activity TO authenticated;

-- ============================================================================
-- 10. accept_participation — honor 50-soft-cap when max_participants IS NULL
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_current_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.max_participants, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  -- Open activities (max_participants IS NULL) honor a hidden 50-soft-cap, same as join_activity
  IF v_current_count >= COALESCE(v_participation.max_participants, 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_accepted',
    'Demande acceptée',
    'Ta demande pour ' || v_participation.title || ' a été acceptée',
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_participation FROM public;
GRANT EXECUTE ON FUNCTION accept_participation TO authenticated;

-- ============================================================================
-- 11. set_participation_transport — bound transport_departs_at vs starts_at
-- ============================================================================
CREATE OR REPLACE FUNCTION set_participation_transport(
  p_activity_id UUID,
  p_transport_type TEXT,
  p_transport_seats SMALLINT DEFAULT NULL,
  p_transport_from_name TEXT DEFAULT NULL,
  p_transport_departs_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_transport_type NOT IN ('car', 'carpool') AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  IF p_transport_type NOT IN ('car', 'carpool') THEN
    p_transport_departs_at := NULL;
  END IF;

  -- Bound transport_departs_at to a sane window around starts_at
  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = CASE WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
                                 THEN trim(p_transport_from_name) ELSE NULL END,
      transport_departs_at = p_transport_departs_at
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;

REVOKE EXECUTE ON FUNCTION set_participation_transport FROM anon;
GRANT EXECUTE ON FUNCTION set_participation_transport TO authenticated;

-- ============================================================================
-- 12. request_seat — bound requested_pickup_at vs driver's transport_departs_at
-- ============================================================================
CREATE OR REPLACE FUNCTION request_seat(
  p_activity_id UUID,
  p_driver_id UUID,
  p_pickup_from TEXT DEFAULT NULL,
  p_message TEXT DEFAULT NULL,
  p_requested_pickup_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_starts_at TIMESTAMPTZ;
  v_driver_departs_at TIMESTAMPTZ;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_secret TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT transport_departs_at INTO v_driver_departs_at
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_driver_id
    AND transport_type IN ('car', 'carpool') AND transport_seats > 0;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Bound requested_pickup_at: must be within ±12h of starts_at, AND <= driver's departure if set
  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF v_driver_departs_at IS NOT NULL AND p_requested_pickup_at > v_driver_departs_at THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  v_pickup := CASE WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
                   THEN trim(p_pickup_from) ELSE NULL END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message,
        requested_pickup_at = p_requested_pickup_at
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message, requested_pickup_at)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message, p_requested_pickup_at)
      RETURNING id INTO v_request_id;
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    p_driver_id, 'seat_request',
    v_requester_name || ' demande une place' || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    COALESCE(v_message, ''),
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'type', 'seat_request'
    ),
    NOW()
  );

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', p_driver_id,
        'title', 'Demande de covoiturage',
        'body', coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »',
        'data', jsonb_build_object(
          'seat_request_id', v_request_id,
          'activity_id', p_activity_id,
          'type', 'seat_request'
        )
      )
    );
  END IF;

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION request_seat FROM anon;
GRANT EXECUTE ON FUNCTION request_seat TO authenticated;

-- ============================================================================
-- 13. accept_seat_request — FOR UPDATE on driver participation + seats > 0 check
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_seat_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_secret TEXT;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Lock driver's participation row and verify seats remain (otherwise concurrent accepts could over-allocate)
  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  SELECT id INTO v_conversation_id FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2 AND status = 'active';
  IF v_conversation_id IS NULL THEN
    INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
    RETURNING id INTO v_conversation_id;
  END IF;

  v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
    || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
    || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_req.driver_id, v_req.requester_id, v_message,
    jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    v_req.requester_id, 'seat_request_accepted', 'Place confirmée !', '',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'type', 'seat_request_accepted'
    ),
    NOW()
  );

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', v_req.requester_id,
        'title', 'Place confirmée !',
        'body', coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
        'data', jsonb_build_object(
          'conversation_id', v_conversation_id,
          'activity_id', v_req.activity_id,
          'type', 'seat_request_accepted'
        )
      )
    );
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;

-- ============================================================================
-- 14. decline_seat_request — notify requester
-- ============================================================================
CREATE OR REPLACE FUNCTION decline_seat_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_secret TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'declined' WHERE id = p_request_id;

  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_declined',
    'Demande refusée',
    coalesce(v_driver_name, 'Le conducteur') || ' a refusé ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'seat_request_id', v_req.id,
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'type', 'seat_request_declined'
    )
  );

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', v_req.requester_id,
        'title', 'Demande refusée',
        'body', coalesce(v_driver_name, 'Le conducteur') || ' a refusé ta demande pour « ' || v_activity_title || ' »',
        'data', jsonb_build_object(
          'seat_request_id', v_req.id,
          'activity_id', v_req.activity_id,
          'type', 'seat_request_declined'
        )
      )
    );
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_seat_request TO authenticated;

-- ============================================================================
-- 15. activity_participants view — strip raw reliability_score, expose tier
-- ============================================================================
DROP VIEW IF EXISTS activity_participants;

CREATE VIEW activity_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  p.left_reason,
  p.penalty_waived,
  p.transport_type,
  p.transport_seats,
  p.transport_from_name,
  p.transport_departs_at,
  a.creator_id,
  pp.display_name,
  pp.avatar_url,
  pp.sports,
  pp.levels_per_sport,
  reliability_tier(u.reliability_score) AS reliability_tier
FROM participations p
JOIN activities a ON a.id = p.activity_id
JOIN public_profiles pp ON pp.id = p.user_id
JOIN users u ON u.id = p.user_id
WHERE a.creator_id = auth.uid()
  AND p.user_id != a.creator_id
  AND p.status != 'removed'
  AND a.deleted_at IS NULL
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON activity_participants TO authenticated;

-- ============================================================================
-- 16. get_user_public_stats — return reliability_tier instead of raw score
-- ============================================================================
DROP FUNCTION IF EXISTS get_user_public_stats(UUID);

CREATE OR REPLACE FUNCTION get_user_public_stats(
  p_user_id UUID
)
RETURNS TABLE (
  total_activities INTEGER,
  completed_activities INTEGER,
  created_activities INTEGER,
  joined_activities INTEGER,
  sports_count INTEGER,
  reliability_tier TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT count(*)::int FROM participations
     WHERE user_id = p_user_id AND status = 'accepted') AS total_activities,
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id AND par.status = 'accepted' AND a.status = 'completed') AS completed_activities,
    (SELECT count(*)::int FROM activities
     WHERE creator_id = p_user_id AND deleted_at IS NULL) AS created_activities,
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL) AS joined_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    (SELECT public.reliability_tier(u.reliability_score) FROM users u WHERE u.id = p_user_id) AS reliability_tier;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_public_stats FROM anon;
GRANT EXECUTE ON FUNCTION get_user_public_stats TO authenticated;

-- ============================================================================
-- 17. recalculate_reliability_score — per-user advisory lock
-- ============================================================================
CREATE OR REPLACE FUNCTION recalculate_reliability_score(
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prior CONSTANT INTEGER := 3;
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  -- Serialize concurrent recalcs for the same user (e.g. auto-FALSE batch + peer flip)
  PERFORM pg_advisory_xact_lock(hashtext('reliability_' || p_user_id::text));

  SELECT count(*) INTO v_total
  FROM participations
  WHERE user_id = p_user_id AND confirmed_present IS NOT NULL;

  SELECT count(*) INTO v_present
  FROM participations
  WHERE user_id = p_user_id AND confirmed_present = true;

  SELECT count(*) INTO v_late_cancels
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.status = 'withdrawn'
    AND p.left_at IS NOT NULL
    AND p.left_at > a.starts_at - INTERVAL '12 hours'
    AND p.penalty_waived = FALSE
    AND a.requires_presence = TRUE;

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION recalculate_reliability_score FROM anon, authenticated;

-- ============================================================================
-- 18. peer_validate_presence — dynamic threshold (1 if accepted ≤ 3, else 2)
-- ============================================================================
CREATE OR REPLACE FUNCTION peer_validate_presence(
  p_voted_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_voter_present BOOLEAN;
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
  v_accepted_count INTEGER;
  v_threshold INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  -- Dynamic threshold: groups of ≤3 only need 1 vote (otherwise tiny groups
  -- can never reach quorum). Larger groups need 2 to prevent collusion.
  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  v_threshold := CASE WHEN v_accepted_count <= 3 THEN 1 ELSE 2 END;

  IF v_vote_count >= v_threshold THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    PERFORM recalculate_reliability_score(p_voted_id);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION peer_validate_presence FROM anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence TO authenticated;

-- ============================================================================
-- 19. join_activity — 24h cooldown after refused
-- ============================================================================
CREATE OR REPLACE FUNCTION join_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at INTO v_existing
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    -- 24h cooldown after creator refused
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now(), refused_at = NULL
    WHERE id = v_existing.id;
  ELSE
    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id,
      'join_request',
      'Nouvelle demande',
      v_user_name || ' souhaite rejoindre ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  ELSE
    PERFORM create_notification(
      v_activity.creator_id,
      'participant_joined',
      'Nouveau participant',
      v_user_name || ' a rejoint ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  END IF;

  RETURN v_result_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION join_activity FROM public;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;
