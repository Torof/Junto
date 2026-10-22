-- Migration 00014: create_activity RPC function
-- Authorization chain: auth + suspension + phone_verified + rate limit + tier check
-- SECURITY DEFINER: inserts into activities + participations (no client INSERT policy)

CREATE OR REPLACE FUNCTION create_activity(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_max_participants INTEGER,
  p_location_start GEOGRAPHY(Point, 4326),
  p_location_meeting GEOGRAPHY(Point, 4326),
  p_route GEOGRAPHY(LineString, 4326),
  p_starts_at TIMESTAMPTZ,
  p_duration INTERVAL,
  p_visibility TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_phone_verified BOOLEAN;
  v_monthly_count INTEGER;
  v_daily_count INTEGER;
  v_activity_id UUID;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Phone verified check
  SELECT phone_verified, tier INTO v_phone_verified, v_tier
  FROM users WHERE id = v_user_id;

  IF NOT v_phone_verified THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Rate limiting with advisory lock (prevents race condition)
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  -- 4a. Daily limit: 2/day for all tiers
  SELECT count(*) INTO v_daily_count
  FROM activities
  WHERE creator_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 day';

  IF v_daily_count >= 2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4b. Monthly limit: 4/month for free tier
  IF v_tier = 'free' THEN
    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id
      AND created_at > NOW() - INTERVAL '1 month';

    IF v_monthly_count >= 4 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- 5. Tier check for private visibility
  IF p_visibility IN ('private_link', 'private_link_approval') AND v_tier = 'free' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Validate starts_at is in the future
  IF p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Insert activity with hardcoded privileged fields
  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, route,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, p_title, p_description, p_level,
    p_max_participants, p_location_start, p_location_meeting, p_route,
    p_starts_at, p_duration, p_visibility, 'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  -- 8. Auto-insert creator as accepted participant
  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  RETURN v_activity_id;
END;
$$;

-- Client-callable: authenticated only
REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;
