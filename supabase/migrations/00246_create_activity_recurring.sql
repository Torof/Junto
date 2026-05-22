-- Migration 00246: extend create_activity to support recurring activities.
--
-- Recurring activities are the pro storefront equivalent of one-off
-- activities. The row persists across occurrences (see 00245 reset job);
-- the create flow only differs in two new params:
--   - p_is_recurring BOOLEAN
--   - p_recurrence_days INTEGER (1..365)
--
-- Authorization additions for is_recurring=TRUE:
--   - Caller's users.tier must be 'pro' (free/premium tiers can't create
--     recurring storefronts; that's the paid offering)
--   - A pro_profiles row must exist (defense in depth — tier could
--     theoretically drift without a profile row)
--   - p_recurrence_days must be NOT NULL and in 1..365
--
-- For is_recurring=FALSE (default), recurrence_days is forced to NULL
-- regardless of what the client sent.

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
  p_visibility TEXT DEFAULT 'public',
  p_requires_presence BOOLEAN DEFAULT TRUE,
  p_objective_lng FLOAT DEFAULT NULL,
  p_objective_lat FLOAT DEFAULT NULL,
  p_objective_name TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL,
  p_start_name TEXT DEFAULT NULL,
  p_trace_geojson JSONB DEFAULT NULL,
  p_is_recurring BOOLEAN DEFAULT FALSE,
  p_recurrence_days INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_is_admin BOOLEAN;
  v_daily_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
  v_recurrence_days INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT tier, coalesce(is_admin, FALSE) INTO v_tier, v_is_admin
  FROM users WHERE id = v_user_id;

  IF NOT v_is_admin THEN
    SELECT count(*) INTO v_daily_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

    IF v_daily_count >= 20 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;

  -- Recurring branch: pro tier + pro_profiles row + valid recurrence_days.
  IF coalesce(p_is_recurring, FALSE) = TRUE THEN
    IF v_tier IS DISTINCT FROM 'pro' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    IF p_recurrence_days IS NULL OR p_recurrence_days < 1 OR p_recurrence_days > 365 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    v_recurrence_days := p_recurrence_days;
  ELSE
    -- One-off: never trust a client-provided recurrence_days.
    v_recurrence_days := NULL;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    location_objective, objective_name, start_name,
    distance_km, elevation_gain_m,
    starts_at, duration, visibility, requires_presence,
    trace_geojson,
    is_recurring, recurrence_days,
    status, created_at, updated_at
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
    CASE WHEN p_objective_lng IS NOT NULL AND p_objective_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_objective_lng, p_objective_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_name IS NOT NULL AND char_length(trim(p_objective_name)) > 0
      THEN trim(p_objective_name) ELSE NULL END,
    CASE WHEN p_start_name IS NOT NULL AND char_length(trim(p_start_name)) > 0
      THEN trim(p_start_name) ELSE NULL END,
    p_distance_km,
    p_elevation_gain_m,
    p_starts_at, p_duration::interval, p_visibility, coalesce(p_requires_presence, TRUE),
    p_trace_geojson,
    coalesce(p_is_recurring, FALSE), v_recurrence_days,
    'published', now(), now()
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
