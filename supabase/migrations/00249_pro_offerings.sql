-- Migration 00249: pro_offerings table + RLS + RPCs.
--
-- A pro_offering is a catalog item the pro advertises: a named route or
-- activity at a specific location, with optional duration, schedule
-- text, gear info, and a single banner image. It has no scheduled
-- starts_at and no join mechanic — bookings happen off-platform via
-- the contact links exposed on the pro_profile.
--
-- Public reads, RPC-only writes. FORCE RLS + whitelist trigger on
-- privileged columns (id, pro_id, created_at) mirrors pro_profiles.

-- ============================================================================
-- Table
-- ============================================================================
CREATE TABLE pro_offerings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_id UUID NOT NULL REFERENCES pro_profiles(user_id) ON DELETE CASCADE,
  sport_id UUID NOT NULL REFERENCES sports(id) ON DELETE RESTRICT,
  title TEXT NOT NULL CHECK (char_length(trim(title)) BETWEEN 3 AND 100),
  description TEXT NOT NULL CHECK (char_length(description) <= 2000),
  level TEXT NOT NULL,
  location GEOGRAPHY(Point, 4326) NOT NULL,
  location_name TEXT NOT NULL CHECK (char_length(trim(location_name)) BETWEEN 1 AND 100),
  duration INTERVAL,
  max_participants INTEGER CHECK (max_participants IS NULL OR (max_participants BETWEEN 1 AND 50)),
  schedule_text TEXT CHECK (schedule_text IS NULL OR char_length(schedule_text) <= 100),
  distance_km NUMERIC CHECK (distance_km IS NULL OR (distance_km > 0 AND distance_km <= 9999)),
  elevation_gain_m INTEGER CHECK (elevation_gain_m IS NULL OR (elevation_gain_m > 0 AND elevation_gain_m <= 99999)),
  image_url TEXT CHECK (image_url IS NULL OR char_length(image_url) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX pro_offerings_pro_id_idx ON pro_offerings(pro_id);
CREATE INDEX pro_offerings_pro_created_idx ON pro_offerings(pro_id, created_at DESC);
CREATE INDEX pro_offerings_location_idx ON pro_offerings USING GIST(location);

-- ============================================================================
-- RLS
-- ============================================================================
ALTER TABLE pro_offerings ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_offerings FORCE ROW LEVEL SECURITY;

CREATE POLICY pro_offerings_public_read ON pro_offerings
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- No INSERT/UPDATE/DELETE policies — RPCs are the only write path.

-- ============================================================================
-- Privileged-column whitelist trigger
-- Forces id / pro_id / created_at to OLD on any UPDATE that isn't
-- explicitly bypassing via junto.bypass_lock.
-- ============================================================================
CREATE OR REPLACE FUNCTION pro_offerings_whitelist_columns()
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
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_offerings_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER pro_offerings_lock_privileged
  BEFORE UPDATE ON pro_offerings
  FOR EACH ROW EXECUTE FUNCTION pro_offerings_whitelist_columns();

-- ============================================================================
-- updated_at touch trigger
-- ============================================================================
CREATE OR REPLACE FUNCTION pro_offerings_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_offerings_touch_updated_at FROM anon, authenticated;

CREATE TRIGGER pro_offerings_touch_updated_at_trg
  BEFORE UPDATE ON pro_offerings
  FOR EACH ROW EXECUTE FUNCTION pro_offerings_touch_updated_at();

-- ============================================================================
-- create_pro_offering — pro only, max 50 offerings per pro
-- ============================================================================
CREATE OR REPLACE FUNCTION create_pro_offering(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_location_lng FLOAT,
  p_location_lat FLOAT,
  p_location_name TEXT,
  p_duration TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_schedule_text TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_offering_id UUID;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
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

  -- Input validation
  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize per-pro to make the 50-cap check + insert atomic.
  PERFORM pg_advisory_xact_lock(hashtext('create_offering:' || v_user_id::text));

  SELECT count(*) INTO v_count
  FROM pro_offerings
  WHERE pro_id = v_user_id;

  IF v_count >= 50 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO pro_offerings (
    pro_id, sport_id, title, description, level,
    location, location_name,
    duration, max_participants, schedule_text,
    distance_km, elevation_gain_m,
    created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_clean_title, p_description, p_level,
    ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    v_clean_location_name,
    CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    p_max_participants,
    v_clean_schedule,
    p_distance_km,
    p_elevation_gain_m,
    now(), now()
  ) RETURNING id INTO v_offering_id;

  RETURN v_offering_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_pro_offering FROM anon;
GRANT EXECUTE ON FUNCTION create_pro_offering TO authenticated;

-- ============================================================================
-- update_pro_offering — owner only
-- ============================================================================
CREATE OR REPLACE FUNCTION update_pro_offering(
  p_offering_id UUID,
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_location_lng FLOAT,
  p_location_lat FLOAT,
  p_location_name TEXT,
  p_duration TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_schedule_text TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
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

  -- Ownership check
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Input validation (identical to create)
  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_offerings SET
    sport_id = p_sport_id,
    title = v_clean_title,
    description = p_description,
    level = p_level,
    location = ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    location_name = v_clean_location_name,
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    max_participants = p_max_participants,
    schedule_text = v_clean_schedule,
    distance_km = p_distance_km,
    elevation_gain_m = p_elevation_gain_m
  WHERE id = p_offering_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_pro_offering FROM anon;
GRANT EXECUTE ON FUNCTION update_pro_offering TO authenticated;

-- ============================================================================
-- delete_pro_offering — owner only
-- ============================================================================
CREATE OR REPLACE FUNCTION delete_pro_offering(p_offering_id UUID)
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
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_offerings WHERE id = p_offering_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION delete_pro_offering FROM anon;
GRANT EXECUTE ON FUNCTION delete_pro_offering TO authenticated;

-- ============================================================================
-- set_pro_offering_image — owner only. NULL clears the image.
-- ============================================================================
CREATE OR REPLACE FUNCTION set_pro_offering_image(
  p_offering_id UUID,
  p_image_url TEXT DEFAULT NULL
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
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_image_url IS NOT NULL AND char_length(p_image_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_offerings SET image_url = p_image_url WHERE id = p_offering_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION set_pro_offering_image FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_offering_image TO authenticated;
