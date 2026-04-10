-- Migration 00005: notifications + blocked_users tables

-- ============================================================================
-- TABLE: notifications
-- ============================================================================
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications FORCE ROW LEVEL SECURITY;

-- SELECT: own notifications only
CREATE POLICY "notifications_select_own"
  ON notifications FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- INSERT: no client policy — functions only
-- DELETE: no client policy

-- UPDATE: own notifications, read_at only (accepted for MVP — user can only corrupt own data)
CREATE POLICY "notifications_update_own"
  ON notifications FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE: blocked_users
-- ============================================================================
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

-- ============================================================================
-- HTML strip trigger for users (bio, display_name)
-- ============================================================================
CREATE OR REPLACE FUNCTION strip_html_users()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.display_name IS NOT NULL THEN
    NEW.display_name := regexp_replace(NEW.display_name, '<[^>]*>', '', 'g');
  END IF;
  IF NEW.bio IS NOT NULL THEN
    NEW.bio := regexp_replace(NEW.bio, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION strip_html_users() FROM anon, authenticated;

CREATE TRIGGER users_strip_html
  BEFORE INSERT OR UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION strip_html_users();
