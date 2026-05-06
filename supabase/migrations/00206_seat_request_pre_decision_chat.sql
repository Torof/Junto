-- Migration 00206: open the chat on request, return conversation_id on accept.
--
-- Two related changes that flow together:
--
-- 1) request_seat now seeds a conversation between requester and driver
--    when the request is created. Until now, the DM channel only opened
--    on acceptance — meaning requester and driver couldn't discuss the
--    pickup or terms before the binary accept/decline. Drivers had to
--    decline-then-wait-for-renegotiated-request to surface any concern.
--    The seed message carries the activity title + pickup info + the
--    requester's optional note so the driver lands on a self-explaining
--    chat. Block-aware (skips the seed if either side has blocked the
--    other) and idempotent (reuses an existing conversation pair).
--
-- 2) accept_seat_request now returns the conversation_id (or NULL if
--    blocked) so the client can route the driver straight to the
--    chat thread on success. The function previously returned VOID;
--    Postgres requires DROP-before-CREATE for return-type changes.
--
-- The accept-side seed message ("🚗 Place réservée …") still fires —
-- it's the confirmation of the deal. Two seeds in the same thread is
-- intentional: the request-side describes the ask, the accept-side
-- describes the agreement.

-- ============================================================================
-- request_seat — adds conversation + seed message on creation/re-request.
-- Auth chain unchanged from 00200.
-- ============================================================================

CREATE OR REPLACE FUNCTION request_seat(
  p_activity_id UUID,
  p_driver_id UUID,
  p_pickup_from TEXT DEFAULT NULL,
  p_message TEXT DEFAULT NULL,
  p_requested_pickup_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  v_u1 UUID;
  v_u2 UUID;
  v_seed_message TEXT;
  v_blocked BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  v_pickup := CASE WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
                   THEN trim(p_pickup_from) ELSE NULL END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
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

  -- Open the chat so requester + driver can discuss before the
  -- accept/decline decision. Bidirectional block check — DMs are
  -- blocked both ways, and a request shouldn't force a private
  -- channel between blocked parties.
  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_driver_id)
       OR (blocker_id = p_driver_id AND blocked_id = v_user_id)
  ) INTO v_blocked;

  IF NOT v_blocked THEN
    IF v_user_id < p_driver_id THEN
      v_u1 := v_user_id; v_u2 := p_driver_id;
    ELSE
      v_u1 := p_driver_id; v_u2 := v_user_id;
    END IF;

    SELECT id INTO v_conversation_id
    FROM conversations
    WHERE user_1 = v_u1 AND user_2 = v_u2 AND status = 'active';

    IF v_conversation_id IS NULL THEN
      INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES (v_u1, v_u2, v_user_id, 'active', 'transport', NOW(), NOW())
      RETURNING id INTO v_conversation_id;
    END IF;

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
      'conversation_id', v_conversation_id
    )
  );

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION request_seat FROM anon;
GRANT EXECUTE ON FUNCTION request_seat TO authenticated;

-- ============================================================================
-- accept_seat_request — return type changes VOID → UUID. Body otherwise
-- identical to the post-00200 version, just RETURN v_conversation_id at
-- the end so the client can route to the chat.
-- ============================================================================

DROP FUNCTION IF EXISTS accept_seat_request(UUID);

CREATE FUNCTION accept_seat_request(p_request_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_updated_count INTEGER;
  v_blocked BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_req.driver_id AND blocked_id = v_req.requester_id)
       OR (blocker_id = v_req.requester_id AND blocked_id = v_req.driver_id)
  ) INTO v_blocked;

  -- The conversation almost certainly exists already (request_seat
  -- seeds it on creation), but keep the lookup-or-create logic so an
  -- accept made before this migration's deploy still works smoothly.
  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  SELECT id INTO v_conversation_id FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2 AND status = 'active';

  IF NOT v_blocked THEN
    IF v_conversation_id IS NULL THEN
      INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
      RETURNING id INTO v_conversation_id;
    END IF;

    v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
      || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
      || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

    INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
    VALUES (
      v_conversation_id, v_req.driver_id, v_req.requester_id, v_message,
      jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
      NOW()
    );

    UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  END IF;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id
    )
  );

  RETURN v_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request(UUID) TO authenticated;
