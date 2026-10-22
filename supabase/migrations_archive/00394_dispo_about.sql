-- ============================================================================
-- 00394 — Dispo "présentation": a free-text intro on the dispo (Scott 2026-08-28)
-- where a person describes themselves + what they're looking for. Shown as a
-- sub-card in each Discovery partner card. ≤ 250 words (≤ 1600 chars hard cap),
-- HTML-stripped, NO URL auto-linking on the client (project rule).
--   • discovery_availabilities.about (content column, not frozen by the trigger)
--   • upsert_dispo(+ p_about) validates + stores
--   • get_my_dispo / get_discovery_cards return it
--   • demo dispos seeded with an in-character intro
-- ============================================================================

ALTER TABLE discovery_availabilities
  ADD COLUMN IF NOT EXISTS about TEXT CHECK (about IS NULL OR char_length(about) <= 1600);

-- ---------- upsert_dispo (+ p_about, reproduced from 00389) ----------
DROP FUNCTION IF EXISTS upsert_dispo(TEXT[], JSONB, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TIMESTAMPTZ, TIMESTAMPTZ, TEXT[]);
CREATE FUNCTION upsert_dispo(
  p_sport_keys TEXT[],
  p_levels JSONB,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_transport_modes TEXT[],
  p_window_start TIMESTAMPTZ,
  p_window_end TIMESTAMPTZ,
  p_intent TEXT[] DEFAULT NULL,
  p_about TEXT DEFAULT NULL
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
  v_about TEXT;
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

  -- Présentation: optional free text, HTML-stripped, ≤ 250 words / ≤ 1600 chars.
  v_about := NULLIF(trim(regexp_replace(COALESCE(p_about, ''), '<[^>]*>', '', 'g')), '');
  IF v_about IS NOT NULL AND (
       char_length(v_about) > 1600
       OR array_length(regexp_split_to_array(v_about, '\s+'), 1) > 250
     ) THEN
    RAISE EXCEPTION 'junto.dispo_about';
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
      (user_id, sport_keys, levels, intent, about, base, base_label, radius_km, transport_modes, window_start, window_end)
    VALUES
      (v_user_id, p_sport_keys, p_levels, v_intent, v_about,
       ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography,
       v_label, p_radius_km, p_transport_modes, p_window_start, p_window_end)
    RETURNING id INTO v_id;
  ELSE
    UPDATE discovery_availabilities SET
      sport_keys = p_sport_keys, levels = p_levels, intent = v_intent, about = v_about,
      base = ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography,
      base_label = v_label, radius_km = p_radius_km, transport_modes = p_transport_modes,
      window_start = p_window_start, window_end = p_window_end
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION upsert_dispo(TEXT[], JSONB, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TIMESTAMPTZ, TIMESTAMPTZ, TEXT[], TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION upsert_dispo(TEXT[], JSONB, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TIMESTAMPTZ, TIMESTAMPTZ, TEXT[], TEXT) TO authenticated;

-- ---------- get_my_dispo (+ about) ----------
DROP FUNCTION IF EXISTS get_my_dispo();
CREATE FUNCTION get_my_dispo()
RETURNS TABLE (
  id UUID, sport_keys TEXT[], levels JSONB, intent TEXT[],
  base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, base_label TEXT,
  radius_km INTEGER, transport_modes TEXT[],
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, is_active BOOLEAN, about TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT id, sport_keys, levels, intent,
         ST_X(base::geometry), ST_Y(base::geometry), base_label,
         radius_km, transport_modes, window_start, window_end, is_active, about
  FROM discovery_availabilities
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION get_my_dispo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_dispo() TO authenticated;

-- ---------- get_discovery_cards (+ about, reproduced from 00391) ----------
DROP FUNCTION IF EXISTS get_discovery_cards();
CREATE FUNCTION get_discovery_cards()
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  sport_keys TEXT[], levels JSONB, transport_modes TEXT[], radius_km INTEGER,
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, intent TEXT[],
  distance_km DOUBLE PRECISION, sorties_count INTEGER, about TEXT
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
  IF v_base IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes, d.radius_km,
         d.window_start, d.window_end, d.intent,
         (ST_Distance(d.base, v_base) / 1000.0) AS distance_km,
         (SELECT count(*)::int FROM participations p
          WHERE p.user_id = d.user_id AND p.status = 'accepted') AS sorties_count,
         d.about
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
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
REVOKE ALL ON FUNCTION get_discovery_cards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_cards() TO authenticated;

-- ---------- Demo dispos: in-character intros ----------
UPDATE discovery_availabilities SET about =
  'Passionnée de montagne, je bosse en semaine et je pars dès que possible. Je cherche des gens fiables pour de la rando et du trail dans les Écrins, à un rythme soutenu mais sans se cramer. Toujours partante pour un café au sommet et papoter itinéraires.'
  WHERE user_id = 'd0000000-0000-4000-a000-000000000002';
UPDATE discovery_availabilities SET about =
  'Grimpeur depuis dix ans, surtout couenne et grandes voies autour de Briançon. Je cherche des partenaires réguliers, sérieux sur la sécu mais détendus sur le reste. Niveau 6b/7a mais je grimpe avec tout le monde. Dispo souvent le week-end, parfois en soirée l’été.'
  WHERE user_id = 'd0000000-0000-4000-a000-000000000003';
UPDATE discovery_availabilities SET about =
  'Touche-à-tout de l’outdoor : rando, ski de rando l’hiver, un peu de via ferrata. J’aime découvrir de nouveaux coins et rencontrer du monde. Pas de compét, juste le plaisir d’être dehors. Je m’adapte au groupe et j’adore quand ça finit en pique-nique.'
  WHERE user_id = 'd0000000-0000-4000-a000-000000000006';
