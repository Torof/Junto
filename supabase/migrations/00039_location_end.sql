-- Migration 00039: Add optional end point to activities

ALTER TABLE activities ADD COLUMN location_end GEOGRAPHY(Point, 4326);

-- Update whitelist trigger to lock location_end when participants exist
CREATE OR REPLACE FUNCTION handle_activity_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;

  -- Conditional lock when participants exist (besides creator)
  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_start := OLD.location_start;
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Update create_activity to accept end point
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
  v_phone_verified BOOLEAN;
  v_monthly_count INTEGER;
  v_daily_count INTEGER;
  v_activity_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT phone_verified, tier INTO v_phone_verified, v_tier
  FROM users WHERE id = v_user_id;

  IF NOT v_phone_verified THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT count(*) INTO v_daily_count
  FROM activities
  WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

  IF v_daily_count >= 2 THEN
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

  IF p_visibility IN ('private_link', 'private_link_approval') AND v_tier = 'free' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, p_title, p_description, p_level,
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

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

-- Update views to include end point coordinates
DROP VIEW IF EXISTS activities_with_coords;
CREATE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  ST_X(a.location_start::geometry) AS lng,
  ST_Y(a.location_start::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress');

GRANT SELECT ON activities_with_coords TO anon, authenticated;
