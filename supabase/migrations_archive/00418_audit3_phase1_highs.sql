-- ============================================================================
-- 00418 — AUDIT 2026-09 Phase 1 : les 5 HIGH (docs/AUDIT_2026-09.md).
--   H5  reports.reporter_id → SET NULL (débloqueur RGPD de suppression de compte)
--   H1  anti-spam booking : compteur d'événements de soumission + cooldown
--   H2  accept_booking : retag 'booking' à la réactivation (fin de la promotion
--       sociale d'une demande refusée) + backstop unique_violation + un-hide +
--       gate pro approuvé sur le verbe accept
--   H4  pinning d'hôte sur les 6 setters d'images pro + gate approved sur les
--       photos communautaires + DROP set_pro_banner (code mort, colonne 00254)
--   H3  privilèges COLONNES sur pro_profiles (real_name & co) + 2 RPC
--       (get_my_pro_application, admin_get_pending_pro_applications)
-- ============================================================================

-- ---------- H5 : reports.reporter_id — anonymiser, ne jamais bloquer ----------
ALTER TABLE reports ALTER COLUMN reporter_id DROP NOT NULL;
ALTER TABLE reports DROP CONSTRAINT reports_reporter_id_fkey;
ALTER TABLE reports
  ADD CONSTRAINT reports_reporter_id_fkey
  FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE SET NULL;

-- ---------- H1 : colonnes anti-spam + trigger whitelist ----------
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS submitted_count INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS last_submitted_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION bookings_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.pro_id := OLD.pro_id;
  NEW.client_id := OLD.client_id;
  NEW.manual_name := OLD.manual_name;
  NEW.manual_phone := OLD.manual_phone;
  NEW.day := OLD.day;
  NEW.period := OLD.period;
  NEW.created_at := OLD.created_at;
  NEW.submitted_count := OLD.submitted_count;
  NEW.last_submitted_at := OLD.last_submitted_at;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ---------- H1 : create_booking — cooldown 1 h + plafond 5 soumissions/ligne ----------
CREATE OR REPLACE FUNCTION create_booking(
  p_offering_id UUID,
  p_day DATE,
  p_period TEXT,
  p_party_size INTEGER,
  p_message TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_msg TEXT;
  v_existing RECORD;
  v_booking_id UUID;
  v_client_name TEXT;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT po.id, po.pro_id, po.title, po.max_participants, pp.is_demo
    INTO v_off
  FROM pro_offerings po
  JOIN pro_profiles pp ON pp.user_id = po.pro_id
  JOIN users u ON u.id = po.pro_id
  WHERE po.id = p_offering_id
    AND pp.status = 'approved'
    AND u.suspended_at IS NULL
    AND u.tier = 'pro';
  IF v_off IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.is_demo = true AND NOT demo_content_visible() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_off.pro_id)
       OR (blocker_id = v_off.pro_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_day IS NULL OR p_day < current_date OR p_day > current_date + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_availabilities
    WHERE pro_id = v_off.pro_id AND day = p_day AND period = p_period
  ) THEN
    RAISE EXCEPTION 'junto.booking_slot_unavailable';
  END IF;

  IF p_party_size IS NULL
     OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  v_msg := nullif(regexp_replace(trim(coalesce(p_message, '')), '<[^>]*>', '', 'g'), '');
  IF v_msg IS NOT NULL AND char_length(v_msg) > 500 THEN
    RAISE EXCEPTION 'junto.booking_message';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND status = 'pending') >= 5 THEN
    RAISE EXCEPTION 'junto.booking_pending_cap';
  END IF;
  -- Cap quotidien inchangé : le trou H1 (cycles annuler/recréer sur la même
  -- ligne) est fermé par le cooldown 1 h + le plafond 5 soumissions/ligne
  -- ci-dessous — sans surcompter les soumissions anciennes d'une ligne réactivée.
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND created_at > now() - INTERVAL '24 hours') >= 10 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  SELECT * INTO v_existing FROM bookings
  WHERE offering_id = p_offering_id AND client_id = v_user_id
    AND day = p_day AND period = p_period
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status IN ('pending', 'accepted') THEN
      RAISE EXCEPTION 'junto.booking_already';
    END IF;
    -- Anti-spam (00418 H1) : cooldown 1 h entre soumissions du même créneau,
    -- plafond 5 soumissions par créneau à vie.
    IF v_existing.last_submitted_at > now() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    IF v_existing.submitted_count >= 5 THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'pending', party_size = p_party_size, message = v_msg,
        created_at = now(),
        submitted_count = v_existing.submitted_count + 1,
        last_submitted_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message)
      VALUES (p_offering_id, v_off.pro_id, v_user_id, p_day, p_period, p_party_size, v_msg)
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE p_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  PERFORM create_notification(
    v_off.pro_id,
    'booking_request',
    'Nouvelle demande de réservation',
    coalesce(v_client_name, 'Un membre') || ' — « ' || v_off.title || ' », le '
      || to_char(p_day, 'DD/MM') || ' ' || v_period_label
      || ' (' || p_party_size || ' pers.)',
    jsonb_build_object('booking_id', v_booking_id, 'offering_id', p_offering_id)
  );

  RETURN v_booking_id;
