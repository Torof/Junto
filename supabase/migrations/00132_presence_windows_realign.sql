-- Migration 00132: realign presence windows.
-- Pre-warning notif: T-30min → T-2h (informational; "it's coming, plan ahead")
-- Geo validation:    T-10min → T-15min (action; "be on-site now")
-- QR validation:     T-30min → T-15min (matches geo)
-- Upper bounds unchanged: geo T+30min, QR T+duration+1h.

-- ============================================================================
-- 1. notify_presence_pre_warning — fires at T-2h, body updated
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_pre_warning(
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
  SELECT id, title, status, starts_at, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'published' THEN RETURN; END IF;
  IF now() < v_activity.starts_at - INTERVAL '2 hours' OR now() >= v_activity.starts_at THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning',
        v_activity.title,
        'Démarre dans 2h — prépare-toi à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_pre_warning FROM anon, authenticated;

-- ============================================================================
-- 2. transition_statuses_only — pre-warning sweep filter T-2h
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

  -- Pre-warning sweep widened: published activities with start within the
  -- next 2 hours (was 30 minutes).
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'published'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND a.starts_at - INTERVAL '2 hours' <= now()
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
-- 3. confirm_presence_via_geo — T-15min lower bound
-- ============================================================================
CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_start FLOAT;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at INTO v_starts_at
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + INTERVAL '30 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    ST_Distance(location_start, v_user_point),
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start, 999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end, 999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;

-- ============================================================================
-- 4. confirm_presence_via_token — T-15min lower bound
-- ============================================================================
CREATE OR REPLACE FUNCTION confirm_presence_via_token(
  p_token TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_token_record RECORD;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_activity_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_token_record
  FROM presence_tokens WHERE token = p_token;
  IF v_token_record IS NULL OR v_token_record.expires_at < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_activity_id := v_token_record.activity_id;

  SELECT starts_at, duration, creator_id INTO v_starts_at, v_duration, v_creator_id
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, v_activity_id);

  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = v_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, v_activity_id);
    END IF;
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;

-- ============================================================================
-- 5. create_presence_token — T-15min lower bound for QR generation
-- ============================================================================
CREATE OR REPLACE FUNCTION create_presence_token(p_activity_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_creator_id UUID;
  v_token TEXT;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id, starts_at, duration INTO v_creator_id, v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_starts_at - INTERVAL '15 minutes' OR now() > v_starts_at + v_duration + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT token INTO v_token FROM presence_tokens
  WHERE activity_id = p_activity_id AND expires_at > now()
  LIMIT 1;

  IF v_token IS NULL THEN
    v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
    INSERT INTO presence_tokens (token, activity_id, expires_at)
    VALUES (v_token, p_activity_id, now() + INTERVAL '30 minutes');
  END IF;

  RETURN v_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_presence_token FROM anon;
GRANT EXECUTE ON FUNCTION create_presence_token TO authenticated;

-- ============================================================================
-- 6. get_my_active_presence_activities — geo polling lower bound T-15min
-- ============================================================================
CREATE OR REPLACE FUNCTION get_my_active_presence_activities()
RETURNS TABLE (
  activity_id UUID,
  title TEXT,
  starts_at TIMESTAMPTZ,
  duration INTERVAL,
  start_lng FLOAT,
  start_lat FLOAT,
  meeting_lng FLOAT,
  meeting_lat FLOAT,
  end_lng FLOAT,
  end_lat FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    a.id AS activity_id,
    a.title,
    a.starts_at,
    a.duration,
    ST_X(a.location_start::geometry)::float AS start_lng,
    ST_Y(a.location_start::geometry)::float AS start_lat,
    ST_X(a.location_meeting::geometry)::float AS meeting_lng,
    ST_Y(a.location_meeting::geometry)::float AS meeting_lat,
    ST_X(a.location_end::geometry)::float AS end_lng,
    ST_Y(a.location_end::geometry)::float AS end_lat
  FROM activities a
  JOIN participations p ON p.activity_id = a.id
  WHERE p.user_id = v_user_id
    AND p.status = 'accepted'
    AND p.confirmed_present IS NULL
    AND a.requires_presence = TRUE
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
    AND now() >= a.starts_at - INTERVAL '15 minutes'
    AND now() <= a.starts_at + INTERVAL '30 minutes';
END;
$$;

REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities FROM anon;
GRANT EXECUTE ON FUNCTION get_my_active_presence_activities TO authenticated;
