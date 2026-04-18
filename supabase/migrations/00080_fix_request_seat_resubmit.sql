-- Migration 00080: allow re-requesting a seat after decline/cancel
-- The UNIQUE constraint prevents duplicate rows, so upsert to pending
-- instead of inserting when a previous request exists.

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
  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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
