-- ============================================================================
-- 00551 — Emoji reactions on messages + a read-only preview of a channel one
-- has not joined (Scott 2026-10-24, board « Messagerie — canaux et bulles »).
--
--   (1) message_reactions: ONE reaction per person per message (as WhatsApp).
--       Read with the messages (embed), under RLS: only a member of the
--       conversation sees them, and never those of someone they are blocked
--       with (same rule as the messages themselves). No client write grant:
--       set_message_reaction only.
--   (2) set_message_reaction(message, emoji): same emoji again or NULL removes
--       it, another emoji replaces it. Chain: signed in · not suspended ·
--       message exists, not deleted · member of its conversation (demo curtain
--       included, via is_conversation_member) · no block with the author ·
--       an emoji, short, no ASCII, no letters. No notification; the
--       conversation topic gets a 'change' so open threads refresh.
--   (3) get_channel_preview(channel): the last 12 messages of an open channel,
--       for the « join » card. Chain: signed in · not suspended · channel
--       exists · demo curtain · not banned · without deleted messages, authors
--       one is blocked with, suspended authors. Read-only. A channel is open:
--       anyone may join and read it all; the preview shows less.
-- ============================================================================

CREATE TABLE public.message_reactions (
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji text NOT NULL CHECK (
    char_length(emoji) BETWEEN 1 AND 16
    AND emoji !~ '[\x01-\x7F]'
    AND emoji !~ '[[:alpha:][:space:]]'
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions FORCE ROW LEVEL SECURITY;
CREATE INDEX message_reactions_user_idx ON public.message_reactions (user_id);

-- Since 00502 a new table gives clients SELECT only; reads under this policy.
CREATE POLICY message_reactions_select_member ON public.message_reactions
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = message_reactions.message_id
      AND m.deleted_at IS NULL
      AND private.is_conversation_member(m.conversation_id, auth.uid())
      AND private.message_author_visible(m.conversation_id, message_reactions.user_id, auth.uid())
  ));

CREATE OR REPLACE FUNCTION public.set_message_reaction(p_message_id uuid, p_emoji text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_msg RECORD;
  v_emoji TEXT := NULLIF(trim(p_emoji), '');
  v_current TEXT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, conversation_id, sender_id, deleted_at INTO v_msg FROM messages WHERE id = p_message_id;
  IF v_msg.id IS NULL OR v_msg.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT private.is_conversation_member(v_msg.conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_msg.sender_id IS NOT NULL AND v_msg.sender_id <> v_user_id AND EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE (b.blocker_id = v_user_id AND b.blocked_id = v_msg.sender_id)
       OR (b.blocker_id = v_msg.sender_id AND b.blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_emoji IS NOT NULL AND (
       char_length(v_emoji) > 16 OR v_emoji ~ '[\x01-\x7F]' OR v_emoji ~ '[[:alpha:][:space:]]'
     ) THEN
    RAISE EXCEPTION 'junto.reaction_invalid';
  END IF;

  SELECT emoji INTO v_current FROM message_reactions WHERE message_id = p_message_id AND user_id = v_user_id;
  IF v_emoji IS NULL OR v_emoji = v_current THEN
    DELETE FROM message_reactions WHERE message_id = p_message_id AND user_id = v_user_id;
  ELSE
    INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (p_message_id, v_user_id, v_emoji)
    ON CONFLICT (message_id, user_id) DO UPDATE SET emoji = EXCLUDED.emoji, created_at = now();
  END IF;

  -- Open threads refresh (the same curated 'change' a new message sends).
  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'message_reactions', 'conversation_id', v_msg.conversation_id, 'message_id', p_message_id),
      'change', 'conversation:' || v_msg.conversation_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.set_message_reaction(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_channel_preview(p_conversation_id uuid)
 RETURNS TABLE(id uuid, sender_id uuid, display_name text, avatar_url text, content text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE users.id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM channels c WHERE c.conversation_id = p_conversation_id) THEN RETURN; END IF;
  IF private.demo_channel_hidden(p_conversation_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = p_conversation_id AND b.user_id = v_user_id) THEN RETURN; END IF;

  RETURN QUERY
  SELECT x.id, x.sender_id, x.display_name, x.avatar_url, x.content, x.created_at
  FROM (
    SELECT m.id, m.sender_id, pp.display_name, pp.avatar_url, m.content, m.created_at
    FROM messages m
    JOIN public_profiles pp ON pp.id = m.sender_id
    WHERE m.conversation_id = p_conversation_id
      AND m.deleted_at IS NULL
      AND NOT private.user_is_suspended(m.sender_id)
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = m.sender_id)
           OR (b.blocker_id = m.sender_id AND b.blocked_id = v_user_id))
    ORDER BY m.created_at DESC
    LIMIT 12
  ) x
  ORDER BY x.created_at ASC;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.get_channel_preview(uuid) TO authenticated;
