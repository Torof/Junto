-- Migration 00204: extend get_activity_seat_assignments with pickup info.
--
-- Audit pass 5 / I-1: GroupCard's getSeatAssignments was directly
-- querying seat_requests, which under RLS only returns rows where
-- auth.uid() is the requester or driver — third-party participants
-- got zero accepted seats and the org tab's "X rides with Y" surface
-- went blank for them. The dedicated SECURITY DEFINER RPC
-- get_activity_seat_assignments (00089) was built for that view
-- and recently hardened with a blocked_users filter (00203), but
-- it didn't return the pickup info GroupCard needs to render
-- passenger sub-rows.
--
-- Decision: extend the RPC's RETURNS TABLE with pickup_from and
-- requested_pickup_at so third parties see the same picture as
-- the driver. (Pickup info is text the requester chose to share
-- when sending the seat request — surfacing it to other accepted
-- participants of the same activity is an explicit coordination
-- choice, not a privacy expansion.)
--
-- Auth chain unchanged from 00089/00203:
--   1. auth.uid() not null
--   2. caller not suspended
--   3. caller is accepted participant of p_activity_id
--   4. blocked_users filter: caller's blocks hide rows on either
--      endpoint (driver or requester).
--
-- Postgres requires DROP-before-CREATE when RETURNS TABLE changes
-- (CREATE OR REPLACE only handles same-signature replacements).

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
    SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id
      AND user_id = v_user_id
      AND status = 'accepted'
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
