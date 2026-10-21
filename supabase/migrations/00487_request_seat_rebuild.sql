-- ============================================================================
-- 00487 — request_seat : 00486 l'avait reconstruite depuis une copie antérieure
-- à 00477 (perte du test d'identifiant DB-AC-2 et des délais de redemande
-- AB-4). Reconstruite depuis 00477 (dernière définition) + le correctif IX-2.
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

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, p_driver_id, v_seed_message,
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
