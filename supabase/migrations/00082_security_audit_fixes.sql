-- Migration 00082: security audit fixes (critical + high + medium)
-- Adds missing suspension checks, conversation status checks, caller identity
-- checks, HTML stripping, and activity status guards across multiple functions.

-- ============================================================================
-- CRITICAL #1: send_private_message — add conversation status = 'active' check
-- MEDIUM #11: send_private_message — add HTML stripping
-- ============================================================================
CREATE OR REPLACE FUNCTION send_private_message(
  p_conversation_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conversation RECORD;
  v_other_user_id UUID;
  v_message_id UUID;
  v_recent_count INTEGER;
  v_sender_name TEXT;
  v_secret TEXT;
  v_clean_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2, status INTO v_conversation FROM conversations WHERE id = p_conversation_id;
  IF v_conversation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- CRITICAL #1: conversation must be active
  IF v_conversation.status != 'active' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conversation.user_1 AND v_user_id != v_conversation.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conversation.user_1 THEN v_conversation.user_2 ELSE v_conversation.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dm_' || p_conversation_id::text));

  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- MEDIUM #11: strip HTML tags
  v_clean_content := regexp_replace(trim(p_content), '<[^>]*>', '', 'g');

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, v_clean_content, now())
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', 'Tu as reçu un message',
        'data', jsonb_build_object('conversation_id', p_conversation_id, 'type', 'new_message')
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_private_message FROM anon;
GRANT EXECUTE ON FUNCTION send_private_message TO authenticated;


-- ============================================================================
-- CRITICAL #2: request_seat — add suspension check
-- MEDIUM #13: request_seat — add activity status check
-- ============================================================================
CREATE OR REPLACE FUNCTION request_seat(
  p_activity_id UUID,
  p_driver_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_driver_name TEXT;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_existing RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- CRITICAL #2: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- MEDIUM #13: activity must be published or in_progress
  IF NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND status IN ('published', 'in_progress')
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF v_existing.status = 'accepted' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    UPDATE seat_requests SET status = 'pending', created_at = NOW()
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    INSERT INTO seat_requests (activity_id, requester_id, driver_id)
    VALUES (p_activity_id, v_user_id, p_driver_id)
    RETURNING id INTO v_request_id;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = p_activity_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    p_driver_id,
    'seat_request',
    v_requester_name || ' demande une place',
    '',
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'type', 'seat_request'
    ),
    NOW()
  );

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION request_seat FROM anon;
GRANT EXECUTE ON FUNCTION request_seat TO authenticated;


-- ============================================================================
-- CRITICAL #3: accept_seat_request — add suspension check
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
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_from_name TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- CRITICAL #3: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Decrement driver's seat count
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

  -- Clear requester's own transport declaration (they're now a passenger)
  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';

  UPDATE seat_requests SET status = 'accepted' WHERE id = p_request_id;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;
  SELECT transport_from_name INTO v_from_name FROM participations WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

  -- Create or get conversation + insert seeded message
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

  v_message := '🚗 Place réservée' || CASE WHEN v_from_name IS NOT NULL THEN ' depuis ' || v_from_name ELSE '' END || ' pour « ' || v_activity_title || ' »';

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (v_conversation_id, v_req.driver_id, v_req.requester_id, v_message, NOW());

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    '',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'type', 'seat_request_accepted'
    ),
    NOW()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;


-- ============================================================================
-- CRITICAL #4: decline_seat_request — add suspension check
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- CRITICAL #4: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'declined' WHERE id = p_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_seat_request TO authenticated;


