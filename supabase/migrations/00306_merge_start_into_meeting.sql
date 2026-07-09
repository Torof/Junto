-- Migration 00306: merge "départ" into "rendez-vous" — one meeting point.
--
-- Scott 2026-07-09: départ and rendez-vous are the same thing in real life
-- (the RDV is where the activity actually starts, approach walk included).
-- location_meeting becomes the single canonical point (NOT NULL) carrying
-- ALL of start's capabilities: display name (start_name RENAMED meeting_name),
-- Google-Maps itinerary anchor, presence validation, route-line origin.
-- location_start + its GIST index are dropped; a GIST index is created on
-- location_meeting.
--
-- SAFETY (presence/geofencing): data merge is COALESCE(meeting, start), so
-- every activity whose meeting was empty inherits EXACTLY its old start
-- point — confirm_presence_via_geo and the client geofences resolve the
-- same coordinate as before. The 150 m threshold, end point and GPX-trace
-- distance terms are untouched. Client resolvers already read meeting ?? start.
--
-- Authorization chains are UNCHANGED in every redefined function — only
-- signatures/projections shrink. Functions with changed return shapes are
-- DROPped and recreated with their grants re-issued verbatim.

-- 1. Data merge (bypass the whitelist trigger; RDV wins when both set)
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE activities SET location_meeting = COALESCE(location_meeting, location_start);

-- 2. Drop dependents (function returns the view rowtype; views project start)
DROP FUNCTION IF EXISTS get_activity_detail;
DROP VIEW IF EXISTS my_pending_activities;
DROP VIEW IF EXISTS my_joined_activities;
DROP VIEW IF EXISTS my_activities;
DROP VIEW IF EXISTS activities_with_coords;

-- 3. Schema
ALTER TABLE activities RENAME COLUMN start_name TO meeting_name;
ALTER TABLE activities ALTER COLUMN location_meeting SET NOT NULL;
DROP INDEX IF EXISTS activities_location_start_idx;
ALTER TABLE activities DROP COLUMN location_start;
CREATE INDEX IF NOT EXISTS activities_location_meeting_idx ON activities USING GIST (location_meeting);

-- 4. Whitelist trigger (meeting_name unconditionally privileged, as start_name was)
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

  -- Unconditionally privileged columns. Writable only via SECURITY
  -- DEFINER functions that explicitly call bypass_lock.
  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.meeting_name := OLD.meeting_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;

  -- Locked once accepted participants exist.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- 5. Views (shapes lose start_*, expose meeting_name)
CREATE OR REPLACE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.meeting_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
  a.level_max
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress')
  AND a.visibility IN ('public', 'approval')
  AND NOT private.user_is_suspended(a.creator_id)
  AND a.creator_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

DROP VIEW IF EXISTS my_activities;
CREATE VIEW my_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.meeting_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
  a.level_max
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id = auth.uid();

GRANT SELECT ON my_activities TO authenticated;

DROP VIEW IF EXISTS my_joined_activities;
CREATE VIEW my_joined_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.meeting_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
  a.level_max
FROM activities a
JOIN participations par ON par.activity_id = a.id
  AND par.user_id = auth.uid()
  AND par.status = 'accepted'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id != auth.uid()
  AND a.deleted_at IS NULL;

GRANT SELECT ON my_joined_activities TO authenticated;

DROP VIEW IF EXISTS my_pending_activities;
CREATE VIEW my_pending_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.meeting_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
  a.level_max
FROM activities a
JOIN participations par ON par.activity_id = a.id
  AND par.user_id = auth.uid()
  AND par.status = 'pending'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id <> auth.uid()
  AND a.deleted_at IS NULL;

GRANT SELECT ON my_pending_activities TO authenticated;

GRANT SELECT ON activities_with_coords TO anon, authenticated;

