-- ============================================================================
-- 00377 — Discovery: get_my_dispo() so the composer can load/edit the caller's
-- dispo (base GEOGRAPHY → lng/lat via ST_X/ST_Y; own row only).
-- ============================================================================

CREATE OR REPLACE FUNCTION get_my_dispo()
RETURNS TABLE (
  id UUID, sport_keys TEXT[], levels JSONB,
  base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, base_label TEXT,
  radius_km INTEGER, transport_modes TEXT[],
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, is_active BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT id, sport_keys, levels,
         ST_X(base::geometry), ST_Y(base::geometry), base_label,
         radius_km, transport_modes, window_start, window_end, is_active
  FROM discovery_availabilities
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION get_my_dispo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_dispo() TO authenticated;
