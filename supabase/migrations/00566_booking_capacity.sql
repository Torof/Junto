-- Capacity becomes a rule (Scott 2026-11-01): clients may still all send
-- requests, the pro picks — but an accept that would overflow the outing's
-- places is refused (junto.booking_full), and so is a new request that no
-- longer fits in the places left after the ACCEPTED groups. Manual bookings
-- stay free (the pro's own agenda) but count in the total.
-- get_pro_agenda also returns the client's photo and the outing's max places
-- (agenda shows 5/6 and groups clients by outing).

CREATE OR REPLACE FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
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

  IF p_day IS NULL OR p_day < private.today_paris() OR p_day > private.today_paris() + INTERVAL '6 months' THEN
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

  -- 00566: a request must fit in the places still free. Only ACCEPTED groups
  -- count (all offerings of the half-day: one pro = one outing per half-day,
  -- same count as get_pro_availability.taken) — pending requests never block,
  -- the pro picks among them.
  IF v_off.max_participants IS NOT NULL
     AND p_party_size > v_off.max_participants - coalesce((
       SELECT sum(b.party_size) FROM bookings b
       WHERE b.pro_id = v_off.pro_id AND b.day = p_day AND b.period = p_period
         AND b.status = 'accepted'), 0) THEN
    RAISE EXCEPTION 'junto.booking_full';
  END IF;

  v_msg := nullif(regexp_replace(trim(coalesce(p_message, '')), '<[^>]*>', '', 'g'), '');
  IF v_msg IS NOT NULL AND char_length(v_msg) > 500 THEN
    RAISE EXCEPTION 'junto.booking_message';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND status = 'pending'
        AND day >= private.today_paris()) >= 5 THEN  -- 00523: past days never block
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
$$;

CREATE OR REPLACE FUNCTION public.accept_booking(p_booking_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
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
  v_max INTEGER;
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
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
       OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00566: no overbooking on accept. The slot lock serialises two accepts on
  -- the same half-day so they cannot both pass the count.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || v_bk.day::text || v_bk.period || '_slot'));
  SELECT max_participants INTO v_max FROM pro_offerings WHERE id = v_bk.offering_id;
  IF v_max IS NOT NULL
     AND v_bk.party_size + coalesce((
       SELECT sum(b.party_size) FROM bookings b
       WHERE b.pro_id = v_user_id AND b.day = v_bk.day AND b.period = v_bk.period
         AND b.status = 'accepted'), 0) > v_max THEN
    RAISE EXCEPTION 'junto.booking_full';
  END IF;

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
      || coalesce(v_off_title, 'ta sortie') || ' » le ' || to_char(v_bk.day, 'DD/MM')
      || ', ' || v_period_label || '. Paiement sur place.',
    jsonb_build_object('booking_id', v_bk.id, 'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'ta sortie'),
                                   'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
  );

  RETURN v_conversation_id;
END;
$$;

DROP FUNCTION public.get_pro_agenda(date, date);

CREATE FUNCTION public.get_pro_agenda(p_from date, p_to date) RETURNS TABLE(kind text, id uuid, day date, period text, status text, offering_id uuid, offering_title text, party_size integer, client_id uuid, client_name text, manual_phone text, message text, is_manual boolean, sport_key text, sport_category text, participant_fields jsonb, participant_info jsonb, client_avatar_url text, max_participants integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
DECLARE
  v_user_id UUID;
  v_flip RECORD;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from
     OR p_to > p_from + INTERVAL '12 months' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Expiration paresseuse + notif client (00420 D3).
  PERFORM set_config('junto.bypass_lock', 'true', true);
  FOR v_flip IN
    WITH flipped AS (
      UPDATE bookings SET status = 'expired'
      WHERE bookings.pro_id = v_user_id AND bookings.status = 'pending'
        AND bookings.day < private.today_paris()
      RETURNING bookings.id AS b_id, bookings.client_id AS b_client,
                bookings.offering_id AS b_off, bookings.day AS b_day,
                bookings.period AS b_period
    )
    SELECT f.b_id, f.b_client, f.b_off, f.b_day, f.b_period, po.title AS b_title
    FROM flipped f
    LEFT JOIN pro_offerings po ON po.id = f.b_off
    WHERE f.b_client IS NOT NULL
  LOOP
    v_period_label := CASE v_flip.b_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;
    PERFORM create_notification(
      v_flip.b_client,
      'booking_expired',
      'Demande expirée',
      'Ta demande pour « ' || coalesce(v_flip.b_title, 'une sortie') || ' » du '
        || to_char(v_flip.b_day, 'DD/MM') || ', ' || v_period_label
        || ' a expiré sans réponse. Tu peux demander un autre créneau.',
      jsonb_build_object('booking_id', v_flip.b_id, 'offering_id', v_flip.b_off,
        'params', jsonb_build_object('title', coalesce(v_flip.b_title, 'une sortie'),
                                     'date', to_char(v_flip.b_day, 'YYYY-MM-DD'), 'period', v_flip.b_period))
    );
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT 'availability'::TEXT, a.id, a.day, a.period, NULL::TEXT,
         NULL::UUID, NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::TEXT, NULL::TEXT,
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT, NULL::JSONB, NULL::JSONB,
         NULL::TEXT, NULL::INTEGER
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL),
         s.key::TEXT, s.category::TEXT,
         po.participant_fields, b.participant_info,
         pp.avatar_url, po.max_participants
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id
    AND b.day BETWEEN p_from AND p_to
    AND b.status IN ('pending', 'accepted')
  ORDER BY 3, 4;
END;
$$;

REVOKE ALL ON FUNCTION public.get_pro_agenda(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pro_agenda(date, date) TO authenticated;
