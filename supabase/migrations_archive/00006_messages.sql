-- Migration 00006: wall_messages + private_messages tables

-- ============================================================================
-- TABLE: wall_messages
-- ============================================================================
CREATE TABLE wall_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE wall_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE wall_messages FORCE ROW LEVEL SECURITY;

-- SELECT: accepted participants only, blocked filtered on message author
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
    AND deleted_at IS NULL
  );

-- INSERT/UPDATE/DELETE: no client policy — via functions only

CREATE OR REPLACE FUNCTION strip_html_wall_messages()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.content IS NOT NULL THEN
    NEW.content := regexp_replace(NEW.content, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION strip_html_wall_messages() FROM anon, authenticated;

CREATE TRIGGER wall_messages_strip_html
  BEFORE INSERT OR UPDATE ON wall_messages
  FOR EACH ROW EXECUTE FUNCTION strip_html_wall_messages();

-- ============================================================================
-- TABLE: private_messages
-- ============================================================================
CREATE TABLE private_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  CHECK (sender_id != receiver_id)
);

ALTER TABLE private_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_messages FORCE ROW LEVEL SECURITY;

-- SELECT: sender or receiver, bidirectional block check
CREATE POLICY "private_messages_select"
  ON private_messages FOR SELECT
  TO authenticated
  USING (
    (auth.uid() = sender_id OR auth.uid() = receiver_id)
    AND deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = auth.uid() AND blocked_id = CASE WHEN auth.uid() = sender_id THEN receiver_id ELSE sender_id END)
         OR (blocked_id = auth.uid() AND blocker_id = CASE WHEN auth.uid() = sender_id THEN receiver_id ELSE sender_id END)
    )
  );

-- INSERT/UPDATE/DELETE: no client policy — via functions only

CREATE OR REPLACE FUNCTION strip_html_private_messages()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.content IS NOT NULL THEN
    NEW.content := regexp_replace(NEW.content, '<[^>]*>', '', 'g');
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION strip_html_private_messages() FROM anon, authenticated;

CREATE TRIGGER private_messages_strip_html
  BEFORE INSERT OR UPDATE ON private_messages
  FOR EACH ROW EXECUTE FUNCTION strip_html_private_messages();
