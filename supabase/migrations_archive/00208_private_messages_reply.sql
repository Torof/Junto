-- Migration 00208: reply-to threading on private messages.
--
-- Adds a self-referencing reply_to_message_id column on
-- private_messages so the chat UI can render quoted-reply blocks
-- (WhatsApp / iMessage style). ON DELETE SET NULL — if the original
-- message gets deleted, the reply stays but loses the quote.
--
-- send_private_message gains an optional p_reply_to_message_id
-- parameter. The function validates that the referenced message
-- belongs to the same conversation; an invalid pointer is silently
-- treated as NULL rather than failing the whole send (defensive
-- against client-side stale state).
--
-- Auth chain otherwise unchanged from 00185.

ALTER TABLE private_messages
  ADD COLUMN IF NOT EXISTS reply_to_message_id UUID
    REFERENCES private_messages(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS private_messages_reply_to_idx
  ON private_messages(reply_to_message_id)
  WHERE reply_to_message_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.send_private_message(
  p_conversation_id UUID,
  p_content TEXT,
  p_reply_to_message_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_conversation RECORD;
  v_other_user_id UUID;
  v_message_id UUID;
  v_sender_name TEXT;
  v_secret TEXT;
  v_clean_content TEXT;
  v_reply_to UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2, status INTO v_conversation FROM conversations WHERE id = p_conversation_id;
  IF v_conversation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conversation.status != 'active' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conversation.user_1 AND v_user_id != v_conversation.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conversation.user_1 THEN v_conversation.user_2 ELSE v_conversation.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_content := regexp_replace(trim(p_content), '<[^>]*>', '', 'g');

  -- Validate the reply pointer: must reference an existing message
  -- in this same conversation and not be soft-deleted. Otherwise
  -- treat as NULL (defensive — don't fail the send because of a
  -- stale client cache).
  v_reply_to := NULL;
  IF p_reply_to_message_id IS NOT NULL THEN
    SELECT id INTO v_reply_to
    FROM private_messages
    WHERE id = p_reply_to_message_id
      AND conversation_id = p_conversation_id
      AND deleted_at IS NULL;
  END IF;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, reply_to_message_id, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, v_clean_content, v_reply_to, now())
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', 'Tu as reçu un message',
        'data', jsonb_build_object('conversation_id', p_conversation_id, 'type', 'new_message'),
        'collapseId', 'message-' || p_conversation_id::text
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.send_private_message(UUID, TEXT, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.send_private_message(UUID, TEXT, UUID) TO authenticated;
