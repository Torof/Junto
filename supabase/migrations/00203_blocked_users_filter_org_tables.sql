-- Migration 00203: align blocked_users filter on coordination tables.
--
-- Audit pass 4 / M-2: participations RLS (00004) and the
-- public_participants view (00075) both exclude rows where
-- user_id is in auth.uid()'s blocked list. activity_gear (00084)
-- and seat_requests (00076) did not. Same for the SECURITY DEFINER
-- read function get_activity_seat_assignments (00089), which
-- exposes accepted seats to all activity participants.
--
-- Result: a blocker still saw their blocked counterparty's gear
-- contributions on the inventory pills, the bringer recap, the
-- seat-request lists, and on third-party seat assignments. Blocking
-- semantics were incoherent across the org-tab surface.
--
-- Direction is unidirectional, matching wall + participations:
--   "auth.uid() blocked X → auth.uid() doesn't see X's rows".
-- Coordination > social — a block is for hiding from one's own view,
-- not for two-way ostracism on logistical channels.
--
-- Side effect: when row visibility flips off via a new block, the
-- caller's UI loses the bringer/avatar at next refetch. The
-- underlying contribution stays in the DB; logistics aren't
-- corrupted, just the blocker's view of them.

-- ============================================================================
-- 1. activity_gear — exclude rows whose user_id was blocked by caller
-- ============================================================================

DROP POLICY IF EXISTS "Participants can read activity gear" ON activity_gear;
CREATE POLICY "Participants can read activity gear"
  ON activity_gear FOR SELECT
  USING (
    (
      EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = activity_gear.activity_id
          AND user_id = auth.uid()
          AND status = 'accepted'
      )
      OR EXISTS (
        SELECT 1 FROM activities
        WHERE id = activity_gear.activity_id
          AND creator_id = auth.uid()
      )
    )
    AND user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
    )
  );

-- ============================================================================
-- 2. seat_requests — exclude rows whose counterparty was blocked by caller
-- ============================================================================
--
-- The existing policy already restricts visibility to the requester
-- or driver of the row. Add a counterparty-aware block filter:
-- if I'm the requester and I blocked the driver, hide; if I'm the
-- driver and I blocked the requester, hide.

DROP POLICY IF EXISTS "Users see their own seat requests" ON seat_requests;
CREATE POLICY "Users see their own seat requests"
  ON seat_requests FOR SELECT
  USING (
    (requester_id = auth.uid() OR driver_id = auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users
      WHERE blocker_id = auth.uid()
        AND blocked_id = CASE
          WHEN seat_requests.requester_id = auth.uid() THEN seat_requests.driver_id
          ELSE seat_requests.requester_id
        END
    )
  );

-- ============================================================================
-- 3. get_activity_seat_assignments — apply the same filter inside the
--    SECURITY DEFINER read so third-party visibility (other participants
--    seeing X-rides-with-Y pairs) also respects the caller's blocks.
-- ============================================================================
--
-- Auth chain unchanged from 00089. Body adds a NOT EXISTS guard
-- against blocked_users for both endpoints of the assignment.

CREATE OR REPLACE FUNCTION get_activity_seat_assignments(p_activity_id UUID)
RETURNS TABLE (
  id UUID,
  driver_id UUID,
  requester_id UUID,
  display_name TEXT,
  avatar_url TEXT
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
      pp.avatar_url
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
