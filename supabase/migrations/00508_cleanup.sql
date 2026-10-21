-- ============================================================================
-- 00508 — Phase de nettoyage (validée par Scott, 2026-10-21 ; pas de testeurs,
-- donc rien n'attend une ancienne version de production).
-- * Anciennes tables wall_messages / private_messages retirées : request_seat
--   et accept_seat_request écrivent directement dans messages ; create_report
--   perd ses branches héritées ; déclencheurs de miroir retirés.
-- * Fonctions sans appelant retirées (dont l'ancienne invitation, les éditions
--   héritées, les badges « mis en avant », le témoignage de présence entre pairs
--   désactivé depuis 00434 et sa table).
-- * Vue public_participants, table contacts (remplacée en 00372), colonnes
--   mortes (users.is_pro_verified / pro_verified_at, conversations.hidden_by_*),
--   index en double.
-- * Purge quotidienne du journal des tâches planifiées (42 Mo).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text DEFAULT NULL::text, p_message text DEFAULT NULL::text, p_requested_pickup_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_starts_at TIMESTAMPTZ;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_conv_sender UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_seed_message TEXT;
  v_recent_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_driver_id)
       OR (blocker_id = p_driver_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('request_seat:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM seat_requests
  WHERE requester_id = v_user_id
    AND created_at > NOW() - INTERVAL '5 minutes';
  IF v_recent_count >= 5 THEN RAISE EXCEPTION 'junto.seat_rate_limit'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id
    AND a.status IN ('published', 'in_progress')
    AND a.starts_at > NOW() - INTERVAL '15 seconds'
    AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'junto.no_seats_available'; END IF;

  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'junto.pickup_out_of_window';
    END IF;
  END IF;

  -- Strip HTML/script tags from pickup_from too (message already does).
  v_pickup := CASE
    WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
    THEN regexp_replace(trim(p_pickup_from), '<[^>]*>', '', 'g')
    ELSE NULL
  END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  -- 00494 (BR-3): one seat per passenger and outing; a driver who carries
  -- passengers does not ride with someone else.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND driver_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';  -- 00496 (B-5): actionable, coded
  END IF;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  -- 00477 (DB-AC-2): test the id — the record has NULL columns, so the
  -- re-request branch was dead code and every re-request was refused.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    -- 00477 (AC-4 / AB-4): no request/cancel loop toward the same driver —
    -- 24 h after a refusal, 1 h after a cancellation or expiry.
    IF v_existing.status = 'declined' AND v_existing.created_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    IF v_existing.status IN ('cancelled', 'expired') AND v_existing.created_at > NOW() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message,
        requested_pickup_at = p_requested_pickup_at
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message, requested_pickup_at)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message, p_requested_pickup_at)
      RETURNING id INTO v_request_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  IF v_user_id < p_driver_id THEN
    v_u1 := v_user_id; v_u2 := p_driver_id;
  ELSE
    v_u1 := p_driver_id; v_u2 := v_user_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (pas seulement active).
  -- Une ligne pending/declined est réactivée en logistique (retag 'transport'
  -- + purge des champs de requête — invariant 00372 : un refus social ne
  -- devient pas un contact par le covoit). Plus d'unique_violation brute.
  SELECT id, status, request_sender_id INTO v_conversation_id, v_conv_status, v_conv_sender
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  -- 00486 (IX-2 / BR-1): if the requester's own contact request to the driver
  -- was refused (or is still unanswered), the seat request must not turn into
  -- a conversation the driver never accepted. The driver gets the request by
  -- notification and decides; accepting it is the driver's consent.
  IF v_conversation_id IS NOT NULL AND v_conv_status IN ('declined', 'pending_request')
     AND v_conv_sender = v_user_id THEN
    v_conversation_id := NULL;
  END IF;

  IF v_conversation_id IS NULL AND v_conv_status IS NOT NULL THEN
    NULL; -- 00486: muted (see above)
  ELSIF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES (v_u1, v_u2, v_user_id, 'active', 'transport', NOW(), NOW())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  ELSIF v_conv_status != 'active' THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations
    SET status = 'active', initiated_from = 'transport',
        request_sender_id = NULL, request_message = NULL,
        pending_activity_id = NULL, request_expires_at = NULL,
        last_message_at = NOW()
    WHERE id = v_conversation_id;
    UPDATE conversation_members SET hidden_at = NULL
    WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;

  IF v_conversation_id IS NOT NULL THEN
  v_seed_message := '🚗 Demande de place pour « ' || v_activity_title || ' »'
    || CASE WHEN v_pickup IS NOT NULL THEN E'\nDepuis : ' || v_pickup ELSE '' END
    || CASE WHEN v_message IS NOT NULL THEN E'\n\n' || v_message ELSE '' END;

  -- 00508: straight into the unified store (the legacy table and its mirror
  -- are gone). This writer notifies on its own: no generic message push.
  PERFORM set_config('junto.skip_message_push', 'true', true);
  INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, v_seed_message,
    jsonb_build_object(
      'type', 'seat_request_pending',
      'activity_id', p_activity_id,
      'seat_request_id', v_request_id
    ),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_driver_id,
    'seat_request',
    'Demande de covoiturage',
    coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »'
      || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'conversation_id', v_conversation_id,
      'variant', CASE WHEN v_pickup IS NOT NULL THEN 'pickup' ELSE NULL END,
      'params', jsonb_build_object('name', coalesce(v_requester_name, 'Quelqu''un'), 'title', v_activity_title, 'pickup', coalesce(v_pickup, ''))
    )
  );

  RETURN v_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_seat_request(p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_updated_count INTEGER;
  v_skip_seed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'junto.seats_exhausted';
  END IF;

  -- 00494 (BR-3): a passenger already seated with another driver of this
  -- outing does not take a second seat (two drivers accepting at once are
  -- serialised on the passenger).
  PERFORM pg_advisory_xact_lock(hashtext('seat_passenger:' || v_req.activity_id::text || ':' || v_req.requester_id::text));
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
               AND status = 'accepted' AND id <> p_request_id) THEN
    RAISE EXCEPTION 'junto.passenger_already_seated';
  END IF;
  -- 00496 (BR-3): a passenger who carries passengers does not ride elsewhere,
  -- and a driver who is seated in someone else's car takes nobody.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND driver_id = v_req.requester_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00496 (B-4): the passenger's other pending requests on this outing are
  -- withdrawn (other drivers no longer see a request they cannot accept).
  UPDATE seat_requests SET status = 'cancelled'
  WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
    AND status = 'pending' AND id <> p_request_id;

  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_req.driver_id AND blocked_id = v_req.requester_id)
       OR (blocker_id = v_req.requester_id AND blocked_id = v_req.driver_id)
  ) OR EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_req.requester_id AND u.suspended_at IS NOT NULL
  ) INTO v_skip_seed;

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (retag 'transport' à la
  -- réactivation, purge des champs de requête). Plus d'unique_violation brute.
  SELECT id, status INTO v_conversation_id, v_conv_status
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF NOT v_skip_seed THEN
    IF v_conversation_id IS NULL THEN
      BEGIN
        INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
        RETURNING id INTO v_conversation_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT id INTO v_conversation_id FROM conversations
        WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
      END;
    ELSIF v_conv_status != 'active' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE conversations
      SET status = 'active', initiated_from = 'transport',
          request_sender_id = NULL, request_message = NULL,
          pending_activity_id = NULL, request_expires_at = NULL,
          last_message_at = NOW()
      WHERE id = v_conversation_id;
      UPDATE conversation_members SET hidden_at = NULL
      WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
      PERFORM set_config('junto.bypass_lock', 'false', true);
    END IF;

    v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
      || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
      || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

    -- 00508: unified store directly; this writer notifies on its own.
    PERFORM set_config('junto.skip_message_push', 'true', true);
    INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
    VALUES (
      v_conversation_id, v_req.driver_id, v_message,
      jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
      NOW()
    );

    UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  ELSIF v_conv_status IS DISTINCT FROM 'active' THEN
    -- Seed sauté (blocage/suspension) : ne pas pointer la notif vers un fil
    -- non actif.
    v_conversation_id := NULL;
  END IF;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );

  RETURN v_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity',
                           'pro_review', 'offering_review', 'message', 'group', 'channel') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');
  IF char_length(v_reason) < 10 THEN RAISE EXCEPTION 'junto.report_reason_too_short'; END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Existence checks. 'message' / 'group' hit the unified store; the reporter
  -- must be a member of the conversation the content lives in (no probing).
  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'activity' AND NOT EXISTS (SELECT 1 FROM activities WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'message' AND NOT EXISTS (
    -- 00499 (MS-8): a message deleted by its author stays reportable by a
    -- member (deleting abuse right after sending it must not dodge a report).
    SELECT 1 FROM messages m
    WHERE m.id = p_target_id
      AND private.is_conversation_member(m.conversation_id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'group' AND NOT EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = p_target_id AND c.type = 'group'
      AND private.is_conversation_member(c.id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'channel' AND NOT EXISTS (
    SELECT 1 FROM conversations c WHERE c.id = p_target_id AND c.type = 'channel'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN RAISE EXCEPTION 'junto.report_already_filed'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));
  SELECT count(*) INTO v_hourly_count FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.report_rate_limit'; END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;
  RETURN v_report_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_user_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.age_confirmed_at := OLD.age_confirmed_at;
  NEW.tier := OLD.tier;
  NEW.is_admin := OLD.is_admin;
  NEW.is_demo := OLD.is_demo;
  NEW.suspended_at := OLD.suspended_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.tutorial_seen_at := OLD.tutorial_seen_at;
  NEW.push_token := OLD.push_token;
  NEW.reliability_score := OLD.reliability_score;
  NEW.levels_per_sport := OLD.levels_per_sport;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.transition_statuses_only()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_activity_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();

  -- Solo end-of-window: nobody (besides the creator) ever joined → the
  -- outing didn't happen. Must run BEFORE the completed update.
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now();

  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  -- Pre-event sweep: published activities approaching start. All three
  -- emitters gate internally on their respective time windows (pre_warning
  -- T-2h..T0, pre_warning_10min T-10..T0, qr_reminder T-10..T0 creator-only).
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'published'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND a.starts_at - INTERVAL '2 hours' <= now()
      AND a.starts_at > now()
  LOOP
    PERFORM notify_presence_pre_warning(v_activity_id);
    PERFORM notify_presence_pre_warning_10min(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  -- During-event sweep: in_progress activities. validate_warning gates on
  -- T+duration/2 internally. (qr_create_reminder no longer called here —
  -- moved to the published sweep at T-10min.)
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    PERFORM notify_presence_validate_warning(v_activity_id);
  END LOOP;

  -- Post-event sweep: completed activities. validate_overdue at T+1h after
  -- end, peer_review_closing at T+22h. Each gates internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '1 hour'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_presence_validate_overdue(v_activity_id);
  END LOOP;

  -- 00427: rate_participants only once the vote window is actually OPEN
  -- (end+15min) — the completion trigger no longer emits it at the flip,
  -- where tapping the notification guaranteed a "too early" refusal.
  -- No requires_presence gate: trait/level votes apply to every outing
  -- with >=2 accepted participants. notify_* gates + dedups internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '15 minutes'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_rate_participants(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_peer_review_state(p_activity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_result jsonb;
  v_sport_key TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id',                p.user_id,
      'display_name',           pp.display_name,
      'avatar_url',             pp.avatar_url,
      -- 00488 (DX-1): never echo an absence to co-participants.
      'confirmed_present',      CASE WHEN p.confirmed_present THEN true END,
      -- 00508: peer presence testimony removed (disabled since 00434).
      'peer_validation_count',  0,
      'i_voted_presence',       false,
      'my_badge_votes',         coalesce(my_votes.keys, ARRAY[]::TEXT[]),
      'declared_level',         NULLIF(pp.levels_per_sport ->> v_sport_key, '')
    )
  ) INTO v_result
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  LEFT JOIN (
    SELECT voted_id, array_agg(badge_key) AS keys
    FROM reputation_votes
    WHERE activity_id = p_activity_id AND voter_id = v_user_id
    GROUP BY voted_id
  ) my_votes ON my_votes.voted_id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id != v_user_id;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$function$;

UPDATE reports SET target_type = 'message' WHERE target_type IN ('wall_message', 'private_message');
ALTER TABLE reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_type_check CHECK (target_type = ANY (ARRAY[
  'user', 'activity', 'pro_review', 'offering_review', 'message', 'group', 'channel']));

DROP FUNCTION public._is_presence_window(uuid);
DROP FUNCTION public.revoke_push_token(text);
DROP FUNCTION public.reply_to_request(text, uuid, text);
DROP FUNCTION public.hide_conversation(uuid);
DROP FUNCTION public.edit_wall_message(uuid, text, boolean);
DROP FUNCTION public.edit_private_message(uuid, text, boolean);
DROP FUNCTION public.get_top_vouched_badges(uuid[]);
DROP FUNCTION public.set_pro_photo_url(uuid, text);
DROP FUNCTION public.set_pro_offering_photo_url(uuid, text);
DROP FUNCTION public.peer_validate_presence(uuid, uuid);
DROP FUNCTION public.invite_users_to_activity(uuid, uuid[]);
DROP FUNCTION public.notify_peer_review_closing(uuid);

DROP TABLE private_messages;
DROP TABLE wall_messages;
DROP FUNCTION public.mirror_private_message();
DROP FUNCTION public.unhide_on_new_message();
DROP FUNCTION IF EXISTS public.strip_html_private_messages();
DROP FUNCTION IF EXISTS public.strip_html_wall_messages();

DROP TABLE peer_validations;
DROP VIEW IF EXISTS public_participants;
DROP TABLE contacts;

ALTER TABLE users DROP COLUMN IF EXISTS is_pro_verified;
ALTER TABLE users DROP COLUMN IF EXISTS pro_verified_at;
ALTER TABLE conversations DROP COLUMN IF EXISTS hidden_by_user_1;
ALTER TABLE conversations DROP COLUMN IF EXISTS hidden_by_user_2;

DROP INDEX IF EXISTS pro_profile_photos_pro_idx;
DROP INDEX IF EXISTS pro_offering_photos_offering_idx;
DROP INDEX IF EXISTS idx_push_tokens_user_id;
DROP INDEX IF EXISTS idx_conversations_user1;
DROP INDEX IF EXISTS pro_offerings_pro_id_idx;
DROP INDEX IF EXISTS messages_sender_idx;

SELECT cron.unschedule('junto-cron-log-purge') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'junto-cron-log-purge');
SELECT cron.schedule('junto-cron-log-purge', '50 4 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$);
