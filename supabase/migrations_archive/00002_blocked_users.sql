-- Migration 00002: blocked_users table (needed before activities — RLS references it)

CREATE TABLE blocked_users (
  blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id != blocked_id)
);

ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocked_users FORCE ROW LEVEL SECURITY;

-- SELECT: own blocks + admins
CREATE POLICY "blocked_users_select_own"
  ON blocked_users FOR SELECT
  TO authenticated
  USING (
    blocker_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true)
  );

-- INSERT: can only block on own behalf
CREATE POLICY "blocked_users_insert_own"
  ON blocked_users FOR INSERT
  TO authenticated
  WITH CHECK (blocker_id = auth.uid());

-- DELETE: only the blocker can unblock
CREATE POLICY "blocked_users_delete_own"
  ON blocked_users FOR DELETE
  TO authenticated
  USING (blocker_id = auth.uid());
