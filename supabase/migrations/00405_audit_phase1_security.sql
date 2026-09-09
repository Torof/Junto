-- ============================================================================
-- 00405 — Audit phase 1: security hardening (Scott 2026-09-09, post-audit).
--
--   (1) Channel photo URL: pin to the Supabase storage public path for the
--       channel-photos bucket AND the caller's own {uid} folder — the old
--       LIKE '%/channel-photos/%' matched any host / another user's object
--       (IP/UA-leak + arbitrary-content vector on a public fan-out read).
--       Applied to create_channel + set_channel_photo.
--   (2) Suspension gate on the four creator-moderation functions
--       (rename_channel / remove_channel_member / close_channel /
--       delete_message channel branch) — they only checked auth, so a
--       suspended creator kept full moderation power.
--   (3) upsert_dispo levels JSONB: require an object + bound each value's
--       length; the old check only constrained KEYS, so a non-object or a
--       multi-KB value slipped through and was pushed to every match.
-- ============================================================================

-- ---------- (1) create_channel — tightened photo URL check ----------
CREATE OR REPLACE FUNCTION create_channel(
  p_name TEXT,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_sport_key TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_photo_url TEXT DEFAULT NULL,
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
  v_sport TEXT;
  v_photo TEXT;
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

  v_sport := NULLIF(trim(p_sport_key), '');
  IF v_sport IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = v_sport AND s.is_active) THEN
    RAISE EXCEPTION 'junto.channel_sport';
  END IF;

  -- Photo OPTIONAL: must be a public URL in the channel-photos bucket under the
  -- caller's own {uid} folder (blocks external hosts + other users' objects).
  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR v_photo NOT LIKE '%/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

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

  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, photo_url, created_by, created_at)
  VALUES (v_conv_id, v_sport, v_base, v_label, p_radius_km, v_clean_desc, v_photo, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;

-- ---------- (1) set_channel_photo — same tightened check ----------
CREATE OR REPLACE FUNCTION set_channel_photo(p_conversation_id UUID, p_photo_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_photo TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM channels
    WHERE conversation_id = p_conversation_id
      AND created_by = v_user_id
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR v_photo NOT LIKE '%/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE channels SET photo_url = v_photo WHERE conversation_id = p_conversation_id;
END;
$$;

-- ---------- (2) delete_message — + suspension gate ----------
CREATE OR REPLACE FUNCTION delete_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE messages SET deleted_at = now()
  WHERE id = p_message_id AND sender_id = v_user_id AND deleted_at IS NULL;
  IF FOUND THEN RETURN; END IF;

  SELECT conversation_id INTO v_conv FROM messages WHERE id = p_message_id AND deleted_at IS NULL;
  IF v_conv IS NOT NULL AND EXISTS (
    SELECT 1 FROM channels ch WHERE ch.conversation_id = v_conv AND ch.created_by = v_user_id
  ) THEN
    UPDATE messages SET deleted_at = now() WHERE id = p_message_id AND deleted_at IS NULL;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Operation not permitted';
END;
$$;

-- ---------- (2) rename_channel — + suspension gate ----------
CREATE OR REPLACE FUNCTION rename_channel(p_conversation_id UUID, p_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id AND created_by = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_clean := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean IS NULL OR char_length(v_clean) > 60 THEN RAISE EXCEPTION 'junto.channel_name'; END IF;
  UPDATE conversations SET name = v_clean WHERE id = p_conversation_id;
END;
$$;

-- ---------- (2) remove_channel_member — + suspension gate ----------
CREATE OR REPLACE FUNCTION remove_channel_member(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
  INSERT INTO channel_bans (conversation_id, user_id, banned_by)
  VALUES (p_conversation_id, p_user_id, v_user_id)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;

-- ---------- (2) close_channel — + suspension gate ----------
CREATE OR REPLACE FUNCTION close_channel(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE channels SET closed_at = now() WHERE conversation_id = p_conversation_id AND closed_at IS NULL;
END;
$$;

-- ---------- (3) upsert_dispo — bound the levels JSONB (object + value length) ----------
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

  -- Levels: optional. If present it MUST be an object whose keys ⊆ chosen sports
  -- and whose values are short strings (cotation codes) — no unbounded / non-object
  -- blob can be stored and fanned out to matches.
  IF p_levels IS NOT NULL THEN
    IF jsonb_typeof(p_levels) <> 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(p_levels) AS lk(sport)
         WHERE lk.sport <> ALL(p_sport_keys)
       )
       OR EXISTS (
         SELECT 1 FROM jsonb_each_text(p_levels) AS e(k, v)
         WHERE v IS NULL OR char_length(v) > 20
       )
    THEN RAISE EXCEPTION 'junto.dispo_levels'; END IF;
  END IF;

  IF p_intent IS NULL OR cardinality(p_intent) = 0 THEN
    v_intent := NULL;
  ELSIF NOT (p_intent <@ ARRAY[
              'discovery','progression','performance','detente','conviviality',
              'dog','child','group','solo','active','calm','early',
              'nature','challenge','photo','mixed','same_level','beginners',
              'long_outing','after_work','regular','adapted','training',
              'experienced','competition'
            ]::text[])
        OR cardinality(p_intent) > 10 THEN
    RAISE EXCEPTION 'junto.dispo_intent';
  ELSE
    v_intent := p_intent;
  END IF;

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
