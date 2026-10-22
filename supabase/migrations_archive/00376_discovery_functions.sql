-- ============================================================================
-- 00376 — Discovery (axe D) B2: the dispo functions (auth chains validated).
--   upsert_dispo · activate_dispo / deactivate_dispo · get_discovery_count
--   (fuzzy, floored) · get_discovery_cards (requires active = reciprocity).
-- Contact reuses send_contact_request(initiated_from='discovery').
-- Matching = sport overlap ∩ zone overlap (ST_DWithin r_a+r_b) ∩ window overlap;
-- suspension + bidirectional block filtered everywhere. Others' base/radius are
-- never returned — only distance-from-you.
-- ============================================================================

-- upsert_dispo — create/edit the caller's single dispo (v1). Does NOT activate.
CREATE OR REPLACE FUNCTION upsert_dispo(
  p_sport_keys TEXT[],
  p_levels JSONB,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_transport_modes TEXT[],
  p_window_start TIMESTAMPTZ,
  p_window_end TIMESTAMPTZ
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_id UUID;
  v_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR array_length(p_sport_keys, 1) NOT BETWEEN 1 AND 3
     OR EXISTS (SELECT 1 FROM unnest(p_sport_keys) k
                WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k AND s.is_active))
  THEN RAISE EXCEPTION 'junto.dispo_sports'; END IF;

  IF p_radius_km IS NOT NULL AND p_radius_km NOT IN (5, 10, 15, 30, 50) THEN
    RAISE EXCEPTION 'junto.dispo_radius';
  END IF;

  IF p_transport_modes IS NULL OR array_length(p_transport_modes, 1) IS NULL
     OR array_length(p_transport_modes, 1) < 1
     OR NOT (p_transport_modes <@ ARRAY['car', 'motorbike', 'bike', 'on_foot', 'public_transport'])
  THEN RAISE EXCEPTION 'junto.dispo_transport'; END IF;

  IF p_window_start IS NULL OR p_window_end IS NULL OR p_window_end <= p_window_start
     OR p_window_end > now() + INTERVAL '4 weeks' OR p_window_start < now() - INTERVAL '1 day'
  THEN RAISE EXCEPTION 'junto.dispo_window'; END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90
  THEN RAISE EXCEPTION 'junto.dispo_place'; END IF;

  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.dispo_place';
  END IF;

  -- One row per user in v1. Content columns are mutable; is_active/user_id are
  -- frozen by the whitelist trigger, so editing keeps an active dispo visible.
  SELECT id INTO v_id FROM discovery_availabilities WHERE user_id = v_user_id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO discovery_availabilities
      (user_id, sport_keys, levels, base, base_label, radius_km, transport_modes, window_start, window_end)
    VALUES
      (v_user_id, p_sport_keys, p_levels,
       ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography,
       v_label, p_radius_km, p_transport_modes, p_window_start, p_window_end)
    RETURNING id INTO v_id;
  ELSE
    UPDATE discovery_availabilities SET
      sport_keys = p_sport_keys, levels = p_levels,
      base = ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography,
      base_label = v_label, radius_km = p_radius_km, transport_modes = p_transport_modes,
      window_start = p_window_start, window_end = p_window_end
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

-- activate_dispo — become visible (and able to see cards). One active per user.
CREATE OR REPLACE FUNCTION activate_dispo()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM discovery_availabilities WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';  -- compose first
  END IF;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE discovery_availabilities SET is_active = true WHERE user_id = v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION deactivate_dispo()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE discovery_availabilities SET is_active = false WHERE user_id = v_user_id;
END;
$$;

-- get_discovery_count — live counter during compose (no active dispo required —
-- counters are free; seeing PEOPLE requires activating). Returns only a number;
-- floored to -1 ("quelques") when 1–2 so a near-unique person can't be singled out.
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

-- get_discovery_cards — the matches for the caller's ACTIVE dispo (reciprocity).
-- Never returns the other's base/radius — only distance-from-you.
CREATE OR REPLACE FUNCTION get_discovery_cards()
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  sport_keys TEXT[], levels JSONB, transport_modes TEXT[],
  distance_km DOUBLE PRECISION, sorties_count INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;  -- reciprocity: must be active to see

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes,
         (ST_Distance(d.base, v_base) / 1000.0) AS distance_km,
         (SELECT count(*)::int FROM participations p
          WHERE p.user_id = d.user_id AND p.status = 'accepted') AS sorties_count
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (v_radius IS NULL OR d.radius_km IS NULL
         OR ST_DWithin(d.base, v_base, (v_radius + d.radius_km) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  ORDER BY pp.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$$;

REVOKE ALL ON FUNCTION upsert_dispo(TEXT[], JSONB, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION upsert_dispo(TEXT[], JSONB, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
REVOKE ALL ON FUNCTION activate_dispo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION activate_dispo() TO authenticated;
REVOKE ALL ON FUNCTION deactivate_dispo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION deactivate_dispo() TO authenticated;
REVOKE ALL ON FUNCTION get_discovery_count(TEXT[], DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_count(TEXT[], DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
REVOKE ALL ON FUNCTION get_discovery_cards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_cards() TO authenticated;
