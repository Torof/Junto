-- ============================================================================
-- 00407 — Audit phase 4: get_discovery_count suspended-caller guard.
--
-- Every other discovery function rejects a suspended caller; the count probe
-- only checked auth.uid() IS NULL. Add the standard suspended guard (return 0)
-- for consistency / defense-in-depth. (Scott 2026-09-09, post-audit.)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_discovery_count(
  p_sport_keys TEXT[],
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_radius_km INTEGER,
  p_window_start TIMESTAMPTZ,
  p_window_end TIMESTAMPTZ
) RETURNS INTEGER
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN 0; END IF;
  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_window_start IS NULL OR p_window_end IS NULL THEN
    RETURN 0;
  END IF;
  v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;

  SELECT count(*) INTO v_count
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && p_sport_keys
    AND tstzrange(d.window_start, d.window_end) && tstzrange(p_window_start, p_window_end)
    AND (p_radius_km IS NULL OR d.radius_km IS NULL
         OR ST_DWithin(d.base, v_base, (p_radius_km + d.radius_km) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id));

  IF v_count > 0 AND v_count <= 2 THEN RETURN -1; END IF;  -- -1 = "quelques"
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION get_discovery_count(TEXT[], DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_count(TEXT[], DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
