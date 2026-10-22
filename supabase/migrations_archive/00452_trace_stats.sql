-- ============================================================================
-- 00452 — Distance and elevation gain derived from the trace (Scott 2026-10-16).
--
-- Until now distance_km / elevation_gain_m were typed by hand and a trace only
-- ever set trace_geojson. The server already knew how to measure a trace
-- (create_gpx_trace, 00320) — this wires it in, with a D+ computation on the
-- Z coordinate the GPX parser has kept all along.
--
-- Rule validated by Scott: the trace PREFILLS, it never overwrites — a value
-- the organiser typed wins; only NULL fields are derived.
--
--   trace_distance_km(jsonb)        internal, pure — PostGIS geography length
--   trace_elevation_gain_m(jsonb)   internal, pure — smoothed positive gain
--   compute_trace_stats(jsonb)      RPC — prefill before the activity exists
--   create_activity                 rebuilt from the LIVE body (00441) + fill
--   update_activity_trace           rebuilt from the LIVE body (00218) + fill
--   consume_trace_elevation_quota   per-user quota for the trace-elevation
--                                   edge function (IGN altimetry proxy)
--
-- D+ algorithm (what gpxpy / Strava / Garmin converge on): keep the Z list
-- only when ≥ 90 % of points carry one; 3-point weighted smoothing
-- (0.3 / 0.4 / 0.3); then a 5 m hysteresis — a reference altitude that only
-- moves when the smoothed profile strays ≥ 5 m from it, climbs summed. Raw
-- summation would inflate the gain by 30-50 % on GPS or DEM noise.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- trace_distance_km — internal, pure. NULL on anything that is not a
-- LineString of ≥ 2 points (callers already validate; this never throws).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trace_distance_km(p_geojson JSONB)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_geom geometry;
BEGIN
  IF p_geojson IS NULL THEN RETURN NULL; END IF;
  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString' OR ST_NPoints(v_geom) < 2 THEN
    RETURN NULL;
  END IF;
  RETURN round((ST_Length(v_geom::geography) / 1000)::numeric, 2);
END;
$$;

