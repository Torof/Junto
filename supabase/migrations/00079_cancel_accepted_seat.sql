-- Migration 00079: cancel an accepted seat request
-- Requester can cancel their accepted seat, which restores the driver's seat count.

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

-- Allow 'cancelled' status in seat_requests
ALTER TABLE seat_requests DROP CONSTRAINT IF EXISTS seat_requests_status_check;
ALTER TABLE seat_requests ADD CONSTRAINT seat_requests_status_check
  CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled'));
