-- ============================================================================
-- 00400 — Channels: "large local hub" model (Scott 2026-09-05, C large / Summeet).
--
-- SUPERSEDES the 00387 "1 sport × capped zone" model. Rationale: a small user
-- base fragments into ghost channels under a strict 1-sport/small-radius bucket
-- (exactly Summeet's pain where the base is thin). So a channel's IDENTITY is now
-- its TITLE + ZONE (a broad territory); sports (0-3) and vibes are OPTIONAL
-- labels for filtering — reusing the Discovery vibe vocabulary + filter.
--
--   • radius tiers 20/35/50 → 35/60/100 (secteur / massif / région)
--   • sport_key (mandatory, single) → sport_keys[] (OPTIONAL, 0-3)
--   • + intent[] (optional vibes, ≤6, closed 25-value vocab + GIN)
--   • concentration is now ZONE-based (sport-agnostic): a hub whose zone contains
--     the new centre is the same territory → offered to join.
-- ============================================================================

-- ---------- Schema ----------
-- Radius: migrate to the new tiers BEFORE swapping the CHECK (20→35, 35→35, 50→60).
ALTER TABLE channels DROP CONSTRAINT IF EXISTS channels_radius_tier;
UPDATE channels SET radius_km = CASE WHEN radius_km <= 35 THEN 35 WHEN radius_km <= 60 THEN 60 ELSE 100 END;
ALTER TABLE channels ADD CONSTRAINT channels_radius_tier CHECK (radius_km IN (35, 60, 100));

-- sport_key (mandatory single) → sport_keys[] (optional, 0-3).
ALTER TABLE channels ADD COLUMN IF NOT EXISTS sport_keys TEXT[];
UPDATE channels SET sport_keys = ARRAY[sport_key] WHERE sport_key IS NOT NULL AND sport_keys IS NULL;
DROP INDEX IF EXISTS channels_sport_idx;
ALTER TABLE channels DROP CONSTRAINT IF EXISTS channels_sport_key_fk;
ALTER TABLE channels DROP COLUMN IF EXISTS sport_key;
ALTER TABLE channels ADD CONSTRAINT channels_sport_keys_len
  CHECK (sport_keys IS NULL OR cardinality(sport_keys) BETWEEN 1 AND 3);
CREATE INDEX channels_sport_keys_gin ON channels USING GIN (sport_keys);

-- Optional vibes (same closed vocab as discovery, ≤6).
ALTER TABLE channels ADD COLUMN IF NOT EXISTS intent TEXT[];
ALTER TABLE channels ADD CONSTRAINT channels_intent_check CHECK (
  intent IS NULL OR (
    intent <@ ARRAY[
      'discovery','progression','performance','detente','conviviality',
      'dog','child','group','solo','active','calm','early',
      'nature','challenge','photo','mixed','same_level','beginners',
      'long_outing','after_work','regular','adapted','training',
      'experienced','competition'
    ]::text[]
    AND coalesce(array_length(intent, 1), 0) BETWEEN 1 AND 6
  )
);
CREATE INDEX channels_intent_gin ON channels USING GIN (intent);

-- Whitelist trigger — freeze identity (now sport_keys + intent instead of sport_key).
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
  NEW.intent := OLD.intent;
  NEW.base := OLD.base;
  NEW.base_label := OLD.base_label;
  NEW.radius_km := OLD.radius_km;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

-- ---------- create_channel (title + zone identity; optional sports[]/intent[]) ----------
DROP FUNCTION IF EXISTS create_channel(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT, BOOLEAN);
CREATE FUNCTION create_channel(
  p_name TEXT,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_sport_keys TEXT[] DEFAULT NULL,
  p_intent TEXT[] DEFAULT NULL,
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
  v_intent TEXT[];
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

  -- Vibes OPTIONAL (≤6, closed vocab).
  IF p_intent IS NULL OR cardinality(p_intent) = 0 THEN
    v_intent := NULL;
  ELSIF cardinality(p_intent) > 6
        OR NOT (p_intent <@ ARRAY[
          'discovery','progression','performance','detente','conviviality',
          'dog','child','group','solo','active','calm','early',
          'nature','challenge','photo','mixed','same_level','beginners',
          'long_outing','after_work','regular','adapted','training',
          'experienced','competition'
        ]::text[]) THEN
    RAISE EXCEPTION 'junto.channel_intent';
  ELSE
    v_intent := p_intent;
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

  INSERT INTO channels (conversation_id, sport_keys, intent, base, base_label, radius_km, description, created_by, created_at)
  VALUES (v_conv_id, v_sports, v_intent, v_base, v_label, p_radius_km, v_clean_desc, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;
REVOKE ALL ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT[], TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT[], TEXT, BOOLEAN) TO authenticated;

-- ---------- search_channels (+ sport-in-array + vibe overlap filters) ----------
DROP FUNCTION IF EXISTS search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION);
CREATE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL,
  p_intent TEXT[] DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[], intent TEXT[], base_label TEXT, radius_km INTEGER, description TEXT,
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
  SELECT c.conversation_id, conv.name, c.sport_keys, c.intent, c.base_label, c.radius_km, c.description,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR p_sport_key = ANY(c.sport_keys))
    AND (p_intent IS NULL OR c.intent && p_intent)
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
REVOKE ALL ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT[]) TO authenticated;

