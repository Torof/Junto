-- Migration 00062: confirm_presence_via_geo accepts proximity to any of the activity's points
-- (location_start, location_meeting, or location_end). Was previously start only.

CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT
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
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT _is_presence_window(p_activity_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_already_confirmed THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    ST_Distance(location_start, v_user_point),
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start, 999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end, 999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations
  SET confirmed_present = now()
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;
