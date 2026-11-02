-- 00575 follow-up: a client already signed up to a full date is told so
-- (not « complet »); plural fix in the stored French text of the D-2 reminder.

CREATE OR REPLACE FUNCTION public.join_pro_session(p_session_id uuid, p_party_size integer, p_message text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_s RECORD;
  v_msg TEXT;
  v_taken INTEGER;
  v_existing RECORD;
  v_booking_id UUID;
  v_client_name TEXT;
  v_pro_name TEXT;
  v_conversation_id UUID;
  v_when TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.*, po.title, po.price_eur AS o_price, po.price_unit::TEXT AS o_unit, pp.is_demo
    INTO v_s
  FROM pro_sessions s
  JOIN pro_offerings po ON po.id = s.offering_id
  JOIN pro_profiles pp ON pp.user_id = s.pro_id
  JOIN users u ON u.id = s.pro_id
  WHERE s.id = p_session_id
    AND pp.status = 'approved' AND u.tier = 'pro' AND u.suspended_at IS NULL
  FOR SHARE OF s;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_s.pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_s.is_demo = true AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_s.pro_id)
       OR (blocker_id = v_s.pro_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_s.status <> 'scheduled' OR private.session_started(v_s.start_day, v_s.start_period) THEN
    RAISE EXCEPTION 'junto.session_closed';
  END IF;
  IF p_party_size IS NULL OR p_party_size < 1 OR p_party_size > v_s.max_participants THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;
  v_msg := nullif(regexp_replace(trim(coalesce(p_message, '')), '<[^>]*>', '', 'g'), '');
  IF v_msg IS NOT NULL AND char_length(v_msg) > 500 THEN
    RAISE EXCEPTION 'junto.booking_message';
  END IF;

  -- Same per-client caps as create_booking.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND created_at > now() - INTERVAL '24 hours') >= 10 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  -- Already signed up: say so before « complet ».
  IF EXISTS (SELECT 1 FROM bookings WHERE session_id = p_session_id AND client_id = v_user_id
             AND status IN ('pending', 'accepted')) THEN
    RAISE EXCEPTION 'junto.booking_already';
  END IF;

  -- Places: the date is locked while counting, two sign-ups cannot overflow.
  PERFORM pg_advisory_xact_lock(hashtext(p_session_id::text || '_session'));
  SELECT coalesce(sum(party_size), 0)::INTEGER INTO v_taken
  FROM bookings WHERE session_id = p_session_id AND status = 'accepted';
  IF p_party_size > v_s.max_participants - v_taken THEN
    RAISE EXCEPTION 'junto.booking_full';
  END IF;

  -- One row per (offering, client, start half-day): a cancelled sign-up (or an
  -- old request on that half-day) is reactivated, with the anti-spam rules of
  -- create_booking.
  SELECT * INTO v_existing FROM bookings
  WHERE offering_id = v_s.offering_id AND client_id = v_user_id
    AND day = v_s.start_day AND period = v_s.start_period
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.status IN ('pending', 'accepted') THEN RAISE EXCEPTION 'junto.booking_already'; END IF;
    IF v_existing.last_submitted_at > now() - INTERVAL '1 hour' OR v_existing.submitted_count >= 5 THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'accepted', session_id = p_session_id, party_size = p_party_size, message = v_msg,
        created_at = now(), price_eur = v_s.o_price, price_unit = v_s.o_unit,
        submitted_count = v_existing.submitted_count + 1, last_submitted_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message,
                            status, session_id, price_eur, price_unit)
      VALUES (v_s.offering_id, v_s.pro_id, v_user_id, v_s.start_day, v_s.start_period, p_party_size, v_msg,
              'accepted', p_session_id, v_s.o_price, v_s.o_unit)
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  -- The logistic DM with the pro, opened like an accepted booking.
  v_when := CASE WHEN v_s.end_day > v_s.start_day
                 THEN 'du ' || to_char(v_s.start_day, 'DD/MM') || ' au ' || to_char(v_s.end_day, 'DD/MM')
                 ELSE 'le ' || to_char(v_s.start_day, 'DD/MM') || ' '
                      || CASE WHEN v_s.start_period <> v_s.end_period THEN 'journée'
                              WHEN v_s.start_period = 'am' THEN 'matin' ELSE 'après-midi' END
            END;
  v_conversation_id := private.booking_dm(v_s.pro_id, v_user_id);
  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (
    v_conversation_id, v_s.pro_id,
    '📆 Inscription confirmée — « ' || coalesce(v_s.title, 'Sortie') || ' », ' || v_when
      || ' (' || p_party_size || ' pers.). Paiement sur place.',
    jsonb_build_object('type', 'booking_accepted', 'booking_id', v_booking_id, 'offering_id', v_s.offering_id)
  );
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations SET last_message_at = now() WHERE id = v_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_s.pro_id,
    'session_joined',
    'Nouvelle inscription',
    coalesce(v_client_name, 'Un membre') || ' · « ' || coalesce(v_s.title, 'ta sortie') || ' » · '
      || to_char(v_s.start_day, 'DD/MM') || ' · ' || p_party_size || ' pers.',
    jsonb_build_object('booking_id', v_booking_id, 'session_id', p_session_id,
      'params', jsonb_build_object('name', coalesce(v_client_name, 'Un membre'), 'title', coalesce(v_s.title, ''),
                                   'date', to_char(v_s.start_day, 'YYYY-MM-DD'), 'count', p_party_size))
  );

  RETURN v_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.notify_booking_forms_missing()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row RECORD;
  v_min_low BOOLEAN;
  v_body TEXT;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN; END IF;

  FOR v_row IN
    WITH outings AS (
      SELECT b.pro_id, b.offering_id, b.day, b.period,
             sum(CASE WHEN coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
                         + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
                      THEN greatest(b.party_size - coalesce(jsonb_array_length(b.participant_info), 0), 0)
                      ELSE 0 END)::INTEGER AS missing,
             sum(b.party_size)::INTEGER AS total
      FROM bookings b
      JOIN pro_offerings po ON po.id = b.offering_id
      WHERE b.status = 'accepted' AND b.day = private.today_paris() + 2
      GROUP BY b.pro_id, b.offering_id, b.day, b.period
    ), sess AS (
      SELECT s.pro_id, s.offering_id, s.start_day AS day, s.start_period AS period, s.min_participants
      FROM pro_sessions s
      WHERE s.status = 'scheduled' AND s.start_day = private.today_paris() + 2
        AND s.min_participants IS NOT NULL
    )
    SELECT coalesce(o.pro_id, s.pro_id) AS pro_id, coalesce(o.offering_id, s.offering_id) AS offering_id,
           coalesce(o.day, s.day) AS day, coalesce(o.period, s.period) AS period,
           coalesce(o.missing, 0) AS missing, coalesce(o.total, 0) AS total,
           s.min_participants AS min, po.title
    FROM outings o
    FULL JOIN sess s ON s.pro_id = o.pro_id AND s.offering_id = o.offering_id
                    AND s.day = o.day AND s.period = o.period
    JOIN pro_offerings po ON po.id = coalesce(o.offering_id, s.offering_id)
    WHERE coalesce(o.missing, 0) > 0
       OR (s.min_participants IS NOT NULL AND coalesce(o.total, 0) < s.min_participants)
  LOOP
    v_min_low := v_row.min IS NOT NULL AND v_row.total < v_row.min;
    v_body := '« ' || coalesce(v_row.title, 'Ta sortie') || ' » (' || to_char(v_row.day, 'DD/MM') || ') : ';
    IF v_row.missing > 0 THEN
      v_body := v_body || v_row.missing || ' fiche' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' participant' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' manquante' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' sur ' || v_row.total;
      IF v_min_low THEN v_body := v_body || ', et '; END IF;
    END IF;
    IF v_min_low THEN
      v_body := v_body || v_row.total || ' pers. inscrite' || CASE WHEN v_row.total > 1 THEN 's' ELSE '' END
        || ', minimum ' || v_row.min || ' pour partir';
    END IF;
    PERFORM create_notification(
      v_row.pro_id,
      'booking_forms_missing',
      CASE WHEN v_row.missing > 0 THEN 'Il manque des infos' ELSE 'Minimum pas atteint' END,
      v_body || '.',
      jsonb_build_object('offering_id', v_row.offering_id,
        'variant', CASE WHEN v_min_low AND v_row.missing > 0 THEN 'both'
                        WHEN v_min_low THEN 'minimum' ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_row.title, ''), 'date', to_char(v_row.day, 'YYYY-MM-DD'),
                                     'period', v_row.period, 'count', v_row.missing, 'total', v_row.total,
                                     'min', v_row.min))
    );
  END LOOP;
END;
$$;
