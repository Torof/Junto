-- Migration 00320: personal GPX trace library (gpx_traces)
--
-- Scott's feature (2026-07-12): let users DRAW a straight-line trace ("as the
-- crow flies between waypoints") in-app and keep it in a personal library,
-- reached from the tab-bar burger menu ("Mes traces GPX"). The app already
-- imports / exports / displays / shares GPX (parse-gpx, geojson-to-gpx,
-- routeLine, shareTrace) — this adds the missing "create + store" upstream.
--
-- Junto is an organiser, not Strava: the trace is a rough visual of the plan,
-- not a precise topo — hence straight segments, no snap-to-trail. A trace is a
-- purely personal asset: owner-only, never public.
--
-- Security: reads via owner-only RLS; writes ONLY via SECURITY DEFINER
-- functions (direct INSERT/UPDATE/DELETE revoked), so geojson validation,
-- server-computed distance, name limits and the 50-trace quota can't be
-- bypassed. Nothing granted to anon. Authorization chains validated by Scott.

-- ============================================================================
-- TABLE
-- ============================================================================
CREATE TABLE gpx_traces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
  geojson JSONB NOT NULL,
  distance_km NUMERIC(7,2) NOT NULL CHECK (distance_km >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gpx_traces_user ON gpx_traces(user_id, created_at DESC);

ALTER TABLE gpx_traces ENABLE ROW LEVEL SECURITY;
ALTER TABLE gpx_traces FORCE ROW LEVEL SECURITY;

-- Read: owner only. Writes go through the functions below.
CREATE POLICY "gpx_traces_select_own"
  ON gpx_traces FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- No direct writes; SECURITY DEFINER functions (run as owner) handle them.
REVOKE ALL ON gpx_traces FROM anon;
REVOKE ALL ON gpx_traces FROM authenticated;
GRANT SELECT ON gpx_traces TO authenticated;

-- ============================================================================
-- create_gpx_trace — validate + server-compute distance + quota, then insert.
-- Chain: auth · not-suspended · name 1..80 · geojson LineString 2..5000 pts ·
--        quota < 50 (advisory-locked) · distance/user_id/timestamps hardcoded.
-- ============================================================================
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

  -- The geojson must be a real LineString of 2..5000 points. ST_GeomFromGeoJSON
  -- throws on malformed input; catch it and surface the same generic-input code.
  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString'
     OR ST_NPoints(v_geom) < 2
     OR ST_NPoints(v_geom) > 5000 THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  -- Quota: 50 stored traces per user (delete old ones to free space).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_gpx_trace'));
  SELECT count(*) INTO v_count FROM gpx_traces WHERE user_id = v_user_id;
  IF v_count >= 50 THEN
    RAISE EXCEPTION 'junto.trace_quota_reached';
  END IF;

  v_distance_km := round((ST_Length(v_geom::geography) / 1000)::numeric, 2);

  INSERT INTO gpx_traces (user_id, name, geojson, distance_km, created_at, updated_at)
  VALUES (v_user_id, v_name, p_geojson, v_distance_km, now(), now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION create_gpx_trace(TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION create_gpx_trace(TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION create_gpx_trace(TEXT, JSONB) TO authenticated;

-- ============================================================================
-- rename_gpx_trace — auth · not-suspended · ownership (generic) · name 1..80.
-- ============================================================================
CREATE OR REPLACE FUNCTION rename_gpx_trace(
  p_id UUID,
  p_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Ownership: exists AND mine. Generic error either way (don't reveal the id).
  IF NOT EXISTS (SELECT 1 FROM gpx_traces WHERE id = p_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_name := trim(p_name);
  IF char_length(v_name) < 1 OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.trace_name_invalid';
  END IF;

  UPDATE gpx_traces SET name = v_name, updated_at = now()
  WHERE id = p_id AND user_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION rename_gpx_trace(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION rename_gpx_trace(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION rename_gpx_trace(UUID, TEXT) TO authenticated;

-- ============================================================================
-- delete_gpx_trace — auth · not-suspended · ownership (generic) · delete.
-- ============================================================================
CREATE OR REPLACE FUNCTION delete_gpx_trace(p_id UUID)
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

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM gpx_traces WHERE id = p_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM gpx_traces WHERE id = p_id AND user_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION delete_gpx_trace(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION delete_gpx_trace(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION delete_gpx_trace(UUID) TO authenticated;