END;
$$;
REVOKE ALL ON FUNCTION create_booking(UUID, DATE, TEXT, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_booking(UUID, DATE, TEXT, INTEGER, TEXT) TO authenticated;

-- ---------- H2 : accept_booking — retag logistique + backstop + un-hide ----------
CREATE OR REPLACE FUNCTION accept_booking(p_booking_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_pro_name TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_updated INTEGER;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00418 : le verbe ACCEPT exige un pro encore approuvé (un pro révoqué garde
  -- cancel, perd accept) — inclut le check suspension.
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.status != 'pending' OR v_bk.client_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.pro_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
       OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'accepted' WHERE id = p_booking_id AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE v_bk.period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  IF v_bk.client_id < v_user_id THEN v_u1 := v_bk.client_id; v_u2 := v_user_id;
  ELSE v_u1 := v_user_id; v_u2 := v_bk.client_id; END IF;

  SELECT id INTO v_conversation_id FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES ('dm', v_u1, v_u2, v_user_id, 'active', 'booking', now(), now())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      -- Course avec un autre créateur de DM : récupérer la ligne fraîche.
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  END IF;

  -- 00418 H2 : la réactivation d'une ligne existante RETAGUE en logistique.
  -- Une demande sociale pending/declined ne devient JAMAIS un contact via le
  -- booking : initiated_from='booking' + purge des champs de requête. Le
  -- double consentement frais (demande client + accept pro) ne couvre que
  -- l'ouverture du fil, pas la classification sociale (invariant 00372).
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations
  SET status = 'active',
      initiated_from = CASE
        WHEN status != 'active' THEN 'booking'
        ELSE initiated_from
      END,
      request_sender_id = CASE WHEN status != 'active' THEN NULL ELSE request_sender_id END,
      request_message   = CASE WHEN status != 'active' THEN NULL ELSE request_message END,
      pending_activity_id = CASE WHEN status != 'active' THEN NULL ELSE pending_activity_id END,
      request_expires_at = NULL,
      last_message_at = now()
  WHERE id = v_conversation_id;
  -- Ré-afficher le fil chez les deux parties (un fil masqué doit resurgir
  -- avec la confirmation).
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (
    v_conversation_id, v_user_id,
    '📆 Réservation confirmée — « ' || coalesce(v_off_title, 'Sortie') || ' », le '
      || to_char(v_bk.day, 'DD/MM') || ' ' || v_period_label
      || ' (' || v_bk.party_size || ' pers.). Paiement sur place.',
    jsonb_build_object('type', 'booking_accepted', 'booking_id', v_bk.id,
                       'offering_id', v_bk.offering_id)
  );
  UPDATE conversations SET last_message_at = now() WHERE id = v_conversation_id;

  PERFORM create_notification(
    v_bk.client_id,
    'booking_accepted',
    'Réservation confirmée !',
    coalesce(v_pro_name, 'Le professionnel') || ' a confirmé « '
      || coalesce(v_off_title, 'ta sortie') || ' » — le ' || to_char(v_bk.day, 'DD/MM')
      || ' ' || v_period_label || '. Paiement sur place.',
    jsonb_build_object('booking_id', v_bk.id, 'conversation_id', v_conversation_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION accept_booking(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION accept_booking(UUID) TO authenticated;

-- ---------- H4 : pinning d'hôte des images pro ----------
-- Préfixe unique : bucket pro-photos, dossier du caller (pattern 00408).

CREATE OR REPLACE FUNCTION private.pro_photo_url_ok(p_url TEXT, p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_url IS NOT NULL
     AND char_length(p_url) BETWEEN 1 AND 500
     AND p_url LIKE 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/' || p_uid::text || '/%';
$$;
REVOKE EXECUTE ON FUNCTION private.pro_photo_url_ok(TEXT, UUID) FROM PUBLIC, anon, authenticated;

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
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_pro_photo:' || v_user_id::text));
  SELECT count(*) INTO v_count FROM pro_profile_photos WHERE pro_id = v_user_id;
  IF v_count >= 25 THEN RAISE EXCEPTION 'junto.photo_cap'; END IF;
  SELECT COALESCE(MAX(order_index), -1) + 1 INTO v_next_index
  FROM pro_profile_photos WHERE pro_id = v_user_id;
  INSERT INTO pro_profile_photos (pro_id, photo_url, order_index)
  VALUES (v_user_id, p_photo_url, v_next_index)
  RETURNING id INTO v_photo_id;
  RETURN v_photo_id;
END;
$$;

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
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_pro_offering_photo:' || p_offering_id::text));
  SELECT count(*) INTO v_count FROM pro_offering_photos WHERE offering_id = p_offering_id;
  IF v_count >= 25 THEN RAISE EXCEPTION 'junto.photo_cap'; END IF;
  SELECT COALESCE(MAX(order_index), -1) + 1 INTO v_next_index
  FROM pro_offering_photos WHERE offering_id = p_offering_id;
  INSERT INTO pro_offering_photos (offering_id, photo_url, order_index)
  VALUES (p_offering_id, p_photo_url, v_next_index)
  RETURNING id INTO v_photo_id;
  RETURN v_photo_id;
END;
$$;

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
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profile_photos SET photo_url = p_photo_url WHERE id = p_photo_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;

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
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_offering_photos SET photo_url = p_photo_url WHERE id = p_photo_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;

CREATE OR REPLACE FUNCTION set_pro_pin_image(p_pin_image_url TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- NULL efface ; sinon URL ancrée au dossier du caller (00418 H4 — le pin
  -- fan-out vers la carte de TOUS les utilisateurs).
  IF p_pin_image_url IS NOT NULL AND NOT private.pro_photo_url_ok(p_pin_image_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_image_url = p_pin_image_url WHERE user_id = v_user_id;
END;
$$;

-- set_pro_banner : code mort (banner_url droppée en 00254) — suppression.
DROP FUNCTION IF EXISTS set_pro_banner(TEXT);

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
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND status = 'approved'
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

-- ---------- H3 : privilèges colonnes sur pro_profiles ----------
REVOKE SELECT ON pro_profiles FROM authenticated, anon, PUBLIC;
GRANT SELECT (
  user_id, display_name, company_name, tagline, description,
  website, email, phone, instagram, facebook,
  primary_lng, primary_lat, primary_location_name,
  pin_image_url, pin_icon, status, is_demo,
  last_location_change_at, created_at, updated_at,
  -- ⚠️ TEMPORAIRE (00418) : real_name + rejection_reason restent grantées
  -- car le build PRODUCTION (OTA « Brique 4a ») les sélectionne encore dans
  -- getById — les révoquer maintenant casserait la fiche pro des testeurs
  -- réels. À retirer dès que production embarque le client corrigé :
  --   REVOKE SELECT ON pro_profiles FROM authenticated, anon, PUBLIC;
  --   GRANT SELECT (…liste ci-dessus SANS ces deux colonnes…) ON pro_profiles TO authenticated;
  real_name, rejection_reason
) ON pro_profiles TO authenticated;
-- reviewed_at, reviewed_by, primary_location : révoquées dès maintenant
-- (aucun client ne les sélectionne). Propriétaire et admin passent par RPC.

CREATE OR REPLACE FUNCTION get_my_pro_application()
RETURNS TABLE (
  user_id UUID, display_name TEXT, company_name TEXT, real_name TEXT,
  tagline TEXT, description TEXT, website TEXT, email TEXT, phone TEXT,
  instagram TEXT, facebook TEXT,
  primary_lng DOUBLE PRECISION, primary_lat DOUBLE PRECISION,
  primary_location_name TEXT, pin_image_url TEXT, pin_icon TEXT,
  status TEXT, rejection_reason TEXT,
  last_location_change_at TIMESTAMPTZ, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
         pp.last_location_change_at, pp.created_at, pp.updated_at
  FROM pro_profiles pp
  WHERE pp.user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION get_my_pro_application() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_pro_application() TO authenticated;

CREATE OR REPLACE FUNCTION admin_get_pending_pro_applications()
RETURNS TABLE (
  user_id UUID, display_name TEXT, company_name TEXT, real_name TEXT,
  email TEXT, phone TEXT, website TEXT, primary_location_name TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.email, pp.phone, pp.website, pp.primary_location_name, pp.created_at
  FROM pro_profiles pp
  WHERE pp.status = 'pending'
  ORDER BY pp.created_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION admin_get_pending_pro_applications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_get_pending_pro_applications() TO authenticated;
