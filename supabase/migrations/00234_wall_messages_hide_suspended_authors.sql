-- Migration 00234: wall_messages SELECT hides posts by suspended users.
--
-- Audit finding C2 (docs/AUDIT.md, 2026-05-16): the wall_messages
-- SELECT policy from 00006 checks participation + blocked-users +
-- soft-delete, but not whether the message author is suspended. A
-- suspended user's wall posts therefore remain visible to every
-- accepted participant of the activity.
--
-- Product decision (Scott, 2026-05-16): wall is a public surface — a
-- suspended user's posts hard-hide for everyone. DMs / conversations
-- stay visible to the existing counterparty (read-only-ghost stance,
-- handled separately — no change there).
--
-- NULL author_id (deleted user, FK ON DELETE SET NULL) keeps showing
-- — that's the anonymized-historical state, not a live suspended user.

DROP POLICY IF EXISTS "wall_messages_select" ON wall_messages;

CREATE POLICY "wall_messages_select"
  ON wall_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = wall_messages.activity_id
      AND user_id = auth.uid()
      AND status = 'accepted'
    )
    AND (wall_messages.user_id IS NULL OR wall_messages.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
    ))
    AND (wall_messages.user_id IS NULL OR wall_messages.user_id NOT IN (
      SELECT id FROM users WHERE suspended_at IS NOT NULL
    ))
    AND deleted_at IS NULL
  );
