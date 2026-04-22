-- Migration 00092: allow accepted participants to see accepted seat requests
-- The original RLS on seat_requests only exposed rows to requester+driver,
-- hiding passenger assignments from other co-participants. The UI needs
-- this visible (seat pips, passenger list).
--
-- A SECURITY DEFINER function was tried first but proved brittle; a focused
-- second RLS policy is cleaner: existing SELECT for requester/driver stays,
-- plus a new SELECT for any accepted participant limited to accepted rows.

CREATE POLICY "Participants see accepted seat requests"
  ON seat_requests FOR SELECT
  USING (
    status = 'accepted'
    AND EXISTS (
      SELECT 1 FROM participations
      WHERE participations.activity_id = seat_requests.activity_id
        AND participations.user_id = auth.uid()
        AND participations.status = 'accepted'
    )
  );

-- Drop the now-unneeded SECURITY DEFINER function (function remained unused
-- once the client falls back to the direct-SELECT pattern).
DROP FUNCTION IF EXISTS get_activity_seat_assignments(UUID);
