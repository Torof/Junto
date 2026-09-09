-- ============================================================================
-- 00403 — Channel photo (Scott 2026-09-09). Direction A: an optional photo the
-- creator sets, rendered faintly behind the tinted list card.
--
--   • Storage bucket `channel-photos` (public read, owner-scoped writes) —
--     mirrors `pro-photos` (00241). Path: {user_id}/channels/{uuid}.jpg.
--   • channels.photo_url (frozen by the whitelist trigger — privileged column,
--     protected by default; only writable via SECURITY DEFINER + bypass_lock).
--   • create_channel gains p_photo_url; new set_channel_photo (creator-only)
--     for edit/remove. search_channels + get_channel return photo_url.
--
-- Security note: the storage policy can only scope writes to the uploader's own
-- {uid}/ folder — it cannot check "is the channel creator". So anyone may drop
-- an object in their own folder, but it only becomes a channel's photo when
-- set_channel_photo (or create_channel) writes the URL, and THOSE check creator
-- ownership. Orphan objects are tolerated (same as pro photos).
-- ============================================================================

-- ---------- Storage bucket ----------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'channel-photos', 'channel-photos', true,
  5242880,  -- 5 MB per file
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "channel_photos_read_all" ON storage.objects;
DROP POLICY IF EXISTS "channel_photos_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "channel_photos_update_own" ON storage.objects;
DROP POLICY IF EXISTS "channel_photos_delete_own" ON storage.objects;

CREATE POLICY "channel_photos_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'channel-photos');

CREATE POLICY "channel_photos_insert_own"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'channel-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "channel_photos_update_own"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'channel-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "channel_photos_delete_own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'channel-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------- Column ----------
ALTER TABLE channels ADD COLUMN IF NOT EXISTS photo_url TEXT
  CHECK (photo_url IS NULL OR char_length(photo_url) <= 500);

-- ---------- Whitelist trigger — freeze photo_url (privileged) ----------
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
  NEW.photo_url := OLD.photo_url;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

-- ---------- create_channel — + p_photo_url ----------
DROP FUNCTION IF EXISTS create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT, BOOLEAN);
CREATE FUNCTION create_channel(
  p_name TEXT,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
  p_sport_keys TEXT[] DEFAULT NULL,
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
  v_sports TEXT[];
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

  -- Photo OPTIONAL: must point at the channel-photos bucket.
  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (char_length(v_photo) > 500 OR v_photo NOT LIKE '%/channel-photos/%') THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  -- Concentration by ZONE (sport-agnostic).
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

  INSERT INTO channels (conversation_id, sport_keys, base, base_label, radius_km, description, photo_url, created_by, created_at)
  VALUES (v_conv_id, v_sports, v_base, v_label, p_radius_km, v_clean_desc, v_photo, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;
REVOKE ALL ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_channel(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT[], TEXT, TEXT, BOOLEAN) TO authenticated;

-- ---------- set_channel_photo — creator sets/replaces/clears the photo ----------
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

  -- Creator-only, open channel (both sensitive → generic message).
  IF NOT EXISTS (
    SELECT 1 FROM channels
    WHERE conversation_id = p_conversation_id
      AND created_by = v_user_id
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (char_length(v_photo) > 500 OR v_photo NOT LIKE '%/channel-photos/%') THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE channels SET photo_url = v_photo WHERE conversation_id = p_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION set_channel_photo(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_channel_photo(UUID, TEXT) TO authenticated;

-- ---------- search_channels — return photo_url ----------
DROP FUNCTION IF EXISTS search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION);
CREATE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[], base_label TEXT, radius_km INTEGER, description TEXT,
  photo_url TEXT, distance_km DOUBLE PRECISION, member_count INTEGER, is_member BOOLEAN, is_creator BOOLEAN
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
  SELECT c.conversation_id, conv.name, c.sport_keys, c.base_label, c.radius_km, c.description, c.photo_url,
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

-- ---------- get_channel — return photo_url ----------
DROP FUNCTION IF EXISTS get_channel(UUID);
CREATE FUNCTION get_channel(p_conversation_id UUID)
RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_keys TEXT[],
  base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, base_label TEXT, radius_km INTEGER,
  description TEXT, photo_url TEXT, member_count INTEGER,
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
         c.description, c.photo_url,
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
