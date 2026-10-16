-- ============================================================================
-- 00453 — Elevation gain on the personal GPX library (Scott 2026-10-16:
-- « le dénivelé n'apparaît que dans la création d'activité, pas dans la
-- bibliothèque »). Same derivation as activities (trace_elevation_gain_m,
-- 00452); the client gives drawn traces their altitudes before saving.
--
--   gpx_traces.elevation_gain_m   nullable (no altitudes → NULL), backfilled
--   create_gpx_trace              rebuilt from the LIVE body (00324), chain
--                                 unchanged, + elevation_gain_m
-- ============================================================================

ALTER TABLE gpx_traces
  ADD COLUMN elevation_gain_m INTEGER
  CHECK (elevation_gain_m IS NULL OR elevation_gain_m >= 0);

-- One-off backfill: traces imported from a GPX already carry Z.
UPDATE gpx_traces SET elevation_gain_m = trace_elevation_gain_m(geojson);

-- ----------------------------------------------------------------------------
-- create_gpx_trace — LIVE body = 00324. Chain: auth · not-suspended · name
-- 1..80 · geojson LineString 2..10000 pts · quota < 50 (advisory-locked) ·
-- distance / D+ / user_id / timestamps hardcoded.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_gpx_trace(
  p_name TEXT,
  p_geojson JSONB
)
RETURNS gpx_traces
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_geom geometry;
  v_distance_km NUMERIC(7,2);
  v_elevation_gain_m INTEGER;
  v_count INTEGER;
  v_row gpx_traces;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_name := trim(p_name);
  IF char_length(v_name) < 1 OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.trace_name_invalid';
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

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_gpx_trace'));
  SELECT count(*) INTO v_count FROM gpx_traces WHERE user_id = v_user_id;
  IF v_count >= 50 THEN
    RAISE EXCEPTION 'junto.trace_quota_reached';
  END IF;

  v_distance_km := round((ST_Length(v_geom::geography) / 1000)::numeric, 2);
  v_elevation_gain_m := trace_elevation_gain_m(p_geojson);

  INSERT INTO gpx_traces (user_id, name, geojson, distance_km, elevation_gain_m, created_at, updated_at)
  VALUES (v_user_id, v_name, p_geojson, v_distance_km, v_elevation_gain_m, now(), now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION create_gpx_trace(TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION create_gpx_trace(TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION create_gpx_trace(TEXT, JSONB) TO authenticated;
