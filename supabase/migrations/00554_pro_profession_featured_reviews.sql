-- ============================================================================
-- 00554 — Page pro refonte, lot base (Scott 2026-10-25, DECISIONS du jour).
--
--   (1) pro_profiles.profession : le métier déclaré, liste fermée (codes
--       stables, libellés côté app). Nullable : les pros existants le
--       renseignent à la prochaine modification. Affiché sous le nom, filtre
--       de la carte. Réponse pragmatique à « vérification diplôme » : une
--       profession déclarée en clair, pas de vérification.
--   (2) pro_profiles.featured_offering_id : la sortie mise en avant sur la
--       page (à défaut la première). FK ON DELETE SET NULL. Ne peut désigner
--       qu'une offre du pro lui-même (erreur générique sinon : ne pas révéler
--       l'existence d'une offre d'autrui).
--   (3) register_as_pro / update_pro_profile prennent p_profession ;
--       update_pro_profile prend p_featured_offering_id et sait vider
--       'profession'. Signatures changées → DROP de l'ancienne (pas
--       d'overload ambigu pour PostgREST) + GRANT explicite (00511).
--   (4) get_my_pro_application renvoie les deux colonnes.
--   (5) Avis réservés à qui a réservé : create_pro_review et
--       create_offering_review exigent une réservation du membre, acceptée et
--       passée (bookings.status = 'accepted', day < aujourd'hui), chez ce pro /
--       sur cette offre. Sinon junto.review_requires_booking (non sensible :
--       l'état du demandeur lui-même). Les avis déjà en base restent.
-- ============================================================================

-- (1) + (2) colonnes ---------------------------------------------------------
ALTER TABLE public.pro_profiles
  ADD COLUMN profession text,
  ADD COLUMN featured_offering_id uuid REFERENCES public.pro_offerings(id) ON DELETE SET NULL;

ALTER TABLE public.pro_profiles
  ADD CONSTRAINT pro_profiles_profession_check CHECK (
    profession IS NULL OR profession = ANY (ARRAY[
      'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
      'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
      'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other'
    ])
  );

-- Les droits de pro_profiles sont par colonne (00418) : les deux nouvelles
-- sont publiques, comme la tagline.
GRANT SELECT(profession) ON TABLE public.pro_profiles TO authenticated;
GRANT SELECT(featured_offering_id) ON TABLE public.pro_profiles TO authenticated;

-- (3a) register_as_pro + p_profession -----------------------------------------
DROP FUNCTION public.register_as_pro(text, text, text, text, text, text, text, text, text, text, double precision, double precision, text);

CREATE OR REPLACE FUNCTION public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text, p_profession text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  -- 00519: same link rules as the table checks, with a readable error.
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF (p_facebook IS NOT NULL AND p_facebook ~* '^[a-z][a-z0-9+.-]*:' AND p_facebook !~* '^https?://')
     OR (p_instagram IS NOT NULL AND p_instagram ~* '^[a-z][a-z0-9+.-]*:' AND p_instagram !~* '^https?://') THEN
    RAISE EXCEPTION 'junto.pro_website_invalid';
  END IF;
  -- 00554: declared profession, closed list (the table CHECK is the last word).
  IF p_profession IS NOT NULL AND p_profession <> ALL (ARRAY[
      'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
      'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
      'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other']) THEN
    RAISE EXCEPTION 'junto.pro_profession_invalid';
  END IF;

  v_clean_name := regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g');
  v_clean_tagline := CASE WHEN p_tagline IS NOT NULL AND char_length(trim(p_tagline)) > 0
                          THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE NULL END;
  v_clean_description := CASE WHEN p_description IS NOT NULL AND char_length(trim(p_description)) > 0
                              THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE NULL END;

  INSERT INTO pro_profiles (
    user_id, display_name, company_name, real_name, status, tagline, description,
    website, email, phone, instagram, facebook,
    primary_lng, primary_lat, primary_location, primary_location_name, profession
  )
  VALUES (
    v_user_id, v_clean_name,
    regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g'),
    regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g'),
    'pending', v_clean_tagline, v_clean_description,
    p_website, p_email, p_phone, p_instagram, p_facebook,
    p_primary_lng, p_primary_lat,
    ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography,
    trim(p_primary_location_name), p_profession
  );
  -- NB: tier stays 'free' — approve_pro flips it to 'pro'.
END;
$function$;
GRANT EXECUTE ON FUNCTION public.register_as_pro(text, text, text, text, text, text, text, text, text, text, double precision, double precision, text, text) TO authenticated;

-- (3b) update_pro_profile + p_profession, p_featured_offering_id ---------------
DROP FUNCTION public.update_pro_profile(text, text, text, text, text, text, text, text, double precision, double precision, text, text, text, text[]);

CREATE OR REPLACE FUNCTION public.update_pro_profile(p_display_name text DEFAULT NULL::text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text, p_company_name text DEFAULT NULL::text, p_real_name text DEFAULT NULL::text, p_clear text[] DEFAULT NULL::text[], p_profession text DEFAULT NULL::text, p_featured_offering_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_existing RECORD;
  v_location_changing BOOLEAN := false;
  v_clear TEXT[] := COALESCE(p_clear, ARRAY[]::TEXT[]);
  v_col TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_existing IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00443 B3 : une fois APPROUVÉ, raison sociale et identité sont gelées —
  -- les renvoyer inchangées est permis, les changer passe par nous.
  IF v_existing.status = 'approved' THEN
    IF (p_company_name IS NOT NULL
        AND trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.company_name)
       OR (p_real_name IS NOT NULL
        AND trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.real_name) THEN
      RAISE EXCEPTION 'junto.pro_identity_locked';
    END IF;
  END IF;

  -- 00444 (1) : liste blanche des colonnes vidables. ≤ 8 entrées, toutes connues.
  -- 00554 : + 'profession' (la sortie mise en avant se vide en passant une
  -- offre NULL… impossible à distinguer de « ne pas toucher » : voir plus bas,
  -- 'featured_offering_id' se vide par p_clear aussi).
  IF array_length(v_clear, 1) > 9 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  FOREACH v_col IN ARRAY v_clear LOOP
    IF v_col IS NULL OR v_col NOT IN ('tagline', 'description', 'website', 'email', 'phone', 'instagram', 'facebook', 'profession', 'featured_offering_id') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END LOOP;

  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00444 (2) : cooldown seulement pour une enseigne publique (approved).
    IF v_existing.status = 'approved'
       AND v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'junto.pro_location_cooldown';
    END IF;
    v_location_changing := true;
  END IF;

  IF p_display_name IS NOT NULL AND (char_length(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_real_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00499 (B11): a tappable link must be a web address (no javascript:, data:…).
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: same link rules as the table checks, with a readable error.
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF (p_facebook IS NOT NULL AND p_facebook ~* '^[a-z][a-z0-9+.-]*:' AND p_facebook !~* '^https?://')
     OR (p_instagram IS NOT NULL AND p_instagram ~* '^[a-z][a-z0-9+.-]*:' AND p_instagram !~* '^https?://') THEN
    RAISE EXCEPTION 'junto.pro_website_invalid';
  END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_primary_location_name) > 200) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00554: declared profession, closed list (the table CHECK is the last word).
  IF p_profession IS NOT NULL AND p_profession <> ALL (ARRAY[
      'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
      'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
      'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other']) THEN
    RAISE EXCEPTION 'junto.pro_profession_invalid';
  END IF;
  -- 00554: the featured outing must be one of MINE — generic error otherwise,
  -- so the existence of someone else's offering is never confirmed.
  IF p_featured_offering_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_offerings o WHERE o.id = p_featured_offering_id AND o.pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET
    display_name = COALESCE(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g')), display_name),
    company_name = CASE WHEN p_company_name IS NOT NULL THEN trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) ELSE company_name END,
    real_name = CASE WHEN p_real_name IS NOT NULL THEN trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) ELSE real_name END,
    tagline = CASE WHEN 'tagline' = ANY(v_clear) THEN NULL
                   WHEN p_tagline IS NOT NULL THEN trim(regexp_replace(p_tagline, '<[^>]*>', '', 'g')) ELSE tagline END,
    description = CASE WHEN 'description' = ANY(v_clear) THEN NULL
                       WHEN p_description IS NOT NULL THEN trim(regexp_replace(p_description, '<[^>]*>', '', 'g')) ELSE description END,
    website = CASE WHEN 'website' = ANY(v_clear) THEN NULL ELSE COALESCE(p_website, website) END,
    email = CASE WHEN 'email' = ANY(v_clear) THEN NULL ELSE COALESCE(p_email, email) END,
    phone = CASE WHEN 'phone' = ANY(v_clear) THEN NULL ELSE COALESCE(p_phone, phone) END,
    instagram = CASE WHEN 'instagram' = ANY(v_clear) THEN NULL ELSE COALESCE(p_instagram, instagram) END,
    facebook = CASE WHEN 'facebook' = ANY(v_clear) THEN NULL ELSE COALESCE(p_facebook, facebook) END,
    profession = CASE WHEN 'profession' = ANY(v_clear) THEN NULL ELSE COALESCE(p_profession, profession) END,
    featured_offering_id = CASE WHEN 'featured_offering_id' = ANY(v_clear) THEN NULL ELSE COALESCE(p_featured_offering_id, featured_offering_id) END,
    primary_lng = CASE WHEN v_location_changing THEN p_primary_lng ELSE primary_lng END,
    primary_lat = CASE WHEN v_location_changing THEN p_primary_lat ELSE primary_lat END,
    primary_location = CASE WHEN v_location_changing
                            THEN ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography
                            ELSE primary_location END,
    primary_location_name = CASE WHEN v_location_changing THEN trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g')) ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.update_pro_profile(text, text, text, text, text, text, text, text, double precision, double precision, text, text, text, text[], text, uuid) TO authenticated;

-- (4) get_my_pro_application + les deux colonnes -------------------------------
DROP FUNCTION public.get_my_pro_application();

CREATE OR REPLACE FUNCTION public.get_my_pro_application()
 RETURNS TABLE(user_id uuid, display_name text, company_name text, real_name text, tagline text, description text, website text, email text, phone text, instagram text, facebook text, primary_lng double precision, primary_lat double precision, primary_location_name text, pin_image_url text, pin_icon text, status text, rejection_reason text, last_location_change_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone, profession text, featured_offering_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.tagline, pp.description, pp.website, pp.email, pp.phone,
         pp.instagram, pp.facebook,
         pp.primary_lng, pp.primary_lat, pp.primary_location_name,
         pp.pin_image_url, pp.pin_icon,
         pp.status, pp.rejection_reason,
         pp.last_location_change_at, pp.created_at, pp.updated_at,
         pp.profession, pp.featured_offering_id
  FROM pro_profiles pp
  WHERE pp.user_id = v_user_id;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.get_my_pro_application() TO authenticated;

-- (5) avis réservés à qui a réservé ---------------------------------------------
CREATE OR REPLACE FUNCTION public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
  v_reviewer_name TEXT;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00443 B5 : cible démo refusée (même erreur générique qu'inexistante).
  -- 00505 (B8): only an approved pro can be reviewed (same generic error).
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND is_demo = false AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = p_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00554: a review needs a booking with this pro, accepted and already past.
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.pro_id = p_pro_id AND b.client_id = v_user_id
      AND b.status = 'accepted' AND b.day < current_date
  ) THEN
    RAISE EXCEPTION 'junto.review_requires_booking';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM pro_reviews WHERE pro_id = p_pro_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'junto.review_duplicate';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.review_rate_limit'; END IF;

  BEGIN
    INSERT INTO pro_reviews (pro_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_pro_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = p_pro_id;
  PERFORM notify_review_received(
    p_pro_id,
    v_reviewer_name,
    p_rating,
    v_pro_name,
    jsonb_build_object('pro_id', p_pro_id, 'review_id', v_review_id, 'reviewer_id', v_user_id)
  );

  RETURN v_review_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_pro_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
  v_reviewer_name TEXT;
  v_offering_title TEXT;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT o.pro_id, o.title, o.is_demo INTO v_pro_id, v_offering_title, v_is_demo FROM pro_offerings o
  WHERE o.id = p_offering_id
    -- 00505 (B8): an approved pro's offering only.
    AND EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = o.pro_id AND pp.status = 'approved');
  -- 00443 B5 : offre démo refusée (même erreur générique qu'inexistante).
  IF v_pro_id IS NULL OR v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00554: a review needs a booking of this offering, accepted and already past.
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.offering_id = p_offering_id AND b.client_id = v_user_id
      AND b.status = 'accepted' AND b.day < current_date
  ) THEN
    RAISE EXCEPTION 'junto.review_requires_booking';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM offering_reviews WHERE offering_id = p_offering_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'junto.review_duplicate';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.review_rate_limit'; END IF;

  BEGIN
    INSERT INTO offering_reviews (offering_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_offering_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  PERFORM notify_review_received(
    v_pro_id,
    v_reviewer_name,
    p_rating,
    v_offering_title,
    jsonb_build_object('offering_id', p_offering_id, 'review_id', v_review_id, 'reviewer_id', v_user_id)
  );

  RETURN v_review_id;
END;
$function$;
