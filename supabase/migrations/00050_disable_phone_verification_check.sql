-- Migration 00050: TEMPORARY — disable phone_verified gate on create_activity
-- Restore this check before opening to a wider audience (Twilio SMS OTP integration).

CREATE OR REPLACE FUNCTION create_activity(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_max_participants INTEGER,
  p_start_lng FLOAT,
  p_start_lat FLOAT,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_end_lng FLOAT DEFAULT NULL,
  p_end_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT '2 hours',
  p_visibility TEXT DEFAULT 'public'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_monthly_count INTEGER;
  v_daily_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;

  IF p_visibility IN ('private_link', 'private_link_approval') AND v_tier = 'free' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT count(*) INTO v_daily_count
  FROM activities
  WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

  IF v_daily_count >= 20 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_tier = 'free' THEN
    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 month';

    IF v_monthly_count >= 4 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography,
    CASE WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    p_starts_at, p_duration::interval, p_visibility, 'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  IF p_visibility IN ('public', 'approval') THEN
    PERFORM check_alerts_for_activity(v_activity_id);
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;
