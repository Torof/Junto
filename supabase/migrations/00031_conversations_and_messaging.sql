-- Migration 00031: Conversations table + messaging functions
-- Sprint 6 — Private Messaging

-- ============================================================================
-- TABLE: conversations
-- ============================================================================
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_1 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_2 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  initiated_by UUID NOT NULL REFERENCES users(id),
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  CHECK (user_1 != user_2),
  UNIQUE (user_1, user_2)
);

CREATE INDEX idx_conversations_user1 ON conversations(user_1);
CREATE INDEX idx_conversations_user2 ON conversations(user_2);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations FORCE ROW LEVEL SECURITY;

-- SELECT: own conversations only, bidirectional block check
CREATE POLICY "conversations_select_own"
  ON conversations FOR SELECT
  TO authenticated
  USING (
    (auth.uid() = user_1 OR auth.uid() = user_2)
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = auth.uid() AND blocked_id = CASE WHEN auth.uid() = user_1 THEN user_2 ELSE user_1 END)
         OR (blocked_id = auth.uid() AND blocker_id = CASE WHEN auth.uid() = user_1 THEN user_2 ELSE user_1 END)
    )
  );

-- INSERT/UPDATE/DELETE: no client policy — via SECURITY DEFINER functions only
-- (No explicit DENY policies — FORCE ROW LEVEL SECURITY + absence of permissive
--  policies blocks direct client writes. SECURITY DEFINER functions bypass RLS
--  as the function owner, not the table owner.)

-- ============================================================================
-- ALTER: add conversation_id to private_messages
-- Clean up any orphaned rows first (dev only — no production data)
-- ============================================================================
DELETE FROM private_messages;
ALTER TABLE private_messages ADD COLUMN conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE;
CREATE INDEX idx_private_messages_conversation ON private_messages(conversation_id);

-- Update RLS: use conversation membership instead of sender/receiver
DROP POLICY IF EXISTS "private_messages_select" ON private_messages;

CREATE POLICY "private_messages_select"
  ON private_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM conversations
      WHERE id = private_messages.conversation_id
      AND (user_1 = auth.uid() OR user_2 = auth.uid())
    )
    AND deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = auth.uid() AND blocked_id = CASE WHEN auth.uid() = private_messages.sender_id THEN private_messages.receiver_id ELSE private_messages.sender_id END)
         OR (blocked_id = auth.uid() AND blocker_id = CASE WHEN auth.uid() = private_messages.sender_id THEN private_messages.receiver_id ELSE private_messages.sender_id END)
    )
  );

-- ============================================================================
-- FUNCTION: create_or_get_conversation
-- ============================================================================
CREATE OR REPLACE FUNCTION create_or_get_conversation(
  p_other_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_1 UUID;
  v_user_2 UUID;
  v_conversation_id UUID;
  v_hourly_count INTEGER;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Can't message yourself
  IF v_user_id = p_other_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Other user exists and is not suspended
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_other_user_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Bidirectional block check
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_other_user_id)
       OR (blocker_id = p_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Order user IDs for consistent UNIQUE constraint
  IF v_user_id < p_other_user_id THEN
    v_user_1 := v_user_id;
    v_user_2 := p_other_user_id;
  ELSE
    v_user_1 := p_other_user_id;
    v_user_2 := v_user_id;
  END IF;

  -- 7. Check if conversation already exists
  SELECT id INTO v_conversation_id
  FROM conversations
  WHERE user_1 = v_user_1 AND user_2 = v_user_2;

  IF v_conversation_id IS NOT NULL THEN
    RETURN v_conversation_id;
  END IF;

  -- 8. Rate limit with advisory lock: 10 new conversations per hour (initiated by this user)
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_conversations'));

  SELECT count(*) INTO v_hourly_count
  FROM conversations
  WHERE initiated_by = v_user_id
    AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 9. Create conversation
  INSERT INTO conversations (user_1, user_2, initiated_by, created_at)
  VALUES (v_user_1, v_user_2, v_user_id, now())
  RETURNING id INTO v_conversation_id;

  RETURN v_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_or_get_conversation FROM anon;
GRANT EXECUTE ON FUNCTION create_or_get_conversation TO authenticated;

-- ============================================================================
-- FUNCTION: send_private_message
-- ============================================================================
CREATE OR REPLACE FUNCTION send_private_message(
  p_conversation_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conversation RECORD;
  v_other_user_id UUID;
  v_message_id UUID;
  v_recent_count INTEGER;
  v_user_name TEXT;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Conversation exists and user is a member
  SELECT id, user_1, user_2 INTO v_conversation
  FROM conversations
  WHERE id = p_conversation_id;

  IF v_conversation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conversation.user_1 AND v_user_id != v_conversation.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conversation.user_1 THEN v_conversation.user_2 ELSE v_conversation.user_1 END;

  -- 4. Other user not suspended
  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Bidirectional block check
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Rate limit: 1 message per minute per conversation
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dm_' || p_conversation_id::text));

  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Content validation
  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 8. Insert message
  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, trim(p_content), now())
  RETURNING id INTO v_message_id;

  -- 9. Update conversation last_message_at
  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;

  -- 10. Notify other user
  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_other_user_id,
    'new_message',
    'Nouveau message',
    v_user_name || ' t''a envoyé un message',
    jsonb_build_object('conversation_id', p_conversation_id)
  );

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_private_message FROM anon;
GRANT EXECUTE ON FUNCTION send_private_message TO authenticated;

-- ============================================================================
-- FUNCTION: edit_private_message (edit content or soft delete)
-- ============================================================================
CREATE OR REPLACE FUNCTION edit_private_message(
  p_message_id UUID,
  p_content TEXT DEFAULT NULL,
  p_delete BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_message RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, sender_id, deleted_at INTO v_message
  FROM private_messages
  WHERE id = p_message_id;

  IF v_message IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_message.sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_message.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_delete THEN
    UPDATE private_messages SET deleted_at = now() WHERE id = p_message_id;
  ELSIF p_content IS NOT NULL AND trim(p_content) != '' THEN
    UPDATE private_messages SET content = trim(p_content), edited_at = now() WHERE id = p_message_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION edit_private_message FROM anon;
GRANT EXECUTE ON FUNCTION edit_private_message TO authenticated;

-- ============================================================================
-- FUNCTION: edit_wall_message (edit content or soft delete)
-- ============================================================================
CREATE OR REPLACE FUNCTION edit_wall_message(
  p_message_id UUID,
  p_content TEXT DEFAULT NULL,
  p_delete BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_message RECORD;
  v_activity_status TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT wm.id, wm.user_id, wm.activity_id, wm.deleted_at INTO v_message
  FROM wall_messages wm
  WHERE wm.id = p_message_id;

  IF v_message IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_message.user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_message.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT status INTO v_activity_status FROM activities WHERE id = v_message.activity_id;
  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_delete THEN
    UPDATE wall_messages SET deleted_at = now() WHERE id = p_message_id;
  ELSIF p_content IS NOT NULL AND trim(p_content) != '' THEN
    UPDATE wall_messages SET content = trim(p_content), edited_at = now() WHERE id = p_message_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION edit_wall_message FROM anon;
GRANT EXECUTE ON FUNCTION edit_wall_message TO authenticated;
