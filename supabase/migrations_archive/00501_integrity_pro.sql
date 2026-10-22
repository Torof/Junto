-- ============================================================================
-- 00501 — Phase intégrité, lot pro.
-- PO-8  URL de photo pro : pas de remontée « .. » (même encodée) hors de son dossier.
-- PO-4  Une personne bloquée par le pro ne publie ni avis (pro / offre), ni
--       photo communautaire sur sa page, ni ne réécrit un ancien avis.
-- PO-5  Une réservation garde le prix demandé (colonnes ajoutées, reprise).
-- PO-6  Compte suspendu : get_my_bookings vide.
-- PO-11 Avis réécrit après la réponse du pro : le pro est prévenu (1 fois / jour).
-- PO-1 / PO-2  Pas de notification répétée (publier / supprimer, effacer /
--       réécrire une réponse).
-- B8    Offres d'un pro non approuvé masquées aux autres (policy + vue).
-- ============================================================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS price_eur NUMERIC;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS price_unit TEXT;
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE bookings b SET price_eur = o.price_eur, price_unit = o.price_unit::text
FROM pro_offerings o WHERE o.id = b.offering_id AND b.price_eur IS NULL;
SELECT set_config('junto.bypass_lock', 'false', true);

CREATE OR REPLACE FUNCTION private.pro_photo_url_ok(p_url text, p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT p_url IS NOT NULL
     AND char_length(p_url) BETWEEN 1 AND 500
     AND p_url LIKE 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/' || p_uid::text || '/%'
     -- 00501 (PO-8): no path climbing out of the own folder (« .. », encoded or not).
     AND p_url !~* '(\.\.|%2e|%2f|%5c|\\)';
$function$;

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

  SELECT pro_id, title, is_demo INTO v_pro_id, v_offering_title, v_is_demo FROM pro_offerings WHERE id = p_offering_id;
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

CREATE OR REPLACE FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid DEFAULT NULL::uuid, p_offering_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.update_pro_review(p_review_id uuid, p_rating smallint, p_body text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_pro UUID;
  v_replied BOOLEAN;
  v_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
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

  SELECT r.pro_id, r.pro_reply IS NOT NULL, (SELECT display_name FROM pro_profiles WHERE user_id = r.pro_id) INTO v_pro, v_replied, v_label
  FROM pro_reviews r WHERE r.id = p_review_id;
  -- 00501 (PO-4): not while blocked by the pro.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE pro_reviews SET rating = p_rating, body = v_body WHERE id = p_review_id;

  -- 00501 (PO-11): a review rewritten after the pro answered — the pro is told
  -- (their reply may no longer match). At most once a day per review.
  IF v_replied THEN
    PERFORM notify_review_received(v_pro, (SELECT display_name FROM users WHERE id = v_user_id), p_rating, v_label,
      jsonb_build_object('review_id', p_review_id, 'reviewer_id', v_user_id, 'variant', 'updated'));
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_offering_review(p_review_id uuid, p_rating smallint, p_body text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_pro UUID;
  v_replied BOOLEAN;
  v_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM offering_reviews WHERE id = p_review_id AND reviewer_id = v_user_id
  ) THEN
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

  SELECT (SELECT o.pro_id FROM pro_offerings o WHERE o.id = r.offering_id), r.pro_reply IS NOT NULL, (SELECT o.title FROM pro_offerings o WHERE o.id = r.offering_id) INTO v_pro, v_replied, v_label
  FROM offering_reviews r WHERE r.id = p_review_id;
  -- 00501 (PO-4): not while blocked by the pro.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE offering_reviews SET rating = p_rating, body = v_body WHERE id = p_review_id;

  -- 00501 (PO-11): a review rewritten after the pro answered — the pro is told
  -- (their reply may no longer match). At most once a day per review.
  IF v_replied THEN
    PERFORM notify_review_received(v_pro, (SELECT display_name FROM users WHERE id = v_user_id), p_rating, v_label,
      jsonb_build_object('review_id', p_review_id, 'reviewer_id', v_user_id, 'variant', 'updated'));
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_review_received(p_pro_id uuid, p_reviewer_name text, p_rating smallint, p_target_label text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  -- 00501 (PO-1 / PO-11): no repeat — one « new review » per reviewer and
  -- pro a day (publish / delete loops), one « review updated » per review a day.
  IF p_data ? 'reviewer_id' AND EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.user_id = p_pro_id AND n.type = 'review_received'
      AND n.data->>'reviewer_id' = p_data->>'reviewer_id'
      AND coalesce(n.data->>'variant', '') = coalesce(p_data->>'variant', '')
      AND (p_data->>'variant' IS NULL OR n.data->>'review_id' = p_data->>'review_id')
      AND n.created_at > now() - INTERVAL '24 hours'
  ) THEN RETURN; END IF;

  v_clean_name := sanitize_notif_text(coalesce(p_reviewer_name, 'Quelqu''un'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_pro_id,
    'review_received',
    'Nouvel avis',
    v_clean_name || ' a laissé un avis (' || p_rating || '★) sur ' || v_clean_label,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'rating', p_rating, 'label', v_clean_label))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_review_reply(p_reviewer_id uuid, p_pro_name text, p_target_label text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clean_name TEXT;
  v_clean_label TEXT;
BEGIN
  -- 00501 (PO-2): one « reply » notification per review (erase / rewrite
  -- loops do not ping the author again).
  IF EXISTS (SELECT 1 FROM notifications n
             WHERE n.user_id = p_reviewer_id AND n.type = 'review_reply'
               AND n.data->>'review_id' = p_data->>'review_id') THEN
    RETURN;
  END IF;

  v_clean_name := sanitize_notif_text(coalesce(p_pro_name, 'Le pro'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_reviewer_id,
    'review_reply',
    'Réponse à ton avis',
    v_clean_name || ' a répondu à ton avis sur ' || v_clean_label,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'label', v_clean_label))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_bookings()
 RETURNS TABLE(id uuid, offering_id uuid, offering_title text, pro_id uuid, pro_name text, day date, period text, party_size integer, status text, conversation_id uuid, created_at timestamp with time zone, location_name text, price_eur numeric, price_unit text, sport_key text, sport_category text, equipment_required jsonb, participant_fields jsonb, participant_info jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  -- 00501 (PO-6): a suspended account reads nothing (like the table).
  IF private.user_is_suspended(v_user_id) THEN RETURN; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'expired'
  WHERE bookings.client_id = v_user_id AND bookings.status = 'pending' AND bookings.day < current_date;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT b.id, b.offering_id, po.title, b.pro_id, pp.display_name,
         b.day, b.period, b.party_size, b.status,
         (SELECT c.id FROM conversations c
          WHERE c.type = 'dm' AND c.status = 'active'
            AND c.user_1 = LEAST(v_user_id, b.pro_id)
            AND c.user_2 = GREATEST(v_user_id, b.pro_id)),
         b.created_at,
         po.location_name, coalesce(b.price_eur, po.price_eur), coalesce(b.price_unit, po.price_unit::TEXT),  -- 00501 (PO-5)
         s.key::TEXT, s.category::TEXT,
         po.equipment_required, po.participant_fields, b.participant_info
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.pro_id
  WHERE b.client_id = v_user_id
  ORDER BY b.day DESC, b.created_at DESC;
END;
$function$;

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

CREATE OR REPLACE VIEW public.pro_offerings_with_coords AS
SELECT o.id,
    o.pro_id,
    o.sport_id,
    o.title,
    o.description,
    o.level,
    o.location_name,
    o.duration,
    o.max_participants,
    o.schedule_text,
    o.distance_km,
    o.elevation_gain_m,
    ( SELECT p.photo_url
           FROM pro_offering_photos p
          WHERE (p.offering_id = o.id)
          ORDER BY p.order_index
         LIMIT 1) AS image_url,
    o.created_at,
    o.updated_at,
    st_x((o.location)::geometry) AS lng,
    st_y((o.location)::geometry) AS lat,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    pp.display_name AS pro_name,
    o.price_eur,
    o.price_unit,
    o.min_participants,
    o.equipment_provided,
    o.equipment_required,
    o.participant_fields
   FROM ((pro_offerings o
     JOIN sports s ON ((o.sport_id = s.id)))
     JOIN pro_profiles pp ON ((o.pro_id = pp.user_id)))
  WHERE ((NOT (EXISTS ( SELECT 1
           FROM users u
          WHERE ((u.id = o.pro_id) AND (u.suspended_at IS NOT NULL))))) AND ((o.is_demo = false) OR demo_content_visible())
    -- 00501 (B8): only an approved pro's offerings (or one's own).
    AND (pp.status = 'approved' OR o.pro_id = auth.uid()));

DROP POLICY IF EXISTS pro_offerings_select ON pro_offerings;
CREATE POLICY pro_offerings_select ON pro_offerings FOR SELECT TO authenticated
  USING ((NOT private.user_is_suspended(pro_id)) AND ((is_demo = false) OR demo_content_visible())
         AND (pro_id = auth.uid()
              OR EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = pro_offerings.pro_id AND pp.status = 'approved')));
