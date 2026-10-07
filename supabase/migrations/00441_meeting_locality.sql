-- ============================================================================
-- 00441 — Meeting locality (Scott 2026-10-07): the rendez-vous point is always
-- an exact pin, but its NAME is a free-text field the creator may leave empty
-- or fill with « parking de la ferme » — meaningless to anyone who does not
-- know the valley, unusable on the website's departures board.
--
-- New column activities.meeting_locality: the village / hamlet / commune the
-- pin falls in, reverse-geocoded by the CLIENT (Photon) when the pin is
-- placed, sent with create_activity. Same trust level as meeting_name (user-
-- provided text, length-capped), same exposure (everywhere meeting_name is
-- selected), frozen after creation like meeting_name — except alongside a
-- pin move in update_activity, before anyone has joined.
--
-- Live bases (verified, every later redefinition listed before choosing):
--   create_activity / update_activity ← 00316 ; handle_activity_update ← 00333 ;
--   activities_with_coords ← 00333 (NOT 00315: 00333 added the demo curtain) ;
--   get_activity_detail ← 00347.
-- Adding a trailing parameter to an existing function creates a PostgREST
-- overload (PGRST203) → the old signatures are dropped first (pattern 00274/00306).
--
-- Backfill: demo outings get their locality from their meeting_name (mostly a
-- village already); real activities stay NULL and the client falls back to
-- meeting_name. No HTTP from the database.
-- ============================================================================

ALTER TABLE activities
  ADD COLUMN IF NOT EXISTS meeting_locality TEXT
  CHECK (meeting_locality IS NULL OR char_length(meeting_locality) BETWEEN 1 AND 80);

-- ---------- 1. Whitelist trigger (base 00333) ----------
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
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.meeting_name := OLD.meeting_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;
  NEW.is_demo := OLD.is_demo;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.level_max := OLD.level_max;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
  END IF;

  -- 00441: the locality follows the meeting pin and nothing else — it may
  -- only change in the same UPDATE that moves location_meeting (which the
  -- participant lock above already freezes once someone has joined).
  IF NEW.location_meeting IS NOT DISTINCT FROM OLD.location_meeting THEN
    NEW.meeting_locality := OLD.meeting_locality;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------- 2. create_activity (base 00316) ----------
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
  p_level_max TEXT DEFAULT NULL,
  p_meeting_locality TEXT DEFAULT NULL
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

  -- Private-link visibilities are open to everyone (Scott 2026-07-10):
  -- all tiers are free at launch. Premium gate removed.

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
    location_objective, objective_name, meeting_name, meeting_locality,
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
    CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
      THEN left(trim(p_meeting_locality), 80) ELSE NULL END,
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
REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

-- ============================================================================
-- 3. update_activity — premium gate removed
-- ============================================================================

