-- ============================================================================
-- 00387 — Channels: the sport × zone model (Scott 2026-08-12, discussion locked).
--
-- A channel = exactly ONE sport + a ZONE (a chosen centre + a radius tier that
-- IS the community's territory, e.g. Briançon + 35 km covers the Briançonnais).
-- This reverts the brief multi-sport / optional-place experiment (00386): the
-- structured bucket concentrates a small user base into few living channels
-- (anti-fragmentation), and a capped radius forbids department-wide catch-alls.
--
-- Concentration: creating a same-sport channel whose centre falls INSIDE an
-- existing channel's zone returns that channel (client pushes "join instead").
-- No auto-snap-to-town in v1 (Photon place typing is unreliable) — first creator
-- anchors the zone, the free title carries the identity.
-- ============================================================================

-- Drop any placeless test channels (base became mandatory again).
DELETE FROM conversations WHERE id IN (SELECT conversation_id FROM channels WHERE base IS NULL);

-- ---------- Schema: sport_keys[] -> single sport_key, + radius_km, place required ----------
ALTER TABLE channels ADD COLUMN sport_key TEXT;
UPDATE channels SET sport_key = sport_keys[1] WHERE sport_keys IS NOT NULL;
ALTER TABLE channels ALTER COLUMN sport_key SET NOT NULL;
ALTER TABLE channels ADD CONSTRAINT channels_sport_key_fk
  FOREIGN KEY (sport_key) REFERENCES sports(key) ON DELETE RESTRICT;

ALTER TABLE channels ADD COLUMN radius_km INTEGER;
UPDATE channels SET radius_km = 35 WHERE radius_km IS NULL;
ALTER TABLE channels ALTER COLUMN radius_km SET NOT NULL;
ALTER TABLE channels ADD CONSTRAINT channels_radius_tier CHECK (radius_km IN (20, 35, 50));

-- Whitelist trigger references sport_keys — recreate on the new columns first.
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
  NEW.sport_key := OLD.sport_key;
  NEW.base := OLD.base;
  NEW.base_label := OLD.base_label;
  NEW.radius_km := OLD.radius_km;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

DROP INDEX IF EXISTS channels_sport_keys_gin;
ALTER TABLE channels DROP CONSTRAINT IF EXISTS channels_sport_keys_len;
ALTER TABLE channels DROP COLUMN sport_keys;
CREATE INDEX channels_sport_idx ON channels (sport_key);

-- Place mandatory again (the zone is the identity).
ALTER TABLE channels DROP CONSTRAINT IF EXISTS channels_place_paired;
ALTER TABLE channels ALTER COLUMN base SET NOT NULL;
ALTER TABLE channels ALTER COLUMN base_label SET NOT NULL;

-- ---------- create_channel (1 sport, required zone, concentration) ----------
DROP FUNCTION IF EXISTS create_channel(TEXT[], TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, BOOLEAN);
CREATE FUNCTION create_channel(
  p_sport_key TEXT,
  p_name TEXT,
  p_base_lng DOUBLE PRECISION,
  p_base_lat DOUBLE PRECISION,
  p_base_label TEXT,
  p_radius_km INTEGER,
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

  IF p_radius_km IS NULL OR p_radius_km NOT IN (20, 35, 50) THEN
    RAISE EXCEPTION 'junto.channel_radius';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  -- Concentration: a same-sport channel whose zone already CONTAINS my centre is
  -- the same territory → return it (client offers Join / Create anyway).
  IF NOT p_force THEN
    SELECT c.conversation_id INTO v_existing
    FROM channels c
    WHERE c.sport_key = p_sport_key AND c.closed_at IS NULL
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

  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, created_by, created_at)
  VALUES (v_conv_id, p_sport_key, v_base, v_label, p_radius_km, v_clean_desc, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$$;
REVOKE ALL ON FUNCTION create_channel(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_channel(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, INTEGER, TEXT, BOOLEAN) TO authenticated;

-- ---------- search_channels (coverage: a channel whose zone contains the point) ----------
DROP FUNCTION IF EXISTS search_channels(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER);
CREATE FUNCTION search_channels(
  p_query TEXT DEFAULT NULL,
  p_sport_key TEXT DEFAULT NULL,
  p_near_lng DOUBLE PRECISION DEFAULT NULL,
  p_near_lat DOUBLE PRECISION DEFAULT NULL
) RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_key TEXT, base_label TEXT, radius_km INTEGER, description TEXT,
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
  SELECT c.conversation_id, conv.name, c.sport_key, c.base_label, c.radius_km, c.description,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR c.sport_key = p_sport_key)
    AND (p_query IS NULL OR conv.name ILIKE '%' || p_query || '%' OR c.base_label ILIKE '%' || p_query || '%')
    -- With a place, keep only channels whose zone COVERS it (point in radius).
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

-- ---------- get_channel (1 sport + radius) ----------
DROP FUNCTION IF EXISTS get_channel(UUID);
CREATE FUNCTION get_channel(p_conversation_id UUID)
RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_key TEXT,
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
  SELECT c.conversation_id, conv.name, c.sport_key,
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
