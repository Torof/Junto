-- Migration 00117: notification system overhaul.
-- Bundles 12 product decisions + 3 security findings from the dedicated audit.
--
-- Highlights:
--  - AFTER INSERT trigger on notifications centralizes push routing per type
--  - participant_joined: coalesces into one row per (creator, activity), updates count,
--    each new join still buzzes via collapseId (one visual, multiple buzzes)
--  - New type peer_review_closing fires at T+22h to confirmed-present non-voters
--  - alert_match capped to 3/day per user (UTC midnight reset)
--  - confirm_presence (legacy) emissions removed
--  - Auto-purge: notifs >7d old deleted nightly
--  - Suspended user has push_token cleared (S2)
--  - Body strings sanitized at create_notification entry (S3)
--  - seat_*/contact_* now routed through create_notification — respects prefs + suspension (S1, decision L)

-- ============================================================================
-- 1. sanitize_notif_text — strip HTML tags + control chars + clip length
-- ============================================================================
CREATE OR REPLACE FUNCTION sanitize_notif_text(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT substring(
    regexp_replace(
      regexp_replace(coalesce(p, ''), '<[^>]*>', '', 'g'),
      '[\x00-\x1F\x7F]', '', 'g'
    )
    FROM 1 FOR 200
  );
$$;

GRANT EXECUTE ON FUNCTION sanitize_notif_text TO authenticated;

-- ============================================================================
-- 2. create_notification — sanitize on entry, suspension check, prefs check
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
  VALUES (
    p_user_id, p_type,
    sanitize_notif_text(p_title),
    sanitize_notif_text(p_body),
    p_data, now()
  )
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_notification FROM anon, authenticated;

-- ============================================================================
-- 3. AFTER INSERT trigger on notifications: route push per type urgency
-- ============================================================================
CREATE OR REPLACE FUNCTION push_notification_to_device()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_should_push BOOLEAN := TRUE;
  v_collapse_id TEXT;
  v_activity_starts TIMESTAMPTZ;
  v_changes JSONB;
  v_secret TEXT;
BEGIN
  -- Routing: only the high-urgency types push. Info-only types (rate_participants,
  -- request_refused, participant_left_late) stay DB-only.
  CASE NEW.type
    WHEN 'rate_participants', 'request_refused', 'participant_left_late' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      -- collapseId so OS replaces the prior visual (still buzzes per insert)
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

    WHEN 'activity_cancelled' THEN
      SELECT starts_at INTO v_activity_starts
      FROM activities WHERE id = (NEW.data->>'activity_id')::uuid;
      v_should_push := v_activity_starts IS NULL
                       OR (v_activity_starts - now() < INTERVAL '48 hours');

    WHEN 'activity_updated' THEN
      v_changes := NEW.data->'changes';
      -- Push only when logistics-affecting fields changed (date/duration/locations)
      v_should_push := v_changes IS NOT NULL AND (
        v_changes ? 'starts_at' OR v_changes ? 'duration'
        OR v_changes ? 'location_meeting' OR v_changes ? 'location_start'
      );

    ELSE
      v_should_push := TRUE;
  END CASE;

  IF NOT v_should_push THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;

  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body,
      'data', COALESCE(NEW.data, '{}'::jsonb) || jsonb_build_object('type', NEW.type),
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_push ON notifications;
CREATE TRIGGER trg_notification_push
  AFTER INSERT ON notifications
  FOR EACH ROW EXECUTE FUNCTION push_notification_to_device();

-- ============================================================================
-- 4. participant_joined coalesce helper: one row per (creator, activity)
--    — UPDATE if unread row exists, else create_notification (which inserts +
--    fires the trigger). On UPDATE we manually fire push since the trigger
--    only runs on INSERT.
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_participant_joined(
  p_creator_id UUID,
  p_activity_id UUID,
  p_joiner_name TEXT,
  p_activity_title TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_existing RECORD;
  v_count INTEGER;
  v_recent_names JSONB;
  v_clean_name TEXT;
  v_clean_title TEXT;
  v_body TEXT;
  v_secret TEXT;
  v_names_arr TEXT[];
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_joiner_name, 'Quelqu''un'));
  v_clean_title := sanitize_notif_text(coalesce(p_activity_title, ''));

  SELECT id, data INTO v_existing
  FROM notifications
  WHERE user_id = p_creator_id
    AND type = 'participant_joined'
    AND (data->>'activity_id')::uuid = p_activity_id
    AND read_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_existing IS NULL THEN
    PERFORM create_notification(
      p_creator_id,
      'participant_joined',
      'Nouveau participant',
      v_clean_name || ' a rejoint ' || v_clean_title,
      jsonb_build_object(
        'activity_id', p_activity_id,
        'count', 1,
        'recent_names', jsonb_build_array(v_clean_name)
      )
    );
    RETURN;
  END IF;

  v_count := COALESCE((v_existing.data->>'count')::int, 1) + 1;
  v_recent_names := COALESCE(v_existing.data->'recent_names', '[]'::jsonb)
                    || jsonb_build_array(v_clean_name);
  -- Keep at most last 3 names
  IF jsonb_array_length(v_recent_names) > 3 THEN
    v_recent_names := jsonb_path_query_array(v_recent_names, '$[1 to last]');
  END IF;

  SELECT array_agg(value) INTO v_names_arr
  FROM jsonb_array_elements_text(v_recent_names) WITH ORDINALITY;

  IF v_count = 2 THEN
    v_body := v_names_arr[1] || ' et ' || v_names_arr[2] || ' ont rejoint ' || v_clean_title;
  ELSE
    v_body := v_names_arr[array_upper(v_names_arr, 1)]
              || ' et ' || (v_count - 1)::text || ' autres ont rejoint ' || v_clean_title;
  END IF;

  UPDATE notifications
  SET body = v_body,
      data = jsonb_set(
        jsonb_set(v_existing.data, '{count}', to_jsonb(v_count)),
        '{recent_names}', v_recent_names
      ),
      created_at = now(),
      read_at = NULL
  WHERE id = v_existing.id;

  -- AFTER INSERT trigger doesn't fire on UPDATE, so push manually with collapseId
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', p_creator_id,
        'title', 'Nouveau participant',
        'body', v_body,
        'data', jsonb_build_object(
          'activity_id', p_activity_id,
          'count', v_count,
          'type', 'participant_joined'
        ),
        'collapseId', 'joined-' || p_activity_id::text
      )
    );
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_participant_joined FROM anon, authenticated;

