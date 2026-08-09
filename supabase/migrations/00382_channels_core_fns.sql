-- ============================================================================
-- 00382 — Channels: core functions (create with dedupe, join, leave, search).
-- channel_bans makes "remove a member" stick (open join would let a removed
-- member walk back in). All writes SECURITY DEFINER; REVOKE anon.
-- ============================================================================

CREATE TABLE channel_bans (
  conversation_id UUID NOT NULL REFERENCES channels(conversation_id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  banned_by UUID REFERENCES users(id) ON DELETE SET NULL,
  banned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
ALTER TABLE channel_bans ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_bans FORCE ROW LEVEL SECURITY;
REVOKE ALL ON channel_bans FROM anon, authenticated;

-- ---------- create_channel (structured, with dedupe) ----------
CREATE OR REPLACE FUNCTION create_channel(
  p_sport_key TEXT,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_name TEXT,
  p_description TEXT,
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

  IF p_sport_key IS NULL OR NOT EXISTS (SELECT 1 FROM sports WHERE key = p_sport_key AND is_active) THEN
    RAISE EXCEPTION 'junto.channel_sport';
  END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;

  v_clean_name := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_name IS NULL OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.channel_name';
  END IF;

  v_clean_desc := NULLIF(trim(regexp_replace(COALESCE(p_description, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_desc IS NOT NULL AND char_length(v_clean_desc) > 500 THEN
    RAISE EXCEPTION 'junto.channel_desc';
  END IF;

  v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;

  -- Serialize the caller's channel creation (cap + daily rate).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  -- Anti-fragmentation: an open channel with the same sport within ~15 km is a
  -- duplicate candidate. Return it (client offers Join / Create anyway).
  IF NOT p_force THEN
    SELECT c.conversation_id INTO v_existing
    FROM channels c
    WHERE c.sport_key = p_sport_key AND c.closed_at IS NULL
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

  INSERT INTO channels (conversation_id, sport_key, base, base_label, description, created_by, created_at)
  VALUES (v_conv_id, p_sport_key, v_base, v_label, v_clean_desc, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;
REVOKE ALL ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

-- ---------- join_channel (open) ----------
CREATE OR REPLACE FUNCTION join_channel(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_ch RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT c.conversation_id, c.closed_at INTO v_ch
  FROM channels c WHERE c.conversation_id = p_conversation_id;
  IF v_ch.conversation_id IS NULL OR v_ch.closed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Banned from this channel (a creator removed you) → refuse.
  IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = p_conversation_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Idempotent join (open membership, no approval).
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, v_user_id, NULL, now())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION join_channel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION join_channel(UUID) TO authenticated;

-- ---------- leave_channel ----------
CREATE OR REPLACE FUNCTION leave_channel(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION leave_channel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION leave_channel(UUID) TO authenticated;

-- ---------- search_channels (browse / directory) ----------
CREATE OR REPLACE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL,
  p_radius_km INTEGER DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_key TEXT, base_label TEXT, description TEXT,
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
  SELECT c.conversation_id, conv.name, c.sport_key, c.base_label, c.description,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR c.sport_key = p_sport_key)
    AND (p_query IS NULL OR conv.name ILIKE '%' || p_query || '%' OR c.base_label ILIKE '%' || p_query || '%')
    AND (v_near IS NULL OR p_radius_km IS NULL OR ST_DWithin(c.base, v_near, p_radius_km * 1000.0))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$$;
REVOKE ALL ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER) TO authenticated;
