-- Migration 00200: search_path normalisation + drop dead bypass_lock calls.
--
-- Audit pass 1 finding N-1: several organisation-tab RPCs declared
-- `SET search_path = public, extensions` despite not referencing any
-- extension-provided functions. SECURITY.md "SECURITY DEFINER"
-- prescribes `SET search_path = public`. The extra `, extensions`
-- isn't a security flaw but is inconsistent and adds noise to
-- audits. Normalise to `public` only on the affected RPCs.
--
-- Audit pass 1 finding N-3: set_participation_transport,
-- accept_seat_request and cancel_accepted_seat call
-- set_config('junto.bypass_lock', 'true', true) before updating
-- participations — but participations has no whitelist trigger
-- (00065 comment: "The whitelist trigger on participations doesn't
-- exist — these are only writable via SECURITY DEFINER fns"). The
-- calls are no-ops that misrepresent the protection model.
--
-- Risk of removal: none for the functions in scope. None of them
-- subsequently update a table that DOES have a bypass-aware trigger
-- (users, activities). If a participations whitelist trigger is
-- ever added, the bypass call would need to come back.
--
-- Bodies otherwise IDENTICAL to their previous-latest versions
-- (00199, 00198, 00195, 00120, 00176).

-- ============================================================================
-- set_participation_transport — N-1 + N-3
-- (last rewrite: 00199, kept the N-2 driver-flip block.)
-- ============================================================================
CREATE OR REPLACE FUNCTION set_participation_transport(
  p_activity_id UUID,
  p_transport_type TEXT,
  p_transport_seats SMALLINT DEFAULT NULL,
  p_transport_from_name TEXT DEFAULT NULL,
  p_transport_departs_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_transport_type IS NULL OR p_transport_type NOT IN ('car', 'carpool'))
     AND EXISTS (
       SELECT 1 FROM seat_requests
       WHERE activity_id = p_activity_id
         AND driver_id = v_user_id
         AND status = 'accepted'
     ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_transport_type NOT IN ('car', 'carpool') AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = CASE WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
                                 THEN trim(p_transport_from_name) ELSE NULL END,
      transport_departs_at = p_transport_departs_at
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;

REVOKE EXECUTE ON FUNCTION set_participation_transport FROM anon;
GRANT EXECUTE ON FUNCTION set_participation_transport TO authenticated;

-- ============================================================================
-- accept_seat_request — N-1 + N-3
-- (last rewrite: 00198, kept the M-3 blocked-users guard.)
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_seat_request(
  p_request_id UUID
)
RETURNS VOID
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

  IF NOT v_blocked THEN
    IF v_req.requester_id < v_req.driver_id THEN
      v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
    ELSE
      v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
    END IF;

    SELECT id INTO v_conversation_id FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2 AND status = 'active';
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
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;

-- ============================================================================
-- decline_seat_request — N-1
-- (body identical to 00120.)
-- ============================================================================
CREATE OR REPLACE FUNCTION decline_seat_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_name TEXT;
  v_activity_title TEXT;
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

  UPDATE seat_requests SET status = 'declined' WHERE id = p_request_id;

  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_declined',
    'Demande refusée',
    coalesce(v_driver_name, 'Le conducteur') || ' a refusé ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'seat_request_id', v_req.id,
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_seat_request TO authenticated;

-- ============================================================================
-- cancel_accepted_seat — N-3
-- (last rewrite: 00195, kept the I-1 race fix. Body identical except
--  bypass_lock removed.)
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_accepted_seat(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.requester_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_request.activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'cancelled'
  WHERE id = p_request_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations
  SET transport_seats = COALESCE(transport_seats, 0) + 1
  WHERE activity_id = v_request.activity_id
    AND user_id = v_request.driver_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_accepted_seat FROM anon;
GRANT EXECUTE ON FUNCTION cancel_accepted_seat TO authenticated;

-- ============================================================================
-- request_seat — N-1
-- (body identical to 00176.)
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
      'from_user_id', v_user_id
    )
  );

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION request_seat FROM anon;
GRANT EXECUTE ON FUNCTION request_seat TO authenticated;
