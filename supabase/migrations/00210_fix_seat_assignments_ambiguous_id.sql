-- Migration 00210: fix ambiguous `id` in get_activity_seat_assignments.
--
-- The function's RETURNS TABLE declares `id` as the first OUT column.
-- The body checked `SELECT 1 FROM users WHERE id = v_user_id` — PL/pgSQL
-- treats that bare `id` as ambiguous (could be the OUT parameter or
-- the users.id column) and raises 42702 at call time:
--
--   ERROR: column reference "id" is ambiguous
--   DETAIL: It could refer to either a PL/pgSQL variable or a table column.
--
-- Result: every authenticated call to get_activity_seat_assignments
-- failed silently in transport-service.getSeatAssignments (the catch
-- returns []), so the GroupCard's "X rides with Y" passenger view
-- went blank for everyone after a successful seat acceptance.
--
-- Fix: alias the tables and qualify every column inside the EXISTS
-- subqueries. Body is otherwise identical to 00204 (auth chain +
-- blocked_users filter + pickup info).

DROP FUNCTION IF EXISTS get_activity_seat_assignments(UUID);

CREATE FUNCTION get_activity_seat_assignments(p_activity_id UUID)
RETURNS TABLE (
  id UUID,
  driver_id UUID,
  requester_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  pickup_from TEXT,
  requested_pickup_at TIMESTAMPTZ
)
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

  IF NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.user_id = v_user_id
      AND p.status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
    SELECT
      sr.id,
      sr.driver_id,
      sr.requester_id,
      pp.display_name,
      pp.avatar_url,
      sr.pickup_from,
      sr.requested_pickup_at
    FROM seat_requests sr
    JOIN public_profiles pp ON pp.id = sr.requester_id
    WHERE sr.activity_id = p_activity_id
      AND sr.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE b.blocker_id = v_user_id
          AND b.blocked_id IN (sr.driver_id, sr.requester_id)
      );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_seat_assignments(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION get_activity_seat_assignments(UUID) FROM public;
GRANT EXECUTE ON FUNCTION get_activity_seat_assignments(UUID) TO authenticated;
