-- Migration 00099: structured-message metadata on private_messages
-- Adds a nullable jsonb column so server-generated messages (seat accepted,
-- shared activity, etc.) can carry typed payload that the client renders as
-- a CTA below the bubble (e.g. "Voir l'activité").
-- Existing rows have metadata = NULL, no behavior change.

ALTER TABLE private_messages
  ADD COLUMN metadata JSONB;

-- Update accept_seat_request to attach activity context to the seeded message.
-- Auth chain unchanged.
CREATE OR REPLACE FUNCTION accept_seat_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';

  UPDATE seat_requests SET status = 'accepted' WHERE id = p_request_id;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;
  SELECT transport_from_name INTO v_driver_from FROM participations WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

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
    v_conversation_id,
    v_req.driver_id,
    v_req.requester_id,
    v_message,
    jsonb_build_object(
      'type', 'seat_accepted',
      'activity_id', v_req.activity_id
    ),
    NOW()
  );

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

  -- Push to the requester
  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx2amx0aHpkeWR6YXRjdnd3cml1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4MjUyNTMsImV4cCI6MjA5MTQwMTI1M30.cxBoxTF1eVNvA8kd_PhoLMmkdEbLvfyocm5kAWefEjM'
    ),
    body := jsonb_build_object(
      'user_id', v_req.requester_id,
      'title', 'Place confirmée !',
      'body', coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
      'data', jsonb_build_object(
        'conversation_id', v_conversation_id,
        'activity_id', v_req.activity_id,
        'type', 'seat_request_accepted'
      )
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;
