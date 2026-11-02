-- Waypoints on a LIBRARY trace (Scott 2026-11-02): « dans ta bibliothèque, tu
-- peux modifier la trace et y rajouter des étapes ». Only the waypoints member
-- of the stored GeoJSON is replaced — the line itself never changes here.
CREATE OR REPLACE FUNCTION public.set_gpx_trace_waypoints(p_id uuid, p_waypoints jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_geojson JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('gpx_waypoints', 60, INTERVAL '1 hour');

  -- Ownership: exists AND mine. Generic error either way.
  SELECT geojson INTO v_geojson FROM gpx_traces WHERE id = p_id AND user_id = v_user_id FOR UPDATE;
  IF v_geojson IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_geojson := v_geojson - 'waypoints';
  IF p_waypoints IS NOT NULL AND jsonb_typeof(p_waypoints) = 'array' AND jsonb_array_length(p_waypoints) > 0 THEN
    v_geojson := v_geojson || jsonb_build_object('waypoints', p_waypoints);
  ELSIF p_waypoints IS NOT NULL AND jsonb_typeof(p_waypoints) <> 'array' THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;
  -- Same gate as every trace path (00570).
  IF NOT trace_geojson_ok(v_geojson) THEN RAISE EXCEPTION 'junto.trace_geojson_invalid'; END IF;

  UPDATE gpx_traces SET geojson = v_geojson, updated_at = now()
  WHERE id = p_id AND user_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_gpx_trace_waypoints(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_gpx_trace_waypoints(uuid, jsonb) TO authenticated;
