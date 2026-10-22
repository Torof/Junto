-- ============================================================================
-- 00402 — Channels: drop the optional vibe labels entirely (Scott 2026-09-09).
--
-- Decision: a channel is a LARGE local hub around a THEME (sport) + a PLACE,
-- meant to gather hundreds. Vibe labels ("intent") are too fine-grained here —
-- people join for the place + sport, not the ambiance — and only fragment the
-- space into too many near-duplicate channels. Ambiance belongs to an activity
-- or to the conversation, not to the channel bucket.
--
-- Channels were preview-only (never OTA'd to prod testers), so we clean the
-- signatures franchement: remove p_intent from create/search, drop intent from
-- get_channel's shape, and drop the channels.intent column + its GIN index.
-- The 'junto.channel_intent' error code disappears with the validation block.
-- ============================================================================

-- ---------- Whitelist trigger — drop intent from the frozen-identity set ----------
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
  NEW.radius_km := OLD.radius_km;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

-- ---------- create_channel — drop p_intent, its validation, and the write ----------
DROP FUNCTION IF EXISTS create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT[], TEXT, BOOLEAN);
CREATE FUNCTION create_channel(
  p_name TEXT,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_sport_keys TEXT[] DEFAULT NULL,
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
  v_sports TEXT[];
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

  v_clean_name := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_name IS NULL OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.channel_name';
  END IF;

  v_clean_desc := NULLIF(trim(regexp_replace(COALESCE(p_description, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_desc IS NOT NULL AND char_length(v_clean_desc) > 500 THEN
    RAISE EXCEPTION 'junto.channel_desc';
  END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;

  IF p_radius_km IS NULL OR p_radius_km NOT IN (35, 60, 100) THEN
    RAISE EXCEPTION 'junto.channel_radius';
  END IF;

  -- Sports OPTIONAL (0-3): if given, each must be an active sport.
  IF p_sport_keys IS NULL OR cardinality(p_sport_keys) = 0 THEN
    v_sports := NULL;
  ELSIF cardinality(p_sport_keys) > 3
        OR EXISTS (SELECT 1 FROM unnest(p_sport_keys) k
                   WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k AND s.is_active)) THEN
    RAISE EXCEPTION 'junto.channel_sport';
  ELSE
    v_sports := p_sport_keys;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  -- Concentration by ZONE (sport-agnostic): an existing hub whose zone already
  -- CONTAINS my centre is the same local territory → return it (client offers
  -- Join / Create anyway).
  IF NOT p_force THEN
    SELECT c.conversation_id INTO v_existing
    FROM channels c
    WHERE c.closed_at IS NULL
      AND ST_DWithin(c.base, v_base, c.radius_km * 1000.0)
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

  INSERT INTO channels (conversation_id, sport_keys, base, base_label, radius_km, description, created_by, created_at)
  VALUES (v_conv_id, v_sports, v_base, v_label, p_radius_km, v_clean_desc, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;
REVOKE ALL ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT, BOOLEAN) TO authenticated;

-- ---------- search_channels — drop p_intent param + filter + column ----------
DROP FUNCTION IF EXISTS search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT[]);
CREATE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[], base_label TEXT, radius_km INTEGER, description TEXT,
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
  SELECT c.conversation_id, conv.name, c.sport_keys, c.base_label, c.radius_km, c.description,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR p_sport_key = ANY(c.sport_keys))
    AND (p_query IS NULL OR conv.name ILIKE '%' || p_query || '%' OR c.base_label ILIKE '%' || p_query || '%')
    AND (v_near IS NULL OR ST_DWithin(c.base, v_near, c.radius_km * 1000.0))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$$;
REVOKE ALL ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- ---------- get_channel — drop intent from the returned shape ----------
DROP FUNCTION IF EXISTS get_channel(UUID);
CREATE FUNCTION get_channel(p_conversation_id UUID)
RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[],
  base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, base_label TEXT, radius_km INTEGER,
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
         ST_X(c.base::geometry), ST_Y(c.base::geometry), c.base_label, c.radius_km,
         c.description,
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

-- ---------- Drop the column last (now unreferenced) ----------
DROP INDEX IF EXISTS channels_intent_gin;
ALTER TABLE channels DROP CONSTRAINT IF EXISTS channels_intent_check;
ALTER TABLE channels DROP COLUMN IF EXISTS intent;