-- ============================================================================
-- 5. join_activity — use coalesce helper for participant_joined notif
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
    -- Coalesce: one row per (creator, activity), updated on each new joiner
    PERFORM notify_participant_joined(
      v_activity.creator_id,
      p_activity_id,
      v_user_name,
      v_activity.title
    );
  END IF;

  RETURN v_result_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION join_activity FROM public;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;

-- ============================================================================
-- 6. check_alerts_for_activity — cap alert_match to 3/day per user (UTC reset)
-- ============================================================================
CREATE OR REPLACE FUNCTION check_alerts_for_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
  v_alert RECORD;
  v_today_count INTEGER;
BEGIN
  SELECT a.id, a.creator_id, a.title, a.location_start, a.location_meeting,
         a.starts_at, a.level, a.status, a.deleted_at, s.key AS sport_key
  INTO v_activity
  FROM activities a JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'published' OR v_activity.deleted_at IS NOT NULL THEN
    RETURN;
  END IF;

  v_sport_key := v_activity.sport_key;
  v_activity_date := v_activity.starts_at::date;

  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.levels IS NULL OR v_activity.level = ANY(a.levels))
      AND (a.starts_on IS NULL OR v_activity_date >= a.starts_on)
      AND (a.ends_on IS NULL OR v_activity_date <= a.ends_on)
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_activity.creator_id AND b.blocked_id = a.user_id)
           OR (b.blocker_id = a.user_id AND b.blocked_id = v_activity.creator_id)
      )
      AND (
        ST_DWithin(a.location, v_activity.location_start, a.radius_km * 1000)
        OR (v_activity.location_meeting IS NOT NULL
            AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000))
      )
  LOOP
    -- Cap: at most 3 alert_match notifs per UTC day per user
    SELECT count(*) INTO v_today_count
    FROM notifications
    WHERE user_id = v_alert.user_id
      AND type = 'alert_match'
      AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC');

    IF v_today_count >= 3 THEN CONTINUE; END IF;

    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle activité',
      v_activity.title || ' correspond à ton alerte',
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION check_alerts_for_activity FROM anon, authenticated;

