-- Migration 00240: Pro feature foundation — pro_profiles table + RPCs.
--
-- Phase 0 of the Pro feature. Adds:
--   - pro_profiles table: the "business identity" attached to a user
--     account. The user keeps their personal profile + reliability score;
--     this row is the public-facing service page (tagline, description,
--     contact info, primary location for the company pin).
--   - register_as_pro / update_pro_profile / unregister_as_pro RPCs —
--     self-claimed for v1 (no payment, no admin verification gate).
--   - is_recurring + recurrence_days columns on activities — Phase 3
--     uses these but the column is cheap and easier to add early.
--
-- Per docs/SECURITY.md "Pattern migration obligatoire": ENABLE + FORCE
-- RLS, owner-only writes via SECURITY DEFINER, suspension filter on
-- public reads, whitelist trigger on privileged columns.

-- ============================================================================
-- TABLE: pro_profiles
-- ============================================================================
CREATE TABLE pro_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 100),
  tagline TEXT CHECK (tagline IS NULL OR char_length(tagline) <= 120),
  description TEXT CHECK (description IS NULL OR char_length(description) <= 2000),
  website TEXT CHECK (website IS NULL OR char_length(website) <= 200),
  email TEXT CHECK (email IS NULL OR char_length(email) <= 200),
  phone TEXT CHECK (phone IS NULL OR char_length(phone) <= 30),
  instagram TEXT CHECK (instagram IS NULL OR char_length(instagram) <= 100),
  facebook TEXT CHECK (facebook IS NULL OR char_length(facebook) <= 200),
  primary_lng FLOAT NOT NULL CHECK (primary_lng BETWEEN -180 AND 180),
  primary_lat FLOAT NOT NULL CHECK (primary_lat BETWEEN -90 AND 90),
  primary_location GEOGRAPHY(POINT, 4326) NOT NULL,
  primary_location_name TEXT NOT NULL CHECK (char_length(primary_location_name) BETWEEN 1 AND 200),
  last_location_change_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX pro_profiles_location_gist ON pro_profiles USING GIST (primary_location);

ALTER TABLE pro_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_profiles FORCE ROW LEVEL SECURITY;

-- SELECT: any authenticated user can read a pro_profiles row, EXCEPT
-- when the pro is suspended (their public surface vanishes). Pro page
-- is a public-facing entity (Google-listing model), no blocked_users
-- filter (a blocked-by relationship doesn't make the business invisible
-- — but the underlying contact / message flows still respect blocks).
CREATE POLICY "pro_profiles_select"
  ON pro_profiles FOR SELECT
  TO authenticated
  USING (
    NOT EXISTS (SELECT 1 FROM users u WHERE u.id = pro_profiles.user_id AND u.suspended_at IS NOT NULL)
  );

-- INSERT/UPDATE/DELETE: via SECURITY DEFINER functions only.

-- ============================================================================
-- Whitelist trigger — protect privileged columns on pro_profiles.
-- user_id / created_at / last_location_change_at are RPC-managed and
-- must never be writable from any non-bypassed UPDATE. Even today
-- there's no INSERT/UPDATE policy so this is defence-in-depth, but
-- adding the trigger now matches the pattern used on users/activities
-- and locks the contract for future RLS changes.
-- ============================================================================
CREATE OR REPLACE FUNCTION pro_profiles_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.user_id := OLD.user_id;
  NEW.created_at := OLD.created_at;
  NEW.last_location_change_at := OLD.last_location_change_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION pro_profiles_whitelist_columns FROM anon, authenticated;

CREATE TRIGGER pro_profiles_lock_privileged
  BEFORE UPDATE ON pro_profiles
  FOR EACH ROW EXECUTE FUNCTION pro_profiles_whitelist_columns();

-- ============================================================================
-- Updated_at touch trigger
-- ============================================================================
CREATE OR REPLACE FUNCTION pro_profiles_touch_updated_at()
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

REVOKE EXECUTE ON FUNCTION pro_profiles_touch_updated_at FROM anon, authenticated;

CREATE TRIGGER pro_profiles_touch_updated_at_trg
  BEFORE UPDATE ON pro_profiles
  FOR EACH ROW EXECUTE FUNCTION pro_profiles_touch_updated_at();

-- ============================================================================
-- activities: add recurring fields (Phase 3 uses these — early addition
-- keeps later migrations smaller).
-- ============================================================================
ALTER TABLE activities
  ADD COLUMN is_recurring BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN recurrence_days INTEGER CHECK (recurrence_days IS NULL OR recurrence_days BETWEEN 1 AND 365);

-- Sanity: if marked recurring, must have a recurrence_days value.
ALTER TABLE activities
  ADD CONSTRAINT activities_recurring_has_days
  CHECK (NOT is_recurring OR recurrence_days IS NOT NULL);

