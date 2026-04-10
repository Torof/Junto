-- Migration 00003: participations table

CREATE TABLE participations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'refused', 'removed', 'withdrawn')),
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  UNIQUE (user_id, activity_id)
);

ALTER TABLE participations ENABLE ROW LEVEL SECURITY;
ALTER TABLE participations FORCE ROW LEVEL SECURITY;

-- SELECT: creator sees all for their activity, participant sees own, accepted see co-accepted
-- Blocked users filtered from participant lists
CREATE POLICY "participations_select"
  ON participations FOR SELECT
  TO authenticated
  USING (
    (
      auth.uid() = user_id
      OR auth.uid() = (SELECT creator_id FROM activities WHERE id = activity_id)
      OR (status = 'accepted' AND EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = participations.activity_id
        AND p2.user_id = auth.uid() AND p2.status = 'accepted'
      ))
    )
    AND user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
    )
  );

-- INSERT: no client policy — via join_activity function only
-- UPDATE: no client policy — via accept/refuse/remove/leave functions only
-- DELETE: no client policy — via leave_activity function only
