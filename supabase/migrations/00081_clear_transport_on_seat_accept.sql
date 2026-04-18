-- Migration 00081: clear requester's transport when seat is accepted
-- If someone registered as on_foot/bike/etc and then gets a car seat,
-- their old transport declaration should be removed so they don't
-- appear in two groups.

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
