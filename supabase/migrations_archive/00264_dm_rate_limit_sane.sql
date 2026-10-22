-- Migration 00264: reinstate the DM rate limit at a chat-sane level.
--
-- Backlog walk #1 (2026-06-11) — archéologie du bug "un popup bloque
-- l'écriture des messages" (Scott, 2026-05-05) :
--   - Cause d'époque : la limite originelle était 1 message/minute/
--     conversation (00158 et avant). Deuxième message en moins de 60s
--     → erreur générique → Alert. Dans un chat, ce n'est pas de
--     l'anti-abus, c'est une conversation cassée.
--   - Le rework reply (00208/00209/00220) a reconstruit la fonction
--     SANS la limite NI l'advisory lock — bug accidentellement résolu,
--     garde anti-abus accidentellement perdue. SECURITY.md affirmait
--     toujours "DM 1/min" (faux depuis 00209).
--
-- Fix : limite réinstaurée à 15/min/conversation (le mur est à 30/min)
-- + advisory lock réinstauré pour sérialiser le check+insert. 15/min =
-- un message toutes les 4s en continu : aucun humain en conversation
-- réelle ne le touche, un spammeur si.
--
-- Body otherwise identical to 00220.

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
  v_recent_count INTEGER;
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

  -- Rate limit: 15/min/conversation under advisory lock (mig 00264 —
  -- reinstated after being lost in the 00208/00209 reply rework; the
  -- historical 1/min was conversation-hostile and is deliberately NOT
  -- restored).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dm_' || p_conversation_id::text));

  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 15 THEN
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
