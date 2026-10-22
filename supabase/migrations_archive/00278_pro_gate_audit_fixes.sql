-- ============================================================================
-- Pro approval gate — audit fixes (see chat audit).
--  1. update_pro_profile gains company_name/real_name so a rejected pro can
--     actually correct the verification fields and resubmit.
--  2. Gate set_pro_pin_image / set_pro_banner on status='approved'.
--  3. Whitelist trigger protects the new privileged columns (status/reviewed_*/
--     verification) — "new columns protected by default".
--  4. Trigger blocks reviews on a non-approved pro.
-- ============================================================================

-- 1. update_pro_profile (+ verification fields) -------------------------------
DROP FUNCTION IF EXISTS update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT);
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
  p_primary_location_name TEXT DEFAULT NULL,
  p_company_name TEXT DEFAULT NULL,
  p_real_name TEXT DEFAULT NULL
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

  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_location_changing := true;
  END IF;

  IF p_display_name IS NOT NULL AND (char_length(trim(p_display_name)) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(trim(p_company_name)) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(trim(p_real_name)) < 2 OR char_length(p_real_name) > 120) THEN
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
    company_name = CASE WHEN p_company_name IS NOT NULL THEN regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g') ELSE company_name END,
    real_name = CASE WHEN p_real_name IS NOT NULL THEN regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g') ELSE real_name END,
    tagline = CASE WHEN p_tagline IS NOT NULL THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE tagline END,
    description = CASE WHEN p_description IS NOT NULL THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE description END,
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
    primary_location_name = CASE WHEN v_location_changing THEN trim(p_primary_location_name) ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT) TO authenticated;

-- 2. Gate pin / banner on approval -------------------------------------------
CREATE OR REPLACE FUNCTION set_pro_pin_image(p_pin_image_url TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_pin_image_url IS NOT NULL AND char_length(p_pin_image_url) > 500 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE pro_profiles SET pin_image_url = p_pin_image_url WHERE user_id = v_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION set_pro_pin_image(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_pin_image(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION set_pro_banner(p_banner_url TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_banner_url IS NOT NULL AND char_length(p_banner_url) > 500 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE pro_profiles SET banner_url = p_banner_url WHERE user_id = v_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION set_pro_banner FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_banner TO authenticated;

-- 3. Whitelist trigger: protect the privileged review/verification columns ----
CREATE OR REPLACE FUNCTION pro_profiles_whitelist_columns()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.user_id := OLD.user_id;
  NEW.created_at := OLD.created_at;
  NEW.last_location_change_at := OLD.last_location_change_at;
  NEW.status := OLD.status;
  NEW.company_name := OLD.company_name;
  NEW.real_name := OLD.real_name;
  NEW.rejection_reason := OLD.rejection_reason;
  NEW.reviewed_at := OLD.reviewed_at;
  NEW.reviewed_by := OLD.reviewed_by;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION pro_profiles_whitelist_columns FROM anon, authenticated;

-- 4. Block reviews on a non-approved pro -------------------------------------
CREATE OR REPLACE FUNCTION pro_reviews_require_approved()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = NEW.pro_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION pro_reviews_require_approved() FROM anon, authenticated;

DROP TRIGGER IF EXISTS pro_reviews_require_approved_trg ON pro_reviews;
CREATE TRIGGER pro_reviews_require_approved_trg
  BEFORE INSERT ON pro_reviews
  FOR EACH ROW EXECUTE FUNCTION pro_reviews_require_approved();
