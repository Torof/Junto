-- ============================================================================
-- Pro approval gate. Pros now register as 'pending'; an admin approves before
-- tier flips to 'pro' and the page goes live. Adds verification fields
-- (company_name + real_name; real_name kept private — admin/owner only via RLS,
-- never selected for public pin/list reads). See chat for the validated
-- authorization chains.
-- ============================================================================

-- 1. Schema -------------------------------------------------------------------
ALTER TABLE pro_profiles
  ADD COLUMN status TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('pending', 'approved', 'rejected')),
  ADD COLUMN company_name TEXT CHECK (company_name IS NULL OR char_length(company_name) BETWEEN 2 AND 120),
  ADD COLUMN real_name TEXT CHECK (real_name IS NULL OR char_length(real_name) BETWEEN 2 AND 120),
  ADD COLUMN rejection_reason TEXT CHECK (rejection_reason IS NULL OR char_length(rejection_reason) <= 500),
  ADD COLUMN reviewed_at TIMESTAMPTZ,
  ADD COLUMN reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL;

-- Existing pros are grandfathered approved (the ADD default backfilled them);
-- future registrations default to pending.
ALTER TABLE pro_profiles ALTER COLUMN status SET DEFAULT 'pending';

-- 2. Visibility: only approved pros are public; owner + admins see their own
--    pending/rejected (so pending pros never hit the map, search, or pins).
DROP POLICY IF EXISTS pro_profiles_select ON pro_profiles;
CREATE POLICY "pro_profiles_select"
  ON pro_profiles FOR SELECT
  TO authenticated
  USING (
    NOT EXISTS (SELECT 1 FROM users u WHERE u.id = pro_profiles.user_id AND u.suspended_at IS NOT NULL)
    AND (
      pro_profiles.status = 'approved'
      OR pro_profiles.user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true)
    )
  );

-- 3. register_as_pro — creates a PENDING application; tier stays 'free' until
--    an admin approves. Adds required company_name + real_name.
DROP FUNCTION IF EXISTS register_as_pro(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT);
CREATE OR REPLACE FUNCTION register_as_pro(
  p_display_name TEXT,
  p_company_name TEXT,
  p_real_name TEXT,
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
  IF p_company_name IS NULL OR char_length(trim(p_company_name)) < 2 OR char_length(p_company_name) > 120 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NULL OR char_length(trim(p_real_name)) < 2 OR char_length(p_real_name) > 120 THEN
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

  v_clean_name := regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g');
  v_clean_tagline := CASE WHEN p_tagline IS NOT NULL AND char_length(trim(p_tagline)) > 0
                          THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE NULL END;
  v_clean_description := CASE WHEN p_description IS NOT NULL AND char_length(trim(p_description)) > 0
                              THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE NULL END;

  INSERT INTO pro_profiles (
    user_id, display_name, company_name, real_name, status, tagline, description,
    website, email, phone, instagram, facebook,
    primary_lng, primary_lat, primary_location, primary_location_name
  )
  VALUES (
    v_user_id, v_clean_name,
    regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g'),
    regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g'),
    'pending', v_clean_tagline, v_clean_description,
    p_website, p_email, p_phone, p_instagram, p_facebook,
    p_primary_lng, p_primary_lat,
    ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography,
    trim(p_primary_location_name)
  );
  -- NB: tier stays 'free' — approve_pro flips it to 'pro'.
END;
$$;

REVOKE ALL ON FUNCTION register_as_pro(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_as_pro(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT) TO authenticated;

-- 4. approve_pro — admin only. Flips status + tier, notifies the user.
CREATE OR REPLACE FUNCTION approve_pro(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'approved', rejection_reason = NULL, reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;
  UPDATE users SET tier = 'pro' WHERE id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_approved', 'Page pro validée',
          'Ta page pro est en ligne. Tu peux maintenant publier tes offres. 🎉',
          jsonb_build_object('pro_id', p_user_id));
END;
$$;
REVOKE ALL ON FUNCTION approve_pro(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION approve_pro(UUID) TO authenticated;

-- 5. reject_pro — admin only. Marks rejected (with reason), notifies; tier untouched.
CREATE OR REPLACE FUNCTION reject_pro(p_user_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reason IS NOT NULL AND char_length(p_reason) > 500 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'rejected', rejection_reason = NULLIF(trim(coalesce(p_reason, '')), ''),
        reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_rejected', 'Demande pro refusée',
          coalesce(NULLIF(trim(coalesce(p_reason, '')), ''), 'Ta demande de page pro n''a pas été validée. Tu peux corriger tes informations et soumettre à nouveau.'),
          jsonb_build_object('pro_id', p_user_id));
END;
$$;
REVOKE ALL ON FUNCTION reject_pro(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION reject_pro(UUID, TEXT) TO authenticated;

-- 6. resubmit_pro_application — owner re-submits a rejected application.
CREATE OR REPLACE FUNCTION resubmit_pro_application()
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
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'rejected') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET status = 'pending', rejection_reason = NULL, reviewed_at = NULL, reviewed_by = NULL
    WHERE user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION resubmit_pro_application() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resubmit_pro_application() TO authenticated;

-- 7. Gate offering creation: a pending/rejected pro can't publish offerings.
--    Trigger keeps the big create_pro_offering function untouched.
CREATE OR REPLACE FUNCTION pro_offerings_require_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = NEW.pro_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION pro_offerings_require_approved() FROM anon, authenticated;

DROP TRIGGER IF EXISTS pro_offerings_require_approved_trg ON pro_offerings;
CREATE TRIGGER pro_offerings_require_approved_trg
  BEFORE INSERT ON pro_offerings
  FOR EACH ROW EXECUTE FUNCTION pro_offerings_require_approved();
