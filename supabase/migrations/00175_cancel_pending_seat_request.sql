-- Migration 00175: cancel a still-pending seat request.
--
-- cancel_accepted_seat (00079, hardened in 00120) only handles seats
-- where the driver has already accepted — it restores the driver's
-- transport_seats count. A still-pending request hasn't taken a seat
-- yet (seats decrement on accept, not on request), so cancelling one
-- is just a status flip with no side effects on the driver's row.
--
-- The MyOutingCard pending-cancel flow needs this to let a passenger
-- back out of a pending request before they can pick a different
-- transport. Without it the pending request would silently linger
-- if/when the user changed mode, leaving the driver with a stale
-- "pending" they could later approve.
--
-- Auth chain:
--   1. auth.uid() not null
--   2. caller not suspended
--   3. seat_request exists
--   4. caller is the requester (only the passenger can cancel their
--      own pending; if the driver wants to refuse, they use
--      decline_seat_request)
--   5. status = 'pending' (already-accepted goes through
--      cancel_accepted_seat which restores seats)
--   6. activity is published or in_progress (locked otherwise per
--      the 00120 lock-on-finished pattern)

CREATE OR REPLACE FUNCTION cancel_pending_seat_request(
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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id;

  IF v_request IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.requester_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_request.activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'cancelled' WHERE id = p_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_pending_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION cancel_pending_seat_request TO authenticated;
