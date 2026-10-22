-- Migration 00252: pro photo galleries (Phase 4A).
--
-- Two tables — one for the pro page gallery, one for offering galleries.
-- Separate FK semantics > polymorphic; cleaner cascades + simpler RPCs.
-- Both share the same shape: parent FK + photo_url + order_index, with
-- a 25-photo cap per surface enforced at the add RPC under an advisory
-- lock (mirrors create_pro_offering's 50-cap pattern).
--
-- Privileged-column whitelist trigger locks id / parent_id / photo_url /
-- created_at to OLD. Only order_index is writable on plain UPDATE, which
-- is what reorder_* RPCs use. set_*_photo_url uses bypass_lock to
-- replace the URL in place (preserves order_index).

-- ============================================================================
-- pro_profile_photos
-- ============================================================================
CREATE TABLE pro_profile_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_id UUID NOT NULL REFERENCES pro_profiles(user_id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL CHECK (char_length(photo_url) BETWEEN 1 AND 500),
  order_index INTEGER NOT NULL CHECK (order_index >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (pro_id, order_index)
);

CREATE INDEX pro_profile_photos_pro_idx ON pro_profile_photos(pro_id, order_index);

ALTER TABLE pro_profile_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_profile_photos FORCE ROW LEVEL SECURITY;

CREATE POLICY pro_profile_photos_public_read ON pro_profile_photos
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- No write policies — RPCs are the only write path.

CREATE OR REPLACE FUNCTION pro_profile_photos_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.photo_url := OLD.photo_url;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_profile_photos_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER pro_profile_photos_lock_privileged
  BEFORE UPDATE ON pro_profile_photos
  FOR EACH ROW EXECUTE FUNCTION pro_profile_photos_whitelist_columns();

-- ============================================================================
-- pro_offering_photos
-- ============================================================================
CREATE TABLE pro_offering_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id UUID NOT NULL REFERENCES pro_offerings(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL CHECK (char_length(photo_url) BETWEEN 1 AND 500),
  order_index INTEGER NOT NULL CHECK (order_index >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (offering_id, order_index)
);

CREATE INDEX pro_offering_photos_offering_idx ON pro_offering_photos(offering_id, order_index);

ALTER TABLE pro_offering_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_offering_photos FORCE ROW LEVEL SECURITY;

CREATE POLICY pro_offering_photos_public_read ON pro_offering_photos
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE OR REPLACE FUNCTION pro_offering_photos_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.photo_url := OLD.photo_url;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_offering_photos_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER pro_offering_photos_lock_privileged
  BEFORE UPDATE ON pro_offering_photos
  FOR EACH ROW EXECUTE FUNCTION pro_offering_photos_whitelist_columns();

-- ============================================================================
-- add_pro_photo — pro only, 25 max per pro
-- ============================================================================
CREATE OR REPLACE FUNCTION add_pro_photo(p_photo_url TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_next_index INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_url IS NULL OR char_length(p_photo_url) < 1 OR char_length(p_photo_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_pro_photo:' || v_user_id::text));

  SELECT count(*) INTO v_count FROM pro_profile_photos WHERE pro_id = v_user_id;
  IF v_count >= 25 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT COALESCE(MAX(order_index), -1) + 1 INTO v_next_index
  FROM pro_profile_photos WHERE pro_id = v_user_id;

  INSERT INTO pro_profile_photos (pro_id, photo_url, order_index)
  VALUES (v_user_id, p_photo_url, v_next_index)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION add_pro_photo FROM anon;
GRANT EXECUTE ON FUNCTION add_pro_photo TO authenticated;

-- ============================================================================
-- remove_pro_photo — owner only
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_pro_photo(p_photo_id UUID)
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

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_profile_photos WHERE id = p_photo_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_profile_photos WHERE id = p_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_pro_photo FROM anon;
GRANT EXECUTE ON FUNCTION remove_pro_photo TO authenticated;

-- ============================================================================
-- set_pro_photo_url — owner only, replace URL in place (keeps order_index)
-- ============================================================================
CREATE OR REPLACE FUNCTION set_pro_photo_url(p_photo_id UUID, p_photo_url TEXT)
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

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_profile_photos WHERE id = p_photo_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_url IS NULL OR char_length(p_photo_url) < 1 OR char_length(p_photo_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profile_photos SET photo_url = p_photo_url WHERE id = p_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION set_pro_photo_url FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_photo_url TO authenticated;

-- ============================================================================
-- reorder_pro_photos — owner only, full reorder
-- Uses a two-pass shift (offset by 1000) to dodge the UNIQUE constraint
-- without DEFERRABLE. Array length must match current photo count.
-- ============================================================================
CREATE OR REPLACE FUNCTION reorder_pro_photos(p_photo_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_owned_count INTEGER;
  v_target_count INTEGER;
  i INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_ids IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_target_count := array_length(p_photo_ids, 1);
  IF v_target_count IS NULL OR v_target_count = 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_count FROM pro_profile_photos WHERE pro_id = v_user_id;
  IF v_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_owned_count
  FROM pro_profile_photos
  WHERE pro_id = v_user_id AND id = ANY(p_photo_ids);
  IF v_owned_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Pass 1: shift everyone out of the [0, 25) window to free the targets.
  UPDATE pro_profile_photos
  SET order_index = order_index + 1000
  WHERE pro_id = v_user_id;

  -- Pass 2: assign each id its array position.
  FOR i IN 1..v_target_count LOOP
    UPDATE pro_profile_photos
    SET order_index = i - 1
    WHERE id = p_photo_ids[i] AND pro_id = v_user_id;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION reorder_pro_photos FROM anon;
GRANT EXECUTE ON FUNCTION reorder_pro_photos TO authenticated;

-- ============================================================================
-- add_pro_offering_photo — owner only, 25 max per offering
-- ============================================================================
CREATE OR REPLACE FUNCTION add_pro_offering_photo(
  p_offering_id UUID,
  p_photo_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_next_index INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_url IS NULL OR char_length(p_photo_url) < 1 OR char_length(p_photo_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_pro_offering_photo:' || p_offering_id::text));

  SELECT count(*) INTO v_count FROM pro_offering_photos WHERE offering_id = p_offering_id;
  IF v_count >= 25 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT COALESCE(MAX(order_index), -1) + 1 INTO v_next_index
  FROM pro_offering_photos WHERE offering_id = p_offering_id;

  INSERT INTO pro_offering_photos (offering_id, photo_url, order_index)
  VALUES (p_offering_id, p_photo_url, v_next_index)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION add_pro_offering_photo FROM anon;
GRANT EXECUTE ON FUNCTION add_pro_offering_photo TO authenticated;

-- ============================================================================
-- remove_pro_offering_photo — owner only
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_pro_offering_photo(p_photo_id UUID)
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

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pro_offering_photos p
    JOIN pro_offerings o ON o.id = p.offering_id
    WHERE p.id = p_photo_id AND o.pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_offering_photos WHERE id = p_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_pro_offering_photo FROM anon;
GRANT EXECUTE ON FUNCTION remove_pro_offering_photo TO authenticated;

-- ============================================================================
-- set_pro_offering_photo_url — owner only, replace in place
-- ============================================================================
CREATE OR REPLACE FUNCTION set_pro_offering_photo_url(
  p_photo_id UUID,
  p_photo_url TEXT
)
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

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pro_offering_photos p
    JOIN pro_offerings o ON o.id = p.offering_id
    WHERE p.id = p_photo_id AND o.pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_url IS NULL OR char_length(p_photo_url) < 1 OR char_length(p_photo_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_offering_photos SET photo_url = p_photo_url WHERE id = p_photo_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION set_pro_offering_photo_url FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_offering_photo_url TO authenticated;

-- ============================================================================
-- reorder_pro_offering_photos — owner only
-- ============================================================================
CREATE OR REPLACE FUNCTION reorder_pro_offering_photos(
  p_offering_id UUID,
  p_photo_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_owned_count INTEGER;
  v_target_count INTEGER;
  i INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_photo_ids IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_target_count := array_length(p_photo_ids, 1);
  IF v_target_count IS NULL OR v_target_count = 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_count FROM pro_offering_photos WHERE offering_id = p_offering_id;
  IF v_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_owned_count
  FROM pro_offering_photos
  WHERE offering_id = p_offering_id AND id = ANY(p_photo_ids);
  IF v_owned_count <> v_target_count THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE pro_offering_photos
  SET order_index = order_index + 1000
  WHERE offering_id = p_offering_id;

  FOR i IN 1..v_target_count LOOP
    UPDATE pro_offering_photos
    SET order_index = i - 1
    WHERE id = p_photo_ids[i] AND offering_id = p_offering_id;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION reorder_pro_offering_photos FROM anon;
GRANT EXECUTE ON FUNCTION reorder_pro_offering_photos TO authenticated;
