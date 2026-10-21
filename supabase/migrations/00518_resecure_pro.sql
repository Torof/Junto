-- ============================================================================
-- 00518 — Re-sécurisation, lot pro (audit neuf).
-- M1  L16 + raison sociale : nom civil, raison sociale et motif de refus ne
--     sont plus lisibles en direct par les autres comptes (« non publique »
--     dans le formulaire). Le pro les lit par get_my_pro_application, l'admin
--     par admin_get_pending_pro_applications. Plus de testeurs : la version de
--     production n'a pas à être attendue.
-- L1  Liens web : site en http(s) au niveau de la table (inscription comprise),
--     Facebook / Instagram jamais en schéma exotique.
-- L2  Photo communautaire d'un contributeur suspendu masquée.
-- L3  Offres : niveau borné, durée entre 15 min et 30 jours.
-- L4  Verrous : pas de réservation créée pendant la suppression d'une offre.
-- L5  Purge à J+30 du téléphone saisi par le pro et du message du client.
-- ============================================================================

REVOKE SELECT (real_name, company_name, rejection_reason) ON pro_profiles FROM anon, authenticated;

ALTER TABLE pro_profiles ADD CONSTRAINT pro_profiles_website_http CHECK (website IS NULL OR website ~* '^https?://[^[:space:]]+$');
ALTER TABLE pro_profiles ADD CONSTRAINT pro_profiles_social_no_scheme CHECK (
  (facebook IS NULL OR facebook !~* '^[a-z][a-z0-9+.-]*:' OR facebook ~* '^https?://')
  AND (instagram IS NULL OR instagram !~* '^[a-z][a-z0-9+.-]*:' OR instagram ~* '^https?://'));

ALTER TABLE pro_offerings ADD CONSTRAINT pro_offerings_level_len CHECK (char_length(level) <= 60);
ALTER TABLE pro_offerings ADD CONSTRAINT pro_offerings_duration_range CHECK (duration IS NULL OR duration BETWEEN INTERVAL '15 minutes' AND INTERVAL '30 days');

ALTER POLICY pro_community_photos_public_read ON pro_community_photos
  USING ((((NOT private.user_is_suspended(pro_id)) AND (demo_content_visible() OR (EXISTS ( SELECT 1
   FROM pro_profiles dp
  WHERE ((dp.user_id = pro_community_photos.pro_id) AND (dp.is_demo = false))))))) AND NOT private.user_is_suspended(contributor_id));

CREATE OR REPLACE FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    AND u.tier = 'pro'
  -- 00518 (L4): the offering cannot be deleted while this booking is created.
  FOR SHARE OF po;
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

  IF v_existing.id IS NOT NULL THEN  -- 00477: a RECORD with any NULL field is never « IS NOT NULL »
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
        -- 00505: a re-submitted request takes the current price.
        price_eur = (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
        price_unit = (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id),
        submitted_count = v_existing.submitted_count + 1,
        last_submitted_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      -- 00501 (PO-5): the price the client asked at is kept with the booking.
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message, price_eur, price_unit)
      VALUES (p_offering_id, v_off.pro_id, v_user_id, p_day, p_period, p_party_size, v_msg,
              (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
              (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id))
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
    coalesce(v_client_name, 'Un membre') || ' · « ' || v_off.title || ' » · '
      || to_char(p_day, 'DD/MM') || ', ' || v_period_label
      || ' · ' || p_party_size || ' pers.',
    jsonb_build_object('booking_id', v_booking_id, 'offering_id', p_offering_id,
      'params', jsonb_build_object('name', coalesce(v_client_name, 'Un membre'), 'title', v_off.title,
                                   'date', to_char(p_day, 'YYYY-MM-DD'), 'period', p_period, 'count', p_party_size))
  );

  RETURN v_booking_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_pro_offering(p_offering_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 00518 (L4): lock the offering first — no booking can slip in between the
  -- check below and the delete.
  PERFORM 1 FROM pro_offerings WHERE id = p_offering_id FOR UPDATE;

  -- 00416 : refuser tant que des réservations futures vivantes existent.
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE offering_id = p_offering_id
      AND status IN ('pending', 'accepted')
      AND day >= current_date
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  DELETE FROM pro_offerings WHERE id = p_offering_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.unregister_as_pro()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 00518 (L4): lock all of this pro's offerings before the check.
  PERFORM 1 FROM pro_offerings WHERE pro_id = v_user_id FOR UPDATE;

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
$function$;

CREATE OR REPLACE FUNCTION public.purge_booking_participant_info()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = NULL
  WHERE participant_info IS NOT NULL AND day < current_date - 30;
  -- 00518 (L5): third-party contact typed by the pro, and the client's free
  -- text, are not kept forever either.
  UPDATE bookings SET manual_phone = NULL, message = NULL
  WHERE (manual_phone IS NOT NULL OR message IS NOT NULL) AND day < current_date - 30;
END;
$function$;
