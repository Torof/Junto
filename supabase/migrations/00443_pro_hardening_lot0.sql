-- ============================================================================
-- 00443 — Lot 0 du durcissement Pro (audit DB 2026-10-08, go Scott 2026-10-12).
--
-- Rituel live-version : chaque objet est reconstruit depuis sa DERNIÈRE
-- définition (listée), pas depuis la première.
--
--   B1  pro_profiles_select     ← 00334 (00277 avant). Régression : sous-requête
--       directe sur `users` → no-op silencieux sous users_select_own (le bug
--       00256, 3e réintroduction). Un pro suspendu restait visible (pin, fiche,
--       favoris). Fix : private.user_is_suspended + admin non suspendu.
--   B2  cancel_booking          ← 00420. `client_id != uid` vaut NULL sur une
--       résa manuelle → l'IF ne levait pas. IS DISTINCT FROM.
--   B3  update_pro_profile      ← 00278. company_name/real_name gelés une fois
--       approved (junto.pro_identity_locked, i18n FR+EN).
--   B5  create_pro_review / create_offering_review ← 00272,
--       add_pro_community_photo ← 00418 : garde is_demo côté écriture (00426).
--   B6  unregister_as_pro       ← 00416. Purge pro_availabilities (FK users).
--   B13 pro_community_photos    ← policy 00349 (TO anon, authenticated) :
--       recréée TO authenticated + REVOKE SELECT anon (le web ne la lit pas).
--
-- Aucune signature ne change → aucun DROP nécessaire, grants inchangés
-- (re-posés par sûreté).
-- ============================================================================

-- ---------- B1 ----------
DROP POLICY IF EXISTS pro_profiles_select ON pro_profiles;
CREATE POLICY "pro_profiles_select"
  ON pro_profiles FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(pro_profiles.user_id)
    AND (pro_profiles.is_demo = false OR demo_content_visible())
    AND (
      pro_profiles.status = 'approved'
      OR pro_profiles.user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true AND suspended_at IS NULL)
    )
  );

