-- ============================================================================
-- 00386 — Channels: multiple sports (TEXT[]) + optional place (Scott 2026-08-10).
-- A channel can now span 1–3 sports and may have NO precise place (general
-- topic channel). Dedupe: still proximity-based, but ONLY when the new channel
-- has a place (placeless channels are not deduped — search prevents doubles).
-- ============================================================================

-- ---------- Schema: sport_key -> sport_keys[], base/label nullable ----------
ALTER TABLE channels ADD COLUMN sport_keys TEXT[];
UPDATE channels SET sport_keys = ARRAY[sport_key] WHERE sport_key IS NOT NULL;
ALTER TABLE channels ALTER COLUMN sport_keys SET NOT NULL;
ALTER TABLE channels
  ADD CONSTRAINT channels_sport_keys_len CHECK (array_length(sport_keys, 1) BETWEEN 1 AND 3);

-- Whitelist trigger references sport_key — recreate it on sport_keys BEFORE drop.
CREATE OR REPLACE FUNCTION channels_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.conversation_id := OLD.conversation_id;
  NEW.sport_keys := OLD.sport_keys;
  NEW.base := OLD.base;
  NEW.base_label := OLD.base_label;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

DROP INDEX IF EXISTS channels_sport_idx;
ALTER TABLE channels DROP COLUMN sport_key;
CREATE INDEX channels_sport_keys_gin ON channels USING GIN (sport_keys);

-- Optional place: base + label become nullable, always together.
ALTER TABLE channels ALTER COLUMN base DROP NOT NULL;
ALTER TABLE channels ALTER COLUMN base_label DROP NOT NULL;
ALTER TABLE channels
  ADD CONSTRAINT channels_place_paired CHECK ((base IS NULL) = (base_label IS NULL));

-- ---------- create_channel (multi-sport, optional place) ----------
DROP FUNCTION IF EXISTS create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, BOOLEAN);
CREATE FUNCTION create_channel(
  p_sport_keys TEXT[],
  p_name TEXT,
  p_base_lng DOUBLE PRECISION DEFAULT NULL,
  p_base_lat DOUBLE PRECISION DEFAULT NULL,
  p_base_label TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_force BOOLEAN DEFAULT false
) RETURNS TABLE (conversation_id UUID, duplicate BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_desc TEXT;
  v_label TEXT;
  v_base GEOGRAPHY;
  v_has_place BOOLEAN;
  v_open_count INTEGER;
  v_daily INTEGER;
  v_existing UUID;
  v_conv_id UUID;
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
  THEN RAISE EXCEPTION 'junto.channel_sport'; END IF;

  v_clean_name := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_name IS NULL OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.channel_name';
  END IF;

  v_clean_desc := NULLIF(trim(regexp_replace(COALESCE(p_description, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_desc IS NOT NULL AND char_length(v_clean_desc) > 500 THEN
    RAISE EXCEPTION 'junto.channel_desc';
  END IF;

  -- Place is optional; when present, coords + label must be valid together.
  v_has_place := p_base_lng IS NOT NULL AND p_base_lat IS NOT NULL;
  IF v_has_place THEN
    IF p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90 THEN
      RAISE EXCEPTION 'junto.channel_place';
    END IF;
    v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
    IF v_label IS NULL OR char_length(v_label) > 120 THEN
      RAISE EXCEPTION 'junto.channel_place';
    END IF;
    v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  -- Dedupe only when the new channel has a place: an open channel with an
  -- overlapping sport within ~15 km. Placeless channels are not deduped.
  IF NOT p_force AND v_has_place THEN
    SELECT c.conversation_id INTO v_existing
    FROM channels c
    WHERE c.closed_at IS NULL
      AND c.base IS NOT NULL
      AND c.sport_keys && p_sport_keys
      AND ST_DWithin(c.base, v_base, 15000)
    ORDER BY ST_Distance(c.base, v_base) ASC
    LIMIT 1;
    IF v_existing IS NOT NULL THEN
      RETURN QUERY SELECT v_existing, true;
      RETURN;
    END IF;
  END IF;

  INSERT INTO conversations (type, status, name, created_by, created_at, last_message_at)
  VALUES ('channel', 'active', v_clean_name, v_user_id, now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO channels (conversation_id, sport_keys, base, base_label, description, created_by, created_at)
  VALUES (v_conv_id, p_sport_keys, v_base, v_label, v_clean_desc, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;
REVOKE ALL ON FUNCTION create_channel(TEXT[], TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_channel(TEXT[], TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, BOOLEAN) TO authenticated;

-- ---------- search_channels (sport_keys[], placeless-aware) ----------
DROP FUNCTION IF EXISTS search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER);
CREATE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL,
  p_radius_km INTEGER DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[], base_label TEXT, description TEXT,
  distance_km DOUBLE PRECISION, member_count INTEGER, is_member BOOLEAN, is_creator BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_near GEOGRAPHY;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  v_near := CASE WHEN p_near_lng IS NOT NULL AND p_near_lat IS NOT NULL
                 THEN ST_SetSRID(ST_MakePoint(p_near_lng, p_near_lat), 4326)::geography END;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_keys, c.base_label, c.description,
         CASE WHEN v_near IS NULL OR c.base IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR p_sport_key = ANY(c.sport_keys))
    AND (p_query IS NULL OR conv.name ILIKE '%' || p_query || '%' OR c.base_label ILIKE '%' || p_query || '%')
    -- A radius filter excludes placeless channels (no distance to compare).
    AND (v_near IS NULL OR p_radius_km IS NULL
         OR (c.base IS NOT NULL AND ST_DWithin(c.base, v_near, p_radius_km * 1000.0)))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL OR c.base IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$$;
REVOKE ALL ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) TO authenticated;

-- ---------- get_channel (sport_keys[], nullable base) ----------
DROP FUNCTION IF EXISTS get_channel(UUID);
CREATE FUNCTION get_channel(p_conversation_id UUID)
RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[],
  base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, base_label TEXT,
  description TEXT, member_count INTEGER,
  is_member BOOLEAN, is_creator BOOLEAN, is_closed BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_keys,
         CASE WHEN c.base IS NULL THEN NULL ELSE ST_X(c.base::geometry) END,
         CASE WHEN c.base IS NULL THEN NULL ELSE ST_Y(c.base::geometry) END,
         c.base_label, c.description,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id),
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id),
         (c.created_by = v_user_id),
         (c.closed_at IS NOT NULL)
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.conversation_id = p_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION get_channel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_channel(UUID) TO authenticated;
