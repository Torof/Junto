-- Migration 00223: blocked_users filter on social-vote SELECT policies.
-- From the parallel security audit MINOR list (consistency with the
-- 00203 fix applied earlier on activity_gear / seat_requests).
--
-- Three tables had open or counterparty-only SELECT policies with no
-- block filter. Adding the unidirectional rule (caller-side hides
-- blocked counterparties) brings them in line with the rest of the
-- codebase per SECURITY.md "Blocage — directionnalité".
--
-- Notes:
--   - peer_validations (00105): policy was `voter_id = auth.uid()
--     OR voted_id = auth.uid()`. A blocker still saw their blocked
--     counterparty's votes.
--   - reputation_votes (00034): same shape.
--   - sport_level_endorsements (00097): `USING (true)` — fully open.
--     Aggregation paths use a SECURITY DEFINER function that already
--     bypasses RLS, so the per-row filter only affects direct table
--     reads (currently unused in the client) — defense-in-depth for
--     future query patterns.

DROP POLICY IF EXISTS "peer_validations_select" ON peer_validations;
CREATE POLICY "peer_validations_select"
  ON peer_validations FOR SELECT
  TO authenticated
  USING (
    (auth.uid() = voter_id OR auth.uid() = voted_id)
    AND voter_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid())
    AND voted_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid())
  );

DROP POLICY IF EXISTS "reputation_votes_select" ON reputation_votes;
CREATE POLICY "reputation_votes_select"
  ON reputation_votes FOR SELECT
  TO authenticated
  USING (
    (auth.uid() = voter_id OR auth.uid() = voted_id)
    AND voter_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid())
    AND voted_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid())
  );

DROP POLICY IF EXISTS "sport_level_endorsements_select" ON sport_level_endorsements;
CREATE POLICY "sport_level_endorsements_select"
  ON sport_level_endorsements FOR SELECT
  TO authenticated
  USING (
    voter_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid())
    AND target_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid())
  );