-- ============================================================================
-- 7. notify_peer_review_closing — at T+22h to confirmed-present non-voters
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_peer_review_closing(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '22 hours' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present = TRUE
      AND NOT EXISTS (
        SELECT 1 FROM peer_validations pv
        WHERE pv.activity_id = p_activity_id AND pv.voter_id = p.user_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'peer_review_closing'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'peer_review_closing',
        v_activity.title,
        'Dernière chance pour valider tes co-participants — la fenêtre se ferme dans 2h',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_peer_review_closing FROM anon, authenticated;

-- Extend the partial unique dedup index to cover the new type
DROP INDEX IF EXISTS idx_notif_presence_dedup;
CREATE UNIQUE INDEX IF NOT EXISTS idx_notif_presence_dedup
ON notifications (user_id, type, ((data->>'activity_id')))
WHERE type IN (
  'presence_pre_warning', 'presence_reminder', 'presence_last_call',
  'qr_create_reminder', 'peer_review_closing'
);

-- ============================================================================
-- 8. transition_statuses_only — add peer_review_closing sweep, remove
--    confirm_presence emission (it lives in transition_single_activity below)
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

  -- New: peer_review_closing sweep, T+22h ≤ now ≤ T+24h
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '22 hours'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_peer_review_closing(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_statuses_only TO postgres;

-- ============================================================================
-- 9. transition_single_activity — remove confirm_presence emission (legacy,
--    superseded by peer review system in 00105+)
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress', 'completed') THEN
    RETURN v_activity.status;
  END IF;

  -- published → expired (2h past start, no real participants)
  IF v_activity.status = 'published'
     AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id
          AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  -- published → in_progress
  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      PERFORM notify_presence_reminders(p_activity_id);
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_presence_reminders(p_activity_id);
    PERFORM notify_creator_qr_reminder(p_activity_id);
  END IF;

  -- in_progress → completed
  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';

    IF FOUND THEN
      -- Notify participants to peer-review (creator is one of them — same notif)
      FOR v_participant IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
      LOOP
        PERFORM create_notification(
          v_participant.user_id,
          'rate_participants',
          'Évalue tes co-participants',
          'Comment s''est passé ' || v_activity.title || ' ?',
          jsonb_build_object('activity_id', p_activity_id)
        );
      END LOOP;

      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;

-- ============================================================================
-- 10. seat_request — route through create_notification (S1 + decision L)
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
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_driver_id,
    'seat_request',
    'Demande de covoiturage',
    coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »'
      || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id
    )
  );

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION request_seat FROM anon;
GRANT EXECUTE ON FUNCTION request_seat TO authenticated;

-- ============================================================================
-- 11. accept_seat_request — route through create_notification (push via trigger)
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

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;

-- ============================================================================
-- 12. decline_seat_request — drop redundant explicit push (trigger handles it)
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
      'driver_id', v_req.driver_id
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_seat_request TO authenticated;

-- ============================================================================
-- 13. send_contact_request — route notif through create_notification (S1 + L)
--    Data model is the conversations table (status='pending_request'), not a
--    separate contact_requests table — only the notification path changes.
-- ============================================================================
CREATE OR REPLACE FUNCTION send_contact_request(
  p_target_user_id UUID,
  p_message TEXT,
  p_source TEXT DEFAULT 'profile'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_user_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  SELECT id INTO v_conversation_id
  FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;

  IF v_conversation_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conversation_id AND status = 'active') THEN
      RETURN v_conversation_id;
    END IF;
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));
  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE status = 'pending_request'
    AND ((user_1 = v_user_id) OR (user_2 = v_user_id))
    AND initiated_from IS NOT NULL;
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'pending_request', p_source, v_user_id, trim(p_message), NOW() + INTERVAL '30 days', NOW(), NOW())
  RETURNING id INTO v_conversation_id;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' souhaite te contacter',
    '',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id)
  );

  RETURN v_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION send_contact_request TO authenticated;

-- ============================================================================
-- 14. accept_contact_request — route notif through create_notification
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_sender_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_conv.request_sender_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_sender_id := v_conv.request_sender_id;

  UPDATE conversations
  SET status = 'active', request_expires_at = NULL
  WHERE id = p_conversation_id;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_sender_id, v_user_id, v_conv.request_message, v_conv.created_at);

  PERFORM create_notification(
    v_sender_id,
    'contact_request_accepted',
    'Demande acceptée',
    '',
    jsonb_build_object('conversation_id', p_conversation_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_contact_request TO authenticated;

-- ============================================================================
-- 15. Suspension trigger: clear push_token when suspended_at is set
-- ============================================================================
CREATE OR REPLACE FUNCTION clear_push_token_on_suspension()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE id = NEW.id AND push_token IS NOT NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clear_push_on_suspension ON users;
CREATE TRIGGER trg_clear_push_on_suspension
  AFTER UPDATE OF suspended_at ON users
  FOR EACH ROW
  WHEN (OLD.suspended_at IS NULL AND NEW.suspended_at IS NOT NULL)
  EXECUTE FUNCTION clear_push_token_on_suspension();

-- ============================================================================
-- 16. Auto-purge: daily cron deletes notifications >7 days old
-- ============================================================================
CREATE OR REPLACE FUNCTION purge_old_notifications()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM notifications WHERE created_at < now() - INTERVAL '7 days';
$$;

REVOKE EXECUTE ON FUNCTION purge_old_notifications FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION purge_old_notifications TO postgres;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'junto-notif-purge') THEN
    PERFORM cron.unschedule('junto-notif-purge');
  END IF;
END $$;

SELECT cron.schedule(
  'junto-notif-purge',
  '0 4 * * *',  -- daily at 04:00 UTC
  $$SELECT public.purge_old_notifications();$$
);
