-- GPX waypoints (Scott 2026-11-02, option 2): named stops on a trace
-- (refuge, bivouac, water, viewpoint, picnic, parking, summit, delicate
-- passage, other). They live INSIDE the trace GeoJSON as a foreign member
-- `waypoints` (allowed by RFC 7946 §6.1), so they follow the trace wherever it
-- already goes (activity, library, chat share) with no signature change.
-- trace_geojson_ok becomes the single gate: it validates the waypoints and
-- now refuses any other unknown top-level member (was silently accepted).
--   waypoints: ≤ 30 × { lng, lat, kind, name? }  name: 1-60 chars, no < > or
--   control characters.

CREATE OR REPLACE FUNCTION public.trace_geojson_ok(p_geojson jsonb)
RETURNS boolean
LANGUAGE plpgsql STABLE
SET search_path = public, extensions
AS $_$
DECLARE
  w jsonb;
BEGIN
  -- 00484: never NULL — callers write `IF NOT trace_geojson_ok(x)`.
  IF p_geojson IS NULL OR jsonb_typeof(p_geojson) <> 'object' THEN RETURN false; END IF;
  IF pg_column_size(p_geojson) > 1000000 THEN RETURN false; END IF;
  IF NOT (p_geojson ? 'type' AND p_geojson ? 'coordinates') THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_geojson) k WHERE k NOT IN ('type', 'coordinates', 'waypoints')) THEN
    RETURN false;
  END IF;
  IF p_geojson->>'type' IS DISTINCT FROM 'LineString'
     OR jsonb_typeof(p_geojson->'coordinates') <> 'array'
     OR jsonb_array_length(p_geojson->'coordinates') NOT BETWEEN 2 AND 10000 THEN
    RETURN false;
  END IF;
  -- Same per-point rules as before (00470), evaluated in C by jsonpath.
  IF jsonb_path_exists(p_geojson, 'strict $.coordinates[*] ? (
         @.type() != "array"
      || @.size() < 2 || @.size() > 4
      || @[0].type() != "number" || @[1].type() != "number"
      || @[0] < -180 || @[0] > 180 || @[1] < -90 || @[1] > 90
      || (@.size() >= 3 && @[2].type() != "number" && @[2].type() != "null")
      || (@.size() >= 3 && @[2].type() == "number" && (@[2] < -100000 || @[2] > 100000))
      || (@.size() == 4 && @[3].type() != "number" && @[3].type() != "null")
      || (@.size() == 4 && @[3].type() == "number" && (@[3] < -1e13 || @[3] > 1e13))
      || (@[0] != 0 && @[0] > -1e-300 && @[0] < 1e-300)
      || (@[1] != 0 && @[1] > -1e-300 && @[1] < 1e-300)
      || (@.size() >= 3 && @[2].type() == "number" && @[2] != 0 && @[2] > -1e-300 && @[2] < 1e-300)
      || (@.size() == 4 && @[3].type() == "number" && @[3] != 0 && @[3] > -1e-300 && @[3] < 1e-300)
    )', '{}', true) THEN
    RETURN false;
  END IF;

  IF p_geojson ? 'waypoints' THEN
    IF jsonb_typeof(p_geojson->'waypoints') <> 'array' OR jsonb_array_length(p_geojson->'waypoints') > 30 THEN
      RETURN false;
    END IF;
    FOR w IN SELECT value FROM jsonb_array_elements(p_geojson->'waypoints') LOOP
      IF jsonb_typeof(w) <> 'object' THEN RETURN false; END IF;
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(w) k WHERE k NOT IN ('lng', 'lat', 'kind', 'name')) THEN
        RETURN false;
      END IF;
      IF jsonb_typeof(w->'lng') IS DISTINCT FROM 'number' OR jsonb_typeof(w->'lat') IS DISTINCT FROM 'number' THEN
        RETURN false;
      END IF;
      IF (w->>'lng')::float8 NOT BETWEEN -180 AND 180 OR (w->>'lat')::float8 NOT BETWEEN -90 AND 90 THEN
        RETURN false;
      END IF;
      IF w->>'kind' IS NULL OR w->>'kind' NOT IN
         ('refuge', 'camp', 'water', 'viewpoint', 'food', 'parking', 'summit', 'danger', 'other') THEN
        RETURN false;
      END IF;
      IF w ? 'name' AND (
           jsonb_typeof(w->'name') <> 'string'
           OR char_length(w->>'name') NOT BETWEEN 1 AND 60
           OR w->>'name' ~ '[<>[:cntrl:]]') THEN
        RETURN false;
      END IF;
    END LOOP;
  END IF;
  RETURN true;
END;
$_$;

REVOKE ALL ON FUNCTION public.trace_geojson_ok(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trace_geojson_ok(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
DECLARE
  v_user_id UUID;
  v_old_trace JSONB;
  v_title TEXT;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_trace', 20, INTERVAL '1 hour');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND creator_id = v_user_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): same gate as create_activity.
  -- 00483: an invalid trace is REPORTED, not raised, so the frequency
  -- counter above stays committed (a raise rolled it back and made the
  -- failing path free). NULL = saved; a junto.<code> = refused.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RETURN 'junto.trace_geojson_invalid';
  END IF;

  SELECT trace_geojson, title INTO v_old_trace, v_title FROM activities WHERE id = p_activity_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson,
      distance_km = CASE
        WHEN p_trace_geojson IS NOT NULL AND distance_km IS NULL
          THEN (SELECT CASE WHEN round(d, 1) > 0 AND d <= 9999 THEN d END FROM (SELECT trace_distance_km(p_trace_geojson) AS d) x)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN (SELECT CASE WHEN g > 0 AND g <= 99999 THEN g END FROM (SELECT trace_elevation_gain_m(p_trace_geojson) AS g) x)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  -- 00475 (audit L9, Scott 2026-10-21): the route is part of what people
  -- signed up for — a changed trace notifies the accepted participants, like
  -- an hour or meeting-point change does in update_activity.
  -- 00570: only a changed PATH notifies — adding or editing a waypoint
  -- (refuge, water…) on the same route is not « a new itinerary ».
  IF v_old_trace->'coordinates' IS DISTINCT FROM p_trace_geojson->'coordinates' THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_updated',
        'Itinéraire modifié',
        '« ' || v_title || ' » a un nouvel itinéraire — jette un œil à la trace.',
        jsonb_build_object('activity_id', p_activity_id,
          'changes', jsonb_build_object('trace', true),
          'variant', 'trace',
          'params', jsonb_build_object('title', v_title))
      );
    END LOOP;
  END IF;
  RETURN NULL;
END;
$$;
