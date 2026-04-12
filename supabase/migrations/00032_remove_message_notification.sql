-- Migration 00032: Remove in-app notification for new messages
-- Messages get a badge on the messagerie tab instead
-- Push notifications for messages will be added in Sprint 8

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

  -- No in-app notification for messages — badge on messagerie tab instead
  -- Push notification will be added in Sprint 8

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_private_message FROM anon;
GRANT EXECUTE ON FUNCTION send_private_message TO authenticated;
