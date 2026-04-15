-- Migration 00067: per-activity presence verification toggle
-- Default TRUE — most outdoor activities have safety stakes (group composition matters).
-- Casual organisers can opt out (gym climbing, park slackline, coffee, etc.).

ALTER TABLE activities ADD COLUMN requires_presence BOOLEAN NOT NULL DEFAULT TRUE;

-- ============================================================================
-- create_activity now accepts the toggle
-- ============================================================================
DROP FUNCTION IF EXISTS create_activity(UUID, TEXT, TEXT, TEXT, INTEGER, FLOAT, FLOAT, FLOAT, FLOAT, FLOAT, FLOAT, TIMESTAMPTZ, TEXT, TEXT);

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
  p_requires_presence BOOLEAN DEFAULT TRUE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
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

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    starts_at, duration, visibility, requires_presence,
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
    p_starts_at, p_duration::interval, p_visibility, coalesce(p_requires_presence, TRUE),
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

-- ============================================================================
-- Presence RPCs reject when verification is disabled for the activity
-- ============================================================================
CREATE OR REPLACE FUNCTION _is_presence_window(p_activity_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_requires BOOLEAN;
BEGIN
  SELECT starts_at, duration, requires_presence
  INTO v_starts_at, v_duration, v_requires
  FROM activities WHERE id = p_activity_id;

  IF v_starts_at IS NULL OR NOT v_requires THEN
    RETURN FALSE;
  END IF;

  RETURN now() BETWEEN (v_starts_at - INTERVAL '2 hours')
                   AND (v_starts_at + v_duration + INTERVAL '12 hours');
END;
$$;

REVOKE EXECUTE ON FUNCTION _is_presence_window FROM anon, authenticated;

-- ============================================================================
-- Expose requires_presence in activities_with_coords so the client can hide
-- the presence section on activities where it's disabled.
-- ============================================================================
DROP VIEW IF EXISTS activities_with_coords;
CREATE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
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
  AND a.status IN ('published', 'in_progress')
  AND a.visibility IN ('public', 'approval');

GRANT SELECT ON activities_with_coords TO anon, authenticated;

-- Same column added to my_activities and my_joined_activities for consistency
DROP VIEW IF EXISTS my_activities;
CREATE VIEW my_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
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
WHERE a.creator_id = auth.uid();

GRANT SELECT ON my_activities TO authenticated;

DROP VIEW IF EXISTS my_joined_activities;
CREATE VIEW my_joined_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
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
JOIN participations par ON par.activity_id = a.id
  AND par.user_id = auth.uid()
  AND par.status = 'accepted'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id != auth.uid()
  AND a.deleted_at IS NULL;

GRANT SELECT ON my_joined_activities TO authenticated;
