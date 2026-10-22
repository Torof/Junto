-- 00537 — discussion moderation holds (audit 2026-10-23, messaging F1-F3).
--
-- * A channel creator who LEFT the channel kept full moderation (delete others'
--   messages, ban, rename, change photo, close): every creator power now also
--   requires being a member.
-- * After an admin closed a reported channel, its creator could still erase
--   other members' messages; in a group taken down by moderation, the reported
--   author could delete their own messages (the evidence). delete_message now
--   refuses in a moderated conversation or a closed channel — own messages
--   included — like send_message / edit_message already do.

CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT conversation_id INTO v_conv FROM messages WHERE id = p_message_id AND deleted_at IS NULL;
  IF v_conv IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00537: a conversation taken down by moderation, or a closed channel, is
  -- frozen — nobody erases anything there (not even their own messages).
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv AND moderated_at IS NOT NULL)
     OR EXISTS (SELECT 1 FROM channels WHERE conversation_id = v_conv AND closed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE messages SET deleted_at = now()
  WHERE id = p_message_id AND sender_id = v_user_id AND deleted_at IS NULL;
  IF FOUND THEN RETURN; END IF;

  -- The channel's creator moderates — while still a member (00537).
  IF EXISTS (
    SELECT 1 FROM channels ch WHERE ch.conversation_id = v_conv AND ch.created_by = v_user_id
  ) AND private.is_conversation_member(v_conv, v_user_id) THEN
    UPDATE messages SET deleted_at = now() WHERE id = p_message_id AND deleted_at IS NULL;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Operation not permitted';
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_channel_member(p_conversation_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00537: creator powers only while still a member of the channel.
  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Serialize against join_channel (see above).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  -- Ban FIRST, then remove membership: with the shared lock this order also
  -- means a concurrent join blocks until the ban row is visible.
  INSERT INTO channel_bans (conversation_id, user_id, banned_by)
  VALUES (p_conversation_id, p_user_id, v_user_id)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.close_channel(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00537: creator powers only while still a member of the channel.
  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE channels SET closed_at = now() WHERE conversation_id = p_conversation_id AND closed_at IS NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rename_channel(p_conversation_id uuid, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00514: a closed discussion (by its creator or by moderation) is frozen.
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id AND created_by = v_user_id AND closed_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00537: creator powers only while still a member of the channel.
  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  v_clean := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean IS NULL OR char_length(v_clean) > 60 THEN RAISE EXCEPTION 'junto.channel_name'; END IF;
  UPDATE conversations SET name = v_clean WHERE id = p_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_channel_photo(p_conversation_id uuid, p_photo_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_photo TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM channels
    WHERE conversation_id = p_conversation_id
      AND created_by = v_user_id
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00537: creator powers only while still a member of the channel.
  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR private.project_url() IS NULL  -- 00524: fail-closed without a project URL
       OR v_photo NOT LIKE private.project_url() || '/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
       OR v_photo ~* '(\.\.|%2e|%2f|%5c|\\)'  -- 00503
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE channels SET photo_url = v_photo WHERE conversation_id = p_conversation_id;
END;
$function$;
