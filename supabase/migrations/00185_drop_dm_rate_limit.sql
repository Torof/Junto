-- Migration 00185: drop the 1-message-per-minute DM rate limit.
--
-- DMs should flow naturally — 1/min/conversation made any back-and-forth
-- conversation hit the limiter on the second message. Spam/abuse is
-- handled by block + report, not by a hard rate cap.
--
-- The advisory lock was only there to make the rate-limit count check
-- race-free; with the check gone, the lock has no purpose either.
--
-- Authorization chain (unchanged from the previous version, minus the
-- rate-limit and lock steps):
--   1. auth.uid() not null
--   2. caller not suspended
--   3. conversation exists
--   4. conversation.status = 'active'
--   5. caller is one of the two participants
--   6. other user not suspended
--   7. neither user blocked the other
--   8. content not empty after trim
-- Same generic 'Operation not permitted' on every failure.

CREATE OR REPLACE FUNCTION public.send_private_message(
  p_conversation_id UUID,
  p_content TEXT
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

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, v_clean_content, now())
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
