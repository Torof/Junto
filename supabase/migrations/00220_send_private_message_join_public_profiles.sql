-- Migration 00220: send_private_message reads sender display_name
-- from public_profiles instead of users. From the parallel security
-- audit MINOR list.
--
-- CLAUDE.md "All JOINs with user data must use public_profiles view,
-- NOT users table". The public_profiles view filters out suspended
-- users (via 00173's `WHERE suspended_at IS NULL`); reading directly
-- from `users` for the push title meant a sender suspended between
-- the auth-chain check and the SELECT could still appear on the
-- recipient's lock screen. Vanishingly small race window in practice
-- but the principle is documented and easy to honour.
--
-- Body otherwise identical to 00208.

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

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
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

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_other_user_id AND u.suspended_at IS NOT NULL) THEN
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

  -- Push title sourced from public_profiles so a sender suspended
  -- mid-flight has their name elided to NULL → 'Junto' fallback.
  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
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