-- ---------- 3. update_activity (base 00316) ----------
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
  p_level_max TEXT DEFAULT NULL,
  p_meeting_locality TEXT DEFAULT NULL
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

  -- The client resends starts_at as an ISO string (millisecond precision)
  -- while Postgres stores microseconds — a raw IS DISTINCT FROM would see a
  -- sub-millisecond ghost diff on any row whose date has non-zero µs (seed,
  -- manual INSERTs) and re-trigger the date_in_past bug plus phantom
  -- "activity updated" notifs. Normalise: an unchanged-at-ms-precision date
  -- is treated as "not provided" for everything downstream (validation,
  -- UPDATE, change diff).
  IF p_starts_at IS NOT NULL
     AND date_trunc('milliseconds', p_starts_at) IS NOT DISTINCT FROM date_trunc('milliseconds', v_old.starts_at) THEN
    p_starts_at := NULL;
  END IF;

  -- Only validate the date when it actually changes — resending the
  -- unchanged (now past) starts_at of an in-progress activity is not a
  -- reschedule and must not block editing the other fields.
  IF p_starts_at IS NOT NULL THEN
    IF p_starts_at <= NOW() THEN
      RAISE EXCEPTION 'junto.date_in_past';
    END IF;
    IF p_starts_at > NOW() + INTERVAL '6 months' THEN
      RAISE EXCEPTION 'junto.date_too_far';
    END IF;
  END IF;

  -- p_max_participants = 0 is the explicit "make it open" sentinel (NULL
  -- means "unchanged", so it can't express open — the edit screen's open
  -- toggle silently did nothing before this). 0 sits outside the valid
  -- [2,50] range so it can't collide with a real cap. Any other
  -- out-of-range value is rejected (parity with create_activity — before
  -- this it surfaced as a raw table CHECK violation).
  IF p_max_participants IS NOT NULL AND p_max_participants != 0
     AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic. Parity with create_activity.
  IF p_visibility IS NOT NULL
     AND p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Private-link visibilities open to all (Scott 2026-07-10) — no gate.

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    level_max = CASE WHEN p_level IS NOT NULL THEN v_level_max ELSE level_max END,
    max_participants = CASE
      WHEN p_max_participants = 0 THEN NULL
      WHEN p_max_participants IS NOT NULL THEN p_max_participants
      ELSE max_participants END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting END,
    -- Only alongside a pin move (00441); the trigger freezes it otherwise.
    meeting_locality = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
                THEN left(trim(p_meeting_locality), 80) ELSE NULL END
      ELSE meeting_locality END,
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
REVOKE EXECUTE ON FUNCTION update_activity FROM anon;
GRANT EXECUTE ON FUNCTION update_activity TO authenticated;

-- ---------- 4. activities_with_coords (base 00333) ----------
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
  a.level_max,
  a.meeting_locality
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress')
  AND (a.is_demo = false OR demo_content_visible())
  AND (
    a.visibility IN ('public', 'approval')
    OR (
      a.visibility IN ('private_link', 'private_link_approval')
      AND (
        a.creator_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM participations p2
          WHERE p2.activity_id = a.id
            AND p2.user_id = auth.uid()
            AND p2.status = 'accepted'
        )
      )
    )
  )
  AND NOT private.user_is_suspended(a.creator_id)
  AND a.creator_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

-- ---------- 5. get_activity_detail (base 00347) ----------
CREATE OR REPLACE FUNCTION get_activity_detail(p_activity_id UUID)
RETURNS SETOF activities_with_coords
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
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
    a.level_max,
    a.meeting_locality
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.id = p_activity_id
    AND a.deleted_at IS NULL
    AND (a.is_demo = false OR demo_content_visible())
    AND NOT private.user_is_suspended(a.creator_id)
    AND a.creator_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
    AND (
      a.creator_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.user_id = v_user_id
          AND p.status IN ('accepted', 'pending')
      )
      OR a.visibility IN ('public', 'approval')
    );
END;
$$;

REVOKE ALL ON FUNCTION get_activity_detail(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_activity_detail(UUID) TO authenticated;

-- ---------- 6. Demo outings: locality derived from their meeting name ----------
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities SET meeting_locality = CASE meeting_name
    WHEN 'Briançon gare' THEN 'Briançon'
    WHEN 'Atterrissage de Briançon' THEN 'Briançon'
    WHEN 'Décollage du Prorel' THEN 'Briançon'
    WHEN 'Parking de Puy-Chalvin (avant la ferme)' THEN 'Puy-Chalvin'
    WHEN 'Plan d''eau d''Embrun' THEN 'Embrun'
    WHEN 'Les Orres 1650' THEN 'Les Orres'
    WHEN 'Vars Sainte-Marie' THEN 'Vars'
    WHEN 'Col du Granon' THEN 'Saint-Chaffrey'
    WHEN 'Hameau des Combes' THEN 'Les Combes'
    ELSE left(meeting_name, 80)
  END
  WHERE is_demo = true AND meeting_name IS NOT NULL AND meeting_locality IS NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