-- ---------- get_channel (+ sport_keys[] + intent[]) ----------
DROP FUNCTION IF EXISTS get_channel(UUID);
CREATE FUNCTION get_channel(p_conversation_id UUID)
RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[], intent TEXT[],
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
  SELECT c.conversation_id, conv.name, c.sport_keys, c.intent,
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

-- ---------- get_my_conversations — channel sport label = first sport ----------
CREATE OR REPLACE FUNCTION get_my_conversations()
RETURNS TABLE (
  id UUID, type TEXT, status TEXT,
  last_message_at TIMESTAMPTZ, created_at TIMESTAMPTZ,
  last_message_content TEXT, last_message_sender_id UUID, last_message_metadata JSONB,
  is_unread BOOLEAN,
  user_1 UUID, user_2 UUID,
  other_user_id UUID, other_user_name TEXT, other_user_avatar TEXT, other_user_reliability_tier TEXT,
  name TEXT, icon TEXT, member_count INTEGER,
  activity_id UUID, activity_title TEXT, sport_id UUID
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.type, c.status, c.last_message_at, c.created_at,
    lm.content, lm.sender_id, lm.metadata,
    EXISTS (
      SELECT 1 FROM messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL
        AND m.sender_id IS DISTINCT FROM auth.uid()
        AND private.message_author_visible(c.id, m.sender_id, auth.uid())
        AND (me.last_read_at IS NULL OR m.created_at > me.last_read_at)
    ) AS is_unread,
    c.user_1, c.user_2,
    CASE WHEN c.type = 'dm' THEN (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END) END,
    CASE WHEN c.type = 'dm' THEN COALESCE(pp.display_name, '?') END,
    CASE WHEN c.type = 'dm' THEN pp.avatar_url END,
    CASE WHEN c.type = 'dm' THEN pp.reliability_tier END,
    CASE WHEN c.type IN ('group', 'channel') THEN c.name END,
    CASE WHEN c.type = 'group' THEN c.icon END,
    CASE WHEN c.type IN ('group', 'channel') THEN (SELECT count(*)::int FROM conversation_members gm WHERE gm.conversation_id = c.id) END,
    CASE WHEN c.type = 'activity' THEN c.activity_id END,
    CASE WHEN c.type = 'activity' THEN act.title END,
    CASE WHEN c.type = 'activity' THEN act.sport_id WHEN c.type = 'channel' THEN cs.id END
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON c.type = 'dm' AND pp.id = (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END)
  LEFT JOIN activities act
    ON c.type = 'activity' AND act.id = c.activity_id
  LEFT JOIN channels ch
    ON c.type = 'channel' AND ch.conversation_id = c.id
  LEFT JOIN sports cs
    ON ch.sport_keys IS NOT NULL AND cs.key = ch.sport_keys[1]
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
      AND private.message_author_visible(m.conversation_id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND (
      (c.type = 'dm' AND c.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
             OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
        ))
      OR c.type = 'group'
      OR c.type = 'channel'
      OR (c.type = 'activity'
          AND act.id IS NOT NULL
          AND act.deleted_at IS NULL
          AND act.is_demo = (SELECT u.is_demo FROM users u WHERE u.id = auth.uid())
          AND (act.status IN ('published', 'in_progress')
               OR act.starts_at > now() - INTERVAL '30 days'))
    )
  ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
$$;