-- 6. create_activity / update_activity / invite token
DROP FUNCTION IF EXISTS create_activity;
CREATE OR REPLACE FUNCTION create_activity(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_max_participants INTEGER,
  p_meeting_lng FLOAT,
  p_meeting_lat FLOAT,
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
  p_meeting_name TEXT DEFAULT NULL,
  p_trace_geojson JSONB DEFAULT NULL,
  p_level_max TEXT DEFAULT NULL
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
  v_monthly_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
  v_level_max TEXT;
BEGIN
  -- Sensitive: generic.
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- User-actionable: coded.
  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;

  -- Normalise the range high end: empty → NULL; equal to the low end → NULL
  -- (single level). Scale membership/ordering enforced client-side.
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'junto.date_in_past';
  END IF;

  IF p_starts_at > NOW() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.date_too_far';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic.
  IF p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT tier, coalesce(is_admin, FALSE) INTO v_tier, v_is_admin
  FROM users WHERE id = v_user_id;

  -- Premium gate: coded (telling a free user it's a premium feature is fine).
  IF p_visibility IN ('private_link', 'private_link_approval')
     AND v_tier NOT IN ('premium', 'pro') THEN
    RAISE EXCEPTION 'junto.premium_required';
  END IF;

  IF NOT v_is_admin THEN
    SELECT count(*) INTO v_daily_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

    IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.limit_daily'; END IF;

    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '30 days';

    IF v_monthly_count >= 30 THEN RAISE EXCEPTION 'junto.limit_monthly'; END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level, level_max,
    max_participants, location_meeting, location_end,
    location_objective, objective_name, meeting_name,
    distance_km, elevation_gain_m,
    starts_at, duration, visibility, requires_presence,
    trace_geojson,
    status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level, v_level_max,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_lng IS NOT NULL AND p_objective_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_objective_lng, p_objective_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_name IS NOT NULL AND char_length(trim(p_objective_name)) > 0
      THEN trim(p_objective_name) ELSE NULL END,
    CASE WHEN p_meeting_name IS NOT NULL AND char_length(trim(p_meeting_name)) > 0
      THEN trim(p_meeting_name) ELSE NULL END,
    p_distance_km,
    p_elevation_gain_m,
    p_starts_at, p_duration::interval, p_visibility, coalesce(p_requires_presence, TRUE),
    p_trace_geojson,
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

REVOKE ALL ON FUNCTION create_activity FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

DROP FUNCTION IF EXISTS update_activity;
CREATE OR REPLACE FUNCTION update_activity(
  p_activity_id UUID,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_level TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL,
  p_level_max TEXT DEFAULT NULL
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
  v_level_max TEXT;
  v_changes JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;
  END IF;

  -- Normalised range high end (only applied when the level is being edited).
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF p_level IS NOT NULL AND v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, max_participants, level, visibility
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_starts_at IS NOT NULL AND p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'junto.date_in_past';
  END IF;

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    level_max = CASE WHEN p_level IS NOT NULL THEN v_level_max ELSE level_max END,
    max_participants = COALESCE(p_max_participants, max_participants),
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
  SELECT title, description, starts_at, duration, location_meeting,
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

REVOKE ALL ON FUNCTION update_activity FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_activity TO authenticated;

-- ============================================================================
-- get_activity_by_invite_token — return level_max too (RETURNS TABLE + SELECT).
-- ============================================================================
DROP FUNCTION IF EXISTS get_activity_by_invite_token(UUID);
CREATE OR REPLACE FUNCTION get_activity_by_invite_token(
  p_token UUID
)
RETURNS TABLE (
  id UUID,
  creator_id UUID,
  sport_id UUID,
  title TEXT,
  description TEXT,
  level TEXT,
  level_max TEXT,
  max_participants INTEGER,
  starts_at TIMESTAMPTZ,
  duration INTERVAL,
  visibility TEXT,
  status TEXT,
  lng FLOAT,
  lat FLOAT,
  creator_name TEXT,
  creator_avatar TEXT,
  sport_key TEXT,
  sport_icon TEXT,
  sport_category TEXT,
  participant_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.level_max,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.status,
    ST_X(a.location_meeting::geometry)::FLOAT AS lng,
    ST_Y(a.location_meeting::geometry)::FLOAT AS lat,
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
  WHERE a.invite_token = p_token
    AND a.status IN ('published', 'in_progress')
    AND a.deleted_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION get_activity_by_invite_token(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_activity_by_invite_token(UUID) TO authenticated;

-- 7. get_activity_detail (returns the new view rowtype)
CREATE OR REPLACE FUNCTION get_activity_detail(
  p_activity_id UUID
)
RETURNS SETOF activities_with_coords
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
    a.distance_km, a.elevation_gain_m,
    a.max_participants, a.starts_at, a.duration, a.visibility,
    a.requires_presence,
    a.status, a.deleted_at, a.created_at, a.updated_at,
    a.objective_name, a.meeting_name,
    a.trace_geojson,
    ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
    ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
    ST_X(a.location_meeting::geometry) AS meeting_lng,
    ST_Y(a.location_meeting::geometry) AS meeting_lat,
    ST_X(a.location_end::geometry) AS end_lng,
    ST_Y(a.location_end::geometry) AS end_lat,
    ST_X(a.location_objective::geometry) AS objective_lng,
    ST_Y(a.location_objective::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
    a.level_max
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.id = p_activity_id
    AND a.deleted_at IS NULL
    AND NOT private.user_is_suspended(a.creator_id)
    -- Same blocked rule as the public view: hide if the viewer blocked the creator.
    AND a.creator_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
    -- Access gate: involved (creator or any participation) OR publicly listed.
    AND (
      a.creator_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.user_id = v_user_id
      )
      OR a.visibility IN ('public', 'approval')
    );
END;
$$;

REVOKE ALL ON FUNCTION get_activity_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_activity_detail(UUID) TO authenticated;

-- 8. Presence — same chain, start distance term removed
CREATE OR REPLACE FUNCTION public.confirm_presence_via_geo(
  p_activity_id uuid, p_lng double precision, p_lat double precision,
  p_captured_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_skip_push boolean DEFAULT true)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_window_anchor TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration, status, deleted_at, creator_id
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  -- Invariant: the creator's presence is never self-attested. No-op.
  IF v_user_id = v_creator_id THEN RETURN; END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    IF now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
      RAISE EXCEPTION 'junto.presence_window_closed';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'junto.presence_too_far';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id, p_skip_push);

  -- Rule A: a non-creator confirming proves the meetup → auto-validate the creator.
  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, p_activity_id, p_skip_push);
    END IF;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS get_my_active_presence_activities;
CREATE OR REPLACE FUNCTION public.get_my_active_presence_activities()
RETURNS TABLE(activity_id uuid, title text, starts_at timestamp with time zone, duration interval, meeting_lng double precision, meeting_lat double precision, end_lng double precision, end_lat double precision)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    a.id AS activity_id,
    a.title,
    a.starts_at,
    a.duration,
    ST_X(a.location_meeting::geometry)::float AS meeting_lng,
    ST_Y(a.location_meeting::geometry)::float AS meeting_lat,
    ST_X(a.location_end::geometry)::float AS end_lng,
    ST_Y(a.location_end::geometry)::float AS end_lat
  FROM activities a
  JOIN participations p ON p.activity_id = a.id
  WHERE p.user_id = v_user_id
    AND p.status = 'accepted'
    AND p.confirmed_present IS NULL
    AND a.creator_id != v_user_id          -- creator never self-confirms
    AND a.requires_presence = TRUE
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
    AND now() >= a.starts_at - INTERVAL '2 hours'
    AND now() <= a.starts_at + INTERVAL '15 minutes';
END;
$$;
REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities FROM anon;
GRANT EXECUTE ON FUNCTION get_my_active_presence_activities TO authenticated;

-- 9. Alert radius match on the single point
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
  SELECT a.id, a.creator_id, a.title, a.location_meeting,
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
      AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000)
  LOOP
    -- Per-user advisory lock so the count+insert is atomic vs. concurrent
    -- alert checks for the same user (multiple activities published in parallel).
    PERFORM pg_advisory_xact_lock(hashtext('alert_match_' || v_alert.user_id::text));

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