-- ============================================================================
-- CRITICAL #5: cancel_accepted_seat — add suspension check
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_accepted_seat(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- CRITICAL #5: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id;

  IF v_request IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_request.requester_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_request.status != 'accepted' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE seat_requests SET status = 'cancelled' WHERE id = p_request_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_seats = COALESCE(transport_seats, 0) + 1
  WHERE activity_id = v_request.activity_id
    AND user_id = v_request.driver_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_accepted_seat FROM anon;
GRANT EXECUTE ON FUNCTION cancel_accepted_seat TO authenticated;


-- ============================================================================
-- CRITICAL #6: cancel_contact_request — add caller must be request_sender_id
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- CRITICAL #6: only the sender can cancel their own request
  IF v_user_id != v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM conversations WHERE id = p_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION cancel_contact_request TO authenticated;


-- ============================================================================
-- HIGH #7: decline_contact_request — add suspension check
-- ============================================================================
CREATE OR REPLACE FUNCTION decline_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- HIGH #7: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE conversations
  SET status = 'declined'
  WHERE id = p_conversation_id;

  -- No notification to sender (silent decline)
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_contact_request TO authenticated;


-- ============================================================================
-- HIGH #8: accept_contact_request — add suspension check
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_sender_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- HIGH #8: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only the recipient can accept (not the sender)
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_sender_id := v_conv.request_sender_id;

  -- Flip to active
  UPDATE conversations
  SET status = 'active', request_expires_at = NULL
  WHERE id = p_conversation_id;

  -- Insert the request message as the first real message
  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_sender_id, v_user_id, v_conv.request_message, v_conv.created_at);

  -- Notify the sender that their request was accepted
  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    v_sender_id,
    'contact_request_accepted',
    'Demande acceptée',
    '',
    jsonb_build_object('conversation_id', p_conversation_id, 'type', 'contact_request_accepted'),
    NOW()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_contact_request TO authenticated;


-- ============================================================================
-- HIGH #9: hide_conversation — add suspension check
-- ============================================================================
CREATE OR REPLACE FUNCTION hide_conversation(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- HIGH #9: suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_conv.user_1 THEN
    UPDATE conversations SET hidden_by_user_1 = TRUE WHERE id = p_conversation_id;
  ELSIF v_user_id = v_conv.user_2 THEN
    UPDATE conversations SET hidden_by_user_2 = TRUE WHERE id = p_conversation_id;
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION hide_conversation FROM anon;
GRANT EXECUTE ON FUNCTION hide_conversation TO authenticated;


-- ============================================================================
-- MEDIUM #10: send_wall_message — add HTML stripping
-- ============================================================================
CREATE OR REPLACE FUNCTION send_wall_message(
  p_activity_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity_status TEXT;
  v_message_id UUID;
  v_recent_count INTEGER;
  v_clean_content TEXT;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Activity must be active
  SELECT status INTO v_activity_status FROM activities WHERE id = p_activity_id;
  IF v_activity_status IS NULL OR v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. User must be accepted participant
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id
      AND user_id = v_user_id
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Rate limit: 1 message per minute per activity
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_wall_' || p_activity_id::text));

  SELECT count(*) INTO v_recent_count
  FROM wall_messages
  WHERE activity_id = p_activity_id
    AND user_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Content validation (DB CHECK constraint handles length, but verify not empty after trim)
  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- MEDIUM #10: strip HTML tags
  v_clean_content := regexp_replace(trim(p_content), '<[^>]*>', '', 'g');

  -- 7. Insert message
  INSERT INTO wall_messages (activity_id, user_id, content, created_at)
  VALUES (p_activity_id, v_user_id, v_clean_content, now())
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_wall_message FROM anon;
GRANT EXECUTE ON FUNCTION send_wall_message TO authenticated;


-- ============================================================================
-- MEDIUM #12: set_participation_transport — add activity status check
-- ============================================================================
CREATE OR REPLACE FUNCTION set_participation_transport(
  p_activity_id UUID,
  p_transport_type TEXT,
  p_transport_seats SMALLINT DEFAULT NULL,
  p_transport_from_name TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- MEDIUM #12: activity must be published or in_progress
  IF NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND status IN ('published', 'in_progress')
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Must be an accepted participant
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Validate transport type
  IF p_transport_type NOT IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Seats only relevant for car/carpool
  IF p_transport_type NOT IN ('car', 'carpool') AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = CASE WHEN p_transport_from_name IS NOT NULL THEN trim(p_transport_from_name) ELSE NULL END
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;

REVOKE EXECUTE ON FUNCTION set_participation_transport FROM anon;
GRANT EXECUTE ON FUNCTION set_participation_transport TO authenticated;