-- ============================================================================
-- FUNCTION: register_as_pro
-- ============================================================================
CREATE OR REPLACE FUNCTION register_as_pro(
  p_display_name TEXT,
  p_tagline TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_website TEXT DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_instagram TEXT DEFAULT NULL,
  p_facebook TEXT DEFAULT NULL,
  p_primary_lng FLOAT DEFAULT NULL,
  p_primary_lat FLOAT DEFAULT NULL,
  p_primary_location_name TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_tagline TEXT;
  v_clean_description TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Required-field validation
  IF p_display_name IS NULL OR char_length(trim(p_display_name)) < 1 OR char_length(p_display_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_lng IS NULL OR p_primary_lat IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_location_name IS NULL OR char_length(trim(p_primary_location_name)) < 1 OR char_length(p_primary_location_name) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- HTML strip on free-form text fields (matches pattern from
  -- send_private_message / wall_messages / request_seat)
  v_clean_name := regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g');
  v_clean_tagline := CASE WHEN p_tagline IS NOT NULL AND char_length(trim(p_tagline)) > 0
                          THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE NULL END;
  v_clean_description := CASE WHEN p_description IS NOT NULL AND char_length(trim(p_description)) > 0
                              THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE NULL END;

  INSERT INTO pro_profiles (
    user_id, display_name, tagline, description,
    website, email, phone, instagram, facebook,
    primary_lng, primary_lat, primary_location, primary_location_name
  )
  VALUES (
    v_user_id, v_clean_name, v_clean_tagline, v_clean_description,
    p_website, p_email, p_phone, p_instagram, p_facebook,
    p_primary_lng, p_primary_lat,
    ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography,
    trim(p_primary_location_name)
  );

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'pro' WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION register_as_pro FROM anon;
GRANT EXECUTE ON FUNCTION register_as_pro TO authenticated;

-- ============================================================================
-- FUNCTION: update_pro_profile
-- All params nullable — only non-null params overwrite. Location change
-- is rate-limited to once per 30 days (Scott: "we can let it change once
-- a month more or less, for people that do seasonal work").
-- ============================================================================
CREATE OR REPLACE FUNCTION update_pro_profile(
  p_display_name TEXT DEFAULT NULL,
  p_tagline TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_website TEXT DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_instagram TEXT DEFAULT NULL,
  p_facebook TEXT DEFAULT NULL,
  p_primary_lng FLOAT DEFAULT NULL,
  p_primary_lat FLOAT DEFAULT NULL,
  p_primary_location_name TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_existing RECORD;
  v_location_changing BOOLEAN := false;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_existing IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Detect location change. Both lng and lat must be provided together
  -- if either is set, and location_name must come with them.
  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 30-day rate limit on location moves
    IF v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_location_changing := true;
  END IF;

  -- Length checks (apply only to provided fields)
  IF p_display_name IS NOT NULL AND (char_length(trim(p_display_name)) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(trim(p_primary_location_name)) < 1 OR char_length(p_primary_location_name) > 200) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET
    display_name = COALESCE(regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g'), display_name),
    tagline = CASE WHEN p_tagline IS NOT NULL
                   THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g')
                   ELSE tagline END,
    description = CASE WHEN p_description IS NOT NULL
                       THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g')
                       ELSE description END,
    website = COALESCE(p_website, website),
    email = COALESCE(p_email, email),
    phone = COALESCE(p_phone, phone),
    instagram = COALESCE(p_instagram, instagram),
    facebook = COALESCE(p_facebook, facebook),
    primary_lng = CASE WHEN v_location_changing THEN p_primary_lng ELSE primary_lng END,
    primary_lat = CASE WHEN v_location_changing THEN p_primary_lat ELSE primary_lat END,
    primary_location = CASE WHEN v_location_changing
                            THEN ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography
                            ELSE primary_location END,
    primary_location_name = CASE WHEN v_location_changing
                                 THEN trim(p_primary_location_name)
                                 ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_pro_profile FROM anon;
GRANT EXECUTE ON FUNCTION update_pro_profile TO authenticated;

-- ============================================================================
-- FUNCTION: unregister_as_pro
-- Refuses if the caller has any active (published / in_progress)
-- recurring activities — they must be deleted first. Avoids orphaned
-- recurring activities pointing at a non-pro creator.
-- ============================================================================
CREATE OR REPLACE FUNCTION unregister_as_pro()
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

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM activities
    WHERE creator_id = v_user_id
      AND is_recurring = true
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION unregister_as_pro FROM anon;
GRANT EXECUTE ON FUNCTION unregister_as_pro TO authenticated;