-- ---------- B2 ----------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_client_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00420 D1 : un suspendu n'annule plus lui-même — ses réservations ont été
  -- auto-annulées à la suspension (admin_suspend_user).
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  -- 00443 B2 : IS DISTINCT FROM — sur une résa MANUELLE (client_id NULL),
  -- `!=` valait NULL et le IF ne levait pas : n'importe quel compte connaissant
  -- l'id pouvait l'annuler. Une manuelle n'a pas de client côté app : refus.
  IF v_bk IS NULL OR v_bk.client_id IS DISTINCT FROM v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'cancelled'
  WHERE id = p_booking_id AND status IN ('pending', 'accepted');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Le pro n'est prévenu que si c'était CONFIRMÉ (un pending annulé disparaît).
  IF v_bk.status = 'accepted' THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
    PERFORM create_notification(
      v_bk.pro_id,
      'booking_cancelled',
      'Réservation annulée',
      coalesce(v_client_name, 'Un client') || ' a annulé « '
        || coalesce(v_off_title, 'une sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM') || '.',
      jsonb_build_object('booking_id', v_bk.id, 'by', 'client')
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION cancel_booking(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION cancel_booking(UUID) TO authenticated;

-- ---------- B3 ----------
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

  -- 00443 B3 : une fois APPROUVÉ, les deux champs sur lesquels l'admin a
  -- validé la candidature (raison sociale, identité) sont gelés — les
  -- renvoyer inchangés est permis (le client renvoie tout le formulaire),
  -- les changer passe par nous. Code actionnable : c'est l'état du pro.
  IF v_existing.status = 'approved' THEN
    IF (p_company_name IS NOT NULL
        AND regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g') IS DISTINCT FROM v_existing.company_name)
       OR (p_real_name IS NOT NULL
        AND regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g') IS DISTINCT FROM v_existing.real_name) THEN
      RAISE EXCEPTION 'junto.pro_identity_locked';
    END IF;
  END IF;

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
REVOKE ALL ON FUNCTION update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT) TO authenticated;

-- ---------- B5 ----------
CREATE OR REPLACE FUNCTION create_pro_review(
  p_pro_id UUID,
  p_rating SMALLINT,
  p_body TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  -- 00443 B5 : cible démo refusée (même erreur générique qu'inexistante).
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND is_demo = false) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = p_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
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
    jsonb_build_object('pro_id', p_pro_id, 'review_id', v_review_id)
  );

  RETURN v_review_id;
END;
$$;
REVOKE ALL ON FUNCTION create_pro_review(UUID, SMALLINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_pro_review(UUID, SMALLINT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION create_offering_review(
  p_offering_id UUID,
  p_rating SMALLINT,
  p_body TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  SELECT pro_id, title, is_demo INTO v_pro_id, v_offering_title, v_is_demo FROM pro_offerings WHERE id = p_offering_id;
  -- 00443 B5 : offre démo refusée (même erreur générique qu'inexistante).
  IF v_pro_id IS NULL OR v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
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
    jsonb_build_object('offering_id', p_offering_id, 'review_id', v_review_id)
  );

  RETURN v_review_id;
END;
$$;
REVOKE ALL ON FUNCTION create_offering_review(UUID, SMALLINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_offering_review(UUID, SMALLINT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION add_pro_community_photo(
  p_pro_id UUID,
  p_photo_url TEXT,
  p_review_id UUID DEFAULT NULL,
  p_offering_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : cible = pro APPROUVÉ (ferme l'oracle de candidature — même
  -- erreur générique qu'une cible inexistante).
  -- 00443 B5 : et NON démo — un compte démo ne reçoit jamais d'écriture réelle (00426).
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND status = 'approved' AND is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : URL ancrée hôte + dossier du CONTRIBUTEUR (fin du wildcard).
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_review_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_reviews
    WHERE id = p_review_id AND reviewer_id = v_user_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_offering_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_offerings
    WHERE id = p_offering_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_community_photo:' || v_user_id::text || ':' || p_pro_id::text));

  SELECT count(*) INTO v_count
  FROM pro_community_photos
  WHERE pro_id = p_pro_id AND contributor_id = v_user_id;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'junto.photo_limit';
  END IF;

  INSERT INTO pro_community_photos (pro_id, contributor_id, photo_url, review_id, offering_id)
  VALUES (p_pro_id, v_user_id, p_photo_url, p_review_id, p_offering_id)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$$;
REVOKE ALL ON FUNCTION add_pro_community_photo(UUID, TEXT, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_pro_community_photo(UUID, TEXT, UUID, UUID) TO authenticated;

-- ---------- B6 ----------
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

  -- 00416 : refuser tant que des réservations futures vivantes existent
  -- (le CASCADE pro_profiles → pro_offerings → bookings serait silencieux).
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE pro_id = v_user_id
      AND status IN ('pending', 'accepted')
      AND day >= current_date
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  -- 00443 B6 : pro_availabilities référence users, pas pro_profiles — sans
  -- ceci les créneaux ouverts survivaient à la désinscription et redevenaient
  -- réservables tels quels à une ré-inscription.
  DELETE FROM pro_availabilities WHERE pro_id = v_user_id;
  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION unregister_as_pro() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION unregister_as_pro() TO authenticated;

-- ---------- B13 ----------
DROP POLICY IF EXISTS pro_community_photos_public_read ON pro_community_photos;
CREATE POLICY pro_community_photos_public_read
  ON pro_community_photos FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(pro_id)
    AND (
      demo_content_visible()
      OR EXISTS (
        SELECT 1 FROM pro_profiles dp
        WHERE dp.user_id = pro_community_photos.pro_id AND dp.is_demo = false
      )
    )
  );
REVOKE SELECT ON pro_community_photos FROM anon;
