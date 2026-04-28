-- Migration 00149: validate geo presence against the route polyline too,
-- not just start/meeting/end coordinates.
--
-- For long activities (alpinism, ski touring, hikes) the user can be on
-- the actual route at km 5 of a 10 km approach without being within 150 m
-- of the start, meeting, or end pins. Currently that's a false-negative —
-- the geofence Enter event never fires (and the foreground watcher
-- rejects too) because all distance checks miss.
--
-- When the activity has a `trace_geojson` (LineString stored as JSONB),
-- include its distance to the user's point in the LEAST() pick. The
-- trace is parsed on demand via ST_GeomFromGeoJSON and cast to geography
-- so distances come out in meters. This is the same conversion the
-- frontend does to render the route, so no schema change is needed.
--
-- Both the live and replay paths in confirm_presence_via_geo are updated.

CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT,
  p_captured_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_start FLOAT;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_window_anchor TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    IF now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    ST_Distance(location_start, v_user_point),
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start,   999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ) FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ) TO authenticated;
