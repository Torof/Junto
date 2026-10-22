-- ============================================================================
-- 00505 — Contre-vérification de 00501-00502.
-- PO-5  Une réservation re-soumise reprend le prix du moment.
-- PO-1  Le dédoublonnage des avis distingue la page du pro et chaque offre ;
--       « avis modifié » a son propre texte et ouvre la page concernée.
-- B8    Avis et favoris seulement sur un pro approuvé ; vues d'avis d'offres
--       limitées aux pros approuvés.
-- Hygiène : contrôles sur les prix des réservations ; plus de MAINTAIN
--       (verrou, VACUUM) pour les clients ; vues sans TRIGGER / REFERENCES.
-- ============================================================================

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
      -- 00505: per target — a review of the pro page and one of an offering
      -- are two different notifications.
      AND coalesce(n.data->>'offering_id', '') = coalesce(p_data->>'offering_id', '')
      AND n.created_at > now() - INTERVAL '24 hours'
  ) THEN RETURN; END IF;

  v_clean_name := sanitize_notif_text(coalesce(p_reviewer_name, 'Quelqu''un'));
  v_clean_label := sanitize_notif_text(coalesce(p_target_label, ''));
  PERFORM create_notification(
    p_pro_id,
    'review_received',
    CASE WHEN p_data->>'variant' = 'updated' THEN 'Avis modifié' ELSE 'Nouvel avis' END,
    CASE WHEN p_data->>'variant' = 'updated'
      THEN v_clean_name || ' a modifié son avis (' || p_rating || '★) sur ' || v_clean_label
      ELSE v_clean_name || ' a laissé un avis (' || p_rating || '★) sur ' || v_clean_label END,
    coalesce(p_data, '{}'::jsonb) || jsonb_build_object('params', jsonb_build_object('name', v_clean_name, 'rating', p_rating, 'label', v_clean_label))
  );
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
      jsonb_build_object('review_id', p_review_id, 'reviewer_id', v_user_id, 'variant', 'updated', 'pro_id', v_pro));  -- 00505: tappable
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
      jsonb_build_object('review_id', p_review_id, 'reviewer_id', v_user_id, 'variant', 'updated',
        'offering_id', (SELECT r.offering_id FROM offering_reviews r WHERE r.id = p_review_id)));  -- 00505: tappable
  END IF;
END;
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
  -- 00505 (B8): only an approved pro can be reviewed (same generic error).
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND is_demo = false AND status = 'approved') THEN
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

CREATE OR REPLACE FUNCTION public.add_favorite(p_kind text, p_id uuid)
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
  IF p_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Cap only NEW favorites — re-favoriting an existing target stays an
  -- idempotent no-op even at the boundary.
  IF (SELECT count(*) FROM favorites WHERE owner_id = v_user_id) >= 500
     AND NOT EXISTS (
       SELECT 1 FROM favorites
       WHERE owner_id = v_user_id
         AND ( (p_kind = 'activity' AND activity_id = p_id)
            OR (p_kind = 'offering' AND offering_id = p_id)
            OR (p_kind = 'pro'      AND pro_id = p_id) )
     ) THEN
    RAISE EXCEPTION 'junto.favorite_cap';
  END IF;

  IF p_kind = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = p_id
        AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
        AND (a.is_demo = false OR demo_content_visible())
        AND (
          a.visibility IN ('public', 'approval')
          OR (
            a.visibility IN ('private_link', 'private_link_approval')
            AND (
              a.creator_id = v_user_id
              OR EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted')
            )
          )
        )
        AND NOT EXISTS (SELECT 1 FROM users cu WHERE cu.id = a.creator_id AND cu.suspended_at IS NOT NULL)
        AND a.creator_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, activity_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'offering' THEN
    -- Mirror pro_offerings_with_coords: gate on suspension + demo only (NOT the
    -- parent pro's approved status — the view shows the offering regardless).
    IF NOT EXISTS (
      SELECT 1 FROM pro_offerings o
      JOIN users u ON u.id = o.pro_id
      WHERE o.id = p_id AND u.suspended_at IS NULL
        AND (o.is_demo = false OR demo_content_visible())
        -- 00505 (B8): the view now hides unapproved pros' offerings too.
        AND EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = o.pro_id AND pp.status = 'approved')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, offering_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'pro' THEN
    IF NOT EXISTS (
      SELECT 1 FROM pro_profiles p
      JOIN users u ON u.id = p.user_id
      WHERE p.user_id = p_id AND p.status = 'approved' AND u.suspended_at IS NULL
        AND (p.is_demo = false OR demo_content_visible())
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, pro_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$function$;

CREATE OR REPLACE VIEW public.offering_review_stats AS
SELECT r.offering_id,
    (count(*))::integer AS review_count,
    (avg(r.rating))::numeric(3,2) AS avg_rating
   FROM (offering_reviews r
     JOIN pro_offerings o ON ((o.id = r.offering_id)))
  WHERE ((NOT private.user_is_suspended(r.reviewer_id)) AND (NOT private.user_is_suspended(o.pro_id)) AND ((o.is_demo = false) OR demo_content_visible()) AND (EXISTS ( SELECT 1 FROM pro_profiles pp_appr WHERE pp_appr.user_id = o.pro_id AND pp_appr.status = 'approved')))
  GROUP BY r.offering_id;

CREATE OR REPLACE VIEW public.offering_reviews_with_profiles AS
SELECT r.id,
    r.offering_id,
    r.reviewer_id,
    r.rating,
    r.body,
    r.pro_reply,
    r.pro_reply_at,
    r.created_at,
    r.updated_at,
    pp.display_name AS reviewer_name,
    pp.avatar_url AS reviewer_avatar
   FROM ((offering_reviews r
     JOIN public_profiles pp ON ((pp.id = r.reviewer_id)))
     JOIN pro_offerings o ON ((o.id = r.offering_id)))
  WHERE ((NOT private.user_is_suspended(r.reviewer_id)) AND (NOT private.user_is_suspended(o.pro_id)) AND ((o.is_demo = false) OR demo_content_visible()) AND (EXISTS ( SELECT 1 FROM pro_profiles pp_appr WHERE pp_appr.user_id = o.pro_id AND pp_appr.status = 'approved')));

ALTER TABLE bookings ADD CONSTRAINT bookings_price_eur_check CHECK (price_eur IS NULL OR price_eur >= 0);
ALTER TABLE bookings ADD CONSTRAINT bookings_price_unit_check CHECK (price_unit IS NULL OR price_unit IN ('person', 'group'));

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE MAINTAIN ON TABLES FROM anon, authenticated;
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT c.oid::regclass AS t, c.relkind FROM pg_class c
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p', 'v', 'm')
  LOOP
    BEGIN
      EXECUTE format('REVOKE MAINTAIN, TRUNCATE, TRIGGER, REFERENCES ON %s FROM anon, authenticated', r.t);
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END $$;
