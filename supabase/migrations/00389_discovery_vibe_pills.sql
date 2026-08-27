-- ============================================================================
-- 00389 — Discovery: "vibe pills" (Scott 2026-08-27, Tinder-inspired). The
-- single-purpose `intent` field becomes one unified pill set (kept on the same
-- `intent` column to avoid churn) — ambiance + compagnie + rythme, ≤6, closed
-- vocabulary. GIN index so future matching/sort can query overlap (`&&`) like
-- sport_keys. The 5 existing intent values stay valid (subset of the new set).
-- ============================================================================

ALTER TABLE discovery_availabilities DROP CONSTRAINT IF EXISTS discovery_availabilities_intent_check;
ALTER TABLE discovery_availabilities
  ADD CONSTRAINT discovery_availabilities_intent_check
  CHECK (
    intent IS NULL
    OR (intent <@ ARRAY[
          'discovery','progression','performance','detente','conviviality',
          'dog','child','group','solo','active','calm','early'
        ]::text[]
        AND cardinality(intent) BETWEEN 1 AND 6)
  );

CREATE INDEX IF NOT EXISTS discovery_availabilities_intent_gin ON discovery_availabilities USING GIN (intent);

-- upsert_dispo — same signature; only the intent validation widens (≤6, new vocab).
CREATE OR REPLACE FUNCTION upsert_dispo(
  p_sport_keys TEXT[],
  p_levels JSONB,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_transport_modes TEXT[],
  p_window_start TIMESTAMPTZ,
  p_window_end TIMESTAMPTZ,
  p_intent TEXT[] DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_id UUID;
  v_label TEXT;
  v_intent TEXT[];
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

  IF p_levels IS NOT NULL AND jsonb_typeof(p_levels) = 'object'
     AND EXISTS (
       SELECT 1 FROM jsonb_object_keys(p_levels) AS lk(sport)
       WHERE lk.sport <> ALL(p_sport_keys)
     )
  THEN RAISE EXCEPTION 'junto.dispo_levels'; END IF;

  -- Vibe pills: optional, ≤6, closed vocabulary. Empty array normalises to NULL.
  IF p_intent IS NULL OR cardinality(p_intent) = 0 THEN
    v_intent := NULL;
  ELSIF NOT (p_intent <@ ARRAY[
              'discovery','progression','performance','detente','conviviality',
              'dog','child','group','solo','active','calm','early'
            ]::text[])
        OR cardinality(p_intent) > 6 THEN
    RAISE EXCEPTION 'junto.dispo_intent';
  ELSE
    v_intent := p_intent;
  END IF;

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

  SELECT id INTO v_id FROM discovery_availabilities WHERE user_id = v_user_id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO discovery_availabilities
      (user_id, sport_keys, levels, intent, base, base_label, radius_km, transport_modes, window_start, window_end)
    VALUES
      (v_user_id, p_sport_keys, p_levels, v_intent,
       ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography,
       v_label, p_radius_km, p_transport_modes, p_window_start, p_window_end)
    RETURNING id INTO v_id;
  ELSE
    UPDATE discovery_availabilities SET
      sport_keys = p_sport_keys, levels = p_levels, intent = v_intent,
      base = ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography,
      base_label = v_label, radius_km = p_radius_km, transport_modes = p_transport_modes,
      window_start = p_window_start, window_end = p_window_end
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;
