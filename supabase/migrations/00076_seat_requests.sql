-- Migration 00076: transport seat requests
-- A lightweight request entity for "can I ride with you?"
-- Separate from contact requests because co-participants already
-- have conversation access — this is about seat commitment.

CREATE TABLE seat_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (requester_id != driver_id),
  UNIQUE (activity_id, requester_id, driver_id)
);

ALTER TABLE seat_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE seat_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY "Users see their own seat requests"
  ON seat_requests FOR SELECT
  USING (requester_id = auth.uid() OR driver_id = auth.uid());

-- ============================================================================
-- RPC: request a seat from a driver
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Both must be accepted participants
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Driver must have seats available
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- No duplicate pending request
  IF EXISTS (
    SELECT 1 FROM seat_requests
    WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO seat_requests (activity_id, requester_id, driver_id)
  VALUES (p_activity_id, v_user_id, p_driver_id)
  RETURNING id INTO v_request_id;

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
-- RPC: accept seat request — decrements driver's available seats
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Decrement seat
  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

  UPDATE seat_requests SET status = 'accepted' WHERE id = p_request_id;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    '',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'type', 'seat_request_accepted'
    ),
    NOW()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;

-- ============================================================================
-- RPC: decline seat request — silent
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

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'declined' WHERE id = p_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_seat_request TO authenticated;
