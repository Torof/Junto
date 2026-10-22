-- Migration 00223: blocked_users filter on social-vote SELECT policies.
-- From the parallel security audit MINOR list (consistency with the
-- 00203 fix applied earlier on activity_gear / seat_requests).
--
-- Two tables had counterparty-only SELECT policies with no block
-- filter. Adding the unidirectional rule (caller-side hides blocked
-- counterparties) brings them in line with the rest of the codebase
-- per SECURITY.md "Blocage — directionnalité".
--
-- Notes:
--   - peer_validations (00105): policy was `voter_id = auth.uid()
--     OR voted_id = auth.uid()`. A blocker still saw their blocked
--     counterparty's votes against them.
--   - reputation_votes (00034): same shape.
--
-- The audit agent also flagged sport_level_endorsements but that
-- table was dropped in 00159 (orphan from a removed UI feature) —
-- nothing to fix there.

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
