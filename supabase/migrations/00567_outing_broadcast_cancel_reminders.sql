-- Pro tools for one outing session (Scott 2026-11-01, chains validated):
--   1. message_outing_clients — the same message to every confirmed client of
--      a session (« RDV 8 h au parking »), each in their own private thread.
--   2. cancel_outing — cancel a whole session at once (weather), with an
--      optional reason that goes to each client's thread, never into a push.
--   3. Reminders (cron, internal): the client the evening before, the pro
--      when requests have been waiting for more than 24 h.

-- ---------------------------------------------------------------------------
-- Internal: the pro ↔ client logistic DM, found or created — same handling as
-- accept_booking / open_booking_conversation (00418 H2): a reactivated row is
-- RETAGGED 'booking' and its social-request fields purged. The caller has
-- already checked ownership, suspension and blocks.
CREATE OR REPLACE FUNCTION private.booking_dm(p_pro uuid, p_client uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  IF p_client < p_pro THEN v_u1 := p_client; v_u2 := p_pro;
  ELSE v_u1 := p_pro; v_u2 := p_client; END IF;

  SELECT id INTO v_conversation_id FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES ('dm', v_u1, v_u2, p_pro, 'active', 'booking', now(), now())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations
  SET status = 'active',
      initiated_from = CASE WHEN status != 'active' THEN 'booking' ELSE initiated_from END,
      request_sender_id = CASE WHEN status != 'active' THEN NULL ELSE request_sender_id END,
      request_message   = CASE WHEN status != 'active' THEN NULL ELSE request_message END,
      pending_activity_id = CASE WHEN status != 'active' THEN NULL ELSE pending_activity_id END,
      request_expires_at = CASE WHEN status != 'active' THEN NULL ELSE request_expires_at END
  WHERE id = v_conversation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN v_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION private.booking_dm(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Internal: drop one message from the pro into a booking DM and surface the
-- thread on both sides (like send_message).
CREATE OR REPLACE FUNCTION private.post_booking_dm(p_conversation_id uuid, p_pro uuid, p_content text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO messages (conversation_id, sender_id, content)
  VALUES (p_conversation_id, p_pro, p_content);
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;

REVOKE ALL ON FUNCTION private.post_booking_dm(uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. « Écrire à tous »
CREATE OR REPLACE FUNCTION public.message_outing_clients(
  p_offering_id uuid, p_day date, p_period text, p_content text
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_content TEXT;
  v_client UUID;
  v_conversation_id UUID;
  v_sent INTEGER := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') OR p_day IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_content := trim(regexp_replace(coalesce(p_content, ''), '<[^>]*>', '', 'g'));
  IF char_length(v_content) < 1 OR char_length(v_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.rate_hit('outing_broadcast', 20, INTERVAL '1 day');

  -- Confirmed in-app clients of the session only: a pending request does not
  -- get the meeting point. Suspended or blocked (either way) are skipped.
  FOR v_client IN
    SELECT DISTINCT b.client_id FROM bookings b
    JOIN users u ON u.id = b.client_id
    WHERE b.pro_id = v_user_id AND b.offering_id = p_offering_id
      AND b.day = p_day AND b.period = p_period
      AND b.status = 'accepted' AND b.client_id IS NOT NULL
      AND u.suspended_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users bu
        WHERE (bu.blocker_id = v_user_id AND bu.blocked_id = b.client_id)
           OR (bu.blocker_id = b.client_id AND bu.blocked_id = v_user_id)
      )
  LOOP
    v_conversation_id := private.booking_dm(v_user_id, v_client);
    PERFORM private.post_booking_dm(v_conversation_id, v_user_id, v_content);
    v_sent := v_sent + 1;
  END LOOP;

  RETURN v_sent;
END;
$$;

REVOKE ALL ON FUNCTION public.message_outing_clients(uuid, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.message_outing_clients(uuid, date, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. « Annuler la sortie »
CREATE OR REPLACE FUNCTION public.cancel_outing(
  p_offering_id uuid, p_day date, p_period text, p_reason text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_title TEXT;
  v_pro_name TEXT;
  v_reason TEXT;
  v_bk RECORD;
  v_conversation_id UUID;
  v_done INTEGER := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') OR p_day IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT title INTO v_title FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  v_reason := nullif(trim(regexp_replace(coalesce(p_reason, ''), '<[^>]*>', '', 'g')), '');
  IF v_reason IS NOT NULL AND char_length(v_reason) > 300 THEN
    RAISE EXCEPTION 'junto.outing_reason';
  END IF;

  -- Same slot lock as accept_booking (00566): no accept slips in mid-cancel.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || p_day::text || p_period || '_slot'));
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;

  FOR v_bk IN
    SELECT id, client_id, status FROM bookings
    WHERE pro_id = v_user_id AND offering_id = p_offering_id
      AND day = p_day AND period = p_period
      AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = CASE WHEN v_bk.status = 'accepted' THEN 'cancelled_pro' ELSE 'declined' END
    WHERE id = v_bk.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_done := v_done + 1;

    -- Manual booking: no one in the app — the pro calls them.
    CONTINUE WHEN v_bk.client_id IS NULL;

    -- The reason is the pro's own words: it goes into the private thread,
    -- never into a notification (push content rule).
    v_conversation_id := NULL;
    IF v_reason IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL)
       AND NOT EXISTS (
         SELECT 1 FROM blocked_users
         WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
            OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
       ) THEN
      v_conversation_id := private.booking_dm(v_user_id, v_bk.client_id);
      PERFORM private.post_booking_dm(v_conversation_id, v_user_id, v_reason);
    END IF;

    IF v_bk.status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        coalesce(v_pro_name, 'Le professionnel') || ' a annulé « ' || coalesce(v_title, 'ta sortie')
          || ' » du ' || to_char(p_day, 'DD/MM') || '.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'pro',
          'variant', CASE WHEN v_conversation_id IS NOT NULL THEN 'by_pro_message' ELSE 'by_pro' END,
          'conversation_id', v_conversation_id,
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(v_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    ELSE
      PERFORM create_notification(
        v_bk.client_id,
        'booking_declined',
        'Créneau indisponible',
        coalesce(v_pro_name, 'Le professionnel') || ' n’est pas disponible pour « '
          || coalesce(v_title, 'ta sortie') || ' » le ' || to_char(p_day, 'DD/MM') || '.',
        jsonb_build_object('booking_id', v_bk.id, 'offering_id', p_offering_id,
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(v_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;

  RETURN v_done;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_outing(uuid, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_outing(uuid, date, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Reminders. pg_cron runs in UTC: each job is scheduled at the two UTC
-- hours that can be the Paris hour (winter / summer) and the function only
-- acts at the right local hour — one run per day, whatever the season.
-- create_notification honours preferences and skips suspended accounts.

-- 18 h Paris: the client, the evening before a confirmed outing.
CREATE OR REPLACE FUNCTION private.notify_booking_reminders()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bk RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 18 THEN RETURN; END IF;

  FOR v_bk IN
    SELECT b.id, b.client_id, b.day, b.period, po.title, pp.display_name AS pro_name,
           (coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
            + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
            AND coalesce(jsonb_array_length(b.participant_info), 0) < b.party_size) AS forms_missing
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    LEFT JOIN public_profiles pp ON pp.id = b.pro_id
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND b.day = private.today_paris() + 1
  LOOP
    PERFORM create_notification(
      v_bk.client_id,
      'booking_reminder',
      'C’est demain',
      '« ' || coalesce(v_bk.title, 'Ta sortie') || ' » demain, '
        || CASE v_bk.period WHEN 'am' THEN 'matin' ELSE 'après-midi' END
        || CASE WHEN v_bk.forms_missing THEN ' · pense à remplir tes fiches participants.' ELSE '.' END,
      jsonb_build_object('booking_id', v_bk.id,
        'variant', CASE WHEN v_bk.forms_missing THEN 'forms' ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_booking_reminders() FROM PUBLIC, anon, authenticated;

-- 9 h Paris: the pro, once, when requests have waited more than 24 h.
CREATE OR REPLACE FUNCTION private.notify_pending_booking_requests()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN; END IF;

  FOR v_row IN
    SELECT b.pro_id, count(*)::INTEGER AS n
    FROM bookings b
    WHERE b.status = 'pending'
      AND b.created_at < now() - INTERVAL '24 hours'
      AND b.day >= private.today_paris()
    GROUP BY b.pro_id
  LOOP
    PERFORM create_notification(
      v_row.pro_id,
      'booking_requests_waiting',
      'Demandes en attente',
      v_row.n || CASE WHEN v_row.n > 1 THEN ' demandes attendent' ELSE ' demande attend' END || ' ta réponse.',
      jsonb_build_object('params', jsonb_build_object('count', v_row.n))
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_pending_booking_requests() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('junto-booking-reminders', '0 16,17 * * *', 'SELECT private.notify_booking_reminders();');
SELECT cron.schedule('junto-booking-requests-waiting', '0 7,8 * * *', 'SELECT private.notify_pending_booking_requests();');