REVOKE ALL ON FUNCTION trace_distance_km(JSONB) FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- trace_elevation_gain_m — internal, pure. NULL when fewer than 90 % of the
-- points carry a Z (a 2D trace, or a GPX with sparse altitudes).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trace_elevation_gain_m(p_geojson JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c_threshold CONSTANT DOUBLE PRECISION := 5;
  v_raw DOUBLE PRECISION[];
  v_z DOUBLE PRECISION[];
  v_smooth DOUBLE PRECISION[];
  v_n INTEGER;
  v_with_z INTEGER;
  v_ref DOUBLE PRECISION;
  v_gain DOUBLE PRECISION := 0;
  i INTEGER;
BEGIN
  IF p_geojson IS NULL
     OR coalesce(p_geojson->>'type', '') <> 'LineString'
     OR jsonb_typeof(p_geojson->'coordinates') <> 'array' THEN
    RETURN NULL;
  END IF;

  -- Third coordinate of every point, NULL where absent or not a number.
  SELECT array_agg(
           CASE WHEN jsonb_typeof(c->2) = 'number' THEN (c->>2)::double precision END
           ORDER BY ord)
    INTO v_raw
  FROM jsonb_array_elements(p_geojson->'coordinates') WITH ORDINALITY AS t(c, ord);

  v_n := coalesce(array_length(v_raw, 1), 0);
  IF v_n < 2 THEN RETURN NULL; END IF;

  SELECT count(*) INTO v_with_z FROM unnest(v_raw) AS u(z) WHERE z IS NOT NULL;
  IF v_with_z < 2 OR v_with_z < ceil(v_n * 0.9) THEN RETURN NULL; END IF;

  -- Drop the gaps (neighbours join across them, as gpxpy does).
  SELECT array_agg(z ORDER BY ord) INTO v_z
  FROM unnest(v_raw) WITH ORDINALITY AS u(z, ord)
  WHERE z IS NOT NULL;
  v_n := array_length(v_z, 1);

  -- 3-point weighted smoothing; the ends keep their raw value.
  v_smooth := v_z;
  FOR i IN 2..(v_n - 1) LOOP
    v_smooth[i] := 0.3 * v_z[i - 1] + 0.4 * v_z[i] + 0.3 * v_z[i + 1];
  END LOOP;

  -- Hysteresis: the reference only moves on a ≥ 5 m excursion.
  v_ref := v_smooth[1];
  FOR i IN 2..v_n LOOP
    IF v_smooth[i] - v_ref >= c_threshold THEN
      v_gain := v_gain + (v_smooth[i] - v_ref);
      v_ref := v_smooth[i];
    ELSIF v_ref - v_smooth[i] >= c_threshold THEN
      v_ref := v_smooth[i];
    END IF;
  END LOOP;

  RETURN round(v_gain)::integer;
END;
$$;

REVOKE ALL ON FUNCTION trace_elevation_gain_m(JSONB) FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- compute_trace_stats — RPC used by the creation form to prefill distance / D+
-- before the activity exists. Pure computation on the caller's own payload:
-- auth · not-suspended · LineString 2..10000 points (same code as 00320).
-- No data access, no quota (milliseconds, nothing to drain).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_trace_stats(p_geojson JSONB)
RETURNS TABLE (distance_km NUMERIC, elevation_gain_m INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_geom geometry;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString'
     OR ST_NPoints(v_geom) < 2
     OR ST_NPoints(v_geom) > 10000 THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  RETURN QUERY SELECT trace_distance_km(p_geojson), trace_elevation_gain_m(p_geojson);
END;
$$;

REVOKE ALL ON FUNCTION compute_trace_stats(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION compute_trace_stats(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION compute_trace_stats(JSONB) TO authenticated;

-- ----------------------------------------------------------------------------
-- create_activity — LIVE body = 00441, unchanged except the two fills below
-- (distance / D+ derived from the trace only when the client sends NULL).
-- ----------------------------------------------------------------------------
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
  v_distance_km NUMERIC;
  v_elevation_gain_m INTEGER;
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

  -- Trace-derived prefill (00452): the typed value always wins.
  v_distance_km := p_distance_km;
  v_elevation_gain_m := p_elevation_gain_m;
  IF p_trace_geojson IS NOT NULL THEN
    IF v_distance_km IS NULL THEN v_distance_km := trace_distance_km(p_trace_geojson); END IF;
    IF v_elevation_gain_m IS NULL THEN v_elevation_gain_m := trace_elevation_gain_m(p_trace_geojson); END IF;
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
    v_distance_km,
    v_elevation_gain_m,
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

-- ----------------------------------------------------------------------------
-- update_activity_trace — LIVE body = 00218, chain unchanged (auth · not
-- suspended · creator · published/in_progress · not deleted). Setting a trace
-- fills distance / D+ only where the activity has NULL; removing a trace
-- leaves the figures alone.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_activity_trace(
  p_activity_id UUID,
  p_trace_geojson JSONB
)
RETURNS VOID
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

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND creator_id = v_user_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson,
      distance_km = CASE
        WHEN p_trace_geojson IS NOT NULL AND distance_km IS NULL
          THEN trace_distance_km(p_trace_geojson)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN trace_elevation_gain_m(p_trace_geojson)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
END;
$$;

REVOKE ALL ON FUNCTION update_activity_trace(UUID, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION update_activity_trace(UUID, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION update_activity_trace(UUID, JSONB) TO authenticated;

-- ----------------------------------------------------------------------------
-- Per-user quota for the trace-elevation edge function (IGN altimetry proxy):
-- same model as snap_trail_calls (00346). 30 traces / rolling hour — a trace
-- is enriched once when it is set; nobody legitimately needs more.
-- ----------------------------------------------------------------------------
CREATE TABLE trace_elevation_calls (
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  called_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX trace_elevation_calls_user_idx ON trace_elevation_calls(user_id, called_at DESC);

ALTER TABLE trace_elevation_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE trace_elevation_calls FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trace_elevation_calls FROM anon, authenticated;

CREATE OR REPLACE FUNCTION consume_trace_elevation_quota()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_count INTEGER;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_trace_elevation'));
  DELETE FROM trace_elevation_calls WHERE user_id = v_user AND called_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM trace_elevation_calls WHERE user_id = v_user;
  IF v_count >= 30 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO trace_elevation_calls (user_id) VALUES (v_user);
END;
$$;
REVOKE ALL ON FUNCTION consume_trace_elevation_quota() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION consume_trace_elevation_quota() TO authenticated;
