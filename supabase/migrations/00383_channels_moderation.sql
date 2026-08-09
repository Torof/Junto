-- ============================================================================
-- 00383 — Channels: creator moderation (rename / remove member / close) +
-- message removal by the creator + read-only enforcement on closed channels.
-- ============================================================================

-- ---------- delete_message: creator can remove any message in THEIR channel ----------
CREATE OR REPLACE FUNCTION delete_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Author removes their own message (original behavior).
  UPDATE messages SET deleted_at = now()
  WHERE id = p_message_id AND sender_id = v_user_id AND deleted_at IS NULL;
  IF FOUND THEN RETURN; END IF;

  -- Otherwise: a channel creator may remove any message in their channel.
  SELECT conversation_id INTO v_conv FROM messages WHERE id = p_message_id AND deleted_at IS NULL;
  IF v_conv IS NOT NULL AND EXISTS (
    SELECT 1 FROM channels ch WHERE ch.conversation_id = v_conv AND ch.created_by = v_user_id
  ) THEN
    UPDATE messages SET deleted_at = now() WHERE id = p_message_id AND deleted_at IS NULL;
    RETURN;
  END IF;

  RAISE EXCEPTION 'Operation not permitted';
END;
$$;
REVOKE ALL ON FUNCTION delete_message(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_message(UUID) TO authenticated;

-- ---------- rename_channel (creator only) ----------
CREATE OR REPLACE FUNCTION rename_channel(p_conversation_id UUID, p_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id AND created_by = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_clean := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean IS NULL OR char_length(v_clean) > 60 THEN RAISE EXCEPTION 'junto.channel_name'; END IF;
  UPDATE conversations SET name = v_clean WHERE id = p_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION rename_channel(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rename_channel(UUID, TEXT) TO authenticated;

-- ---------- remove_channel_member (creator only, + ban so it sticks) ----------
CREATE OR REPLACE FUNCTION remove_channel_member(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
  INSERT INTO channel_bans (conversation_id, user_id, banned_by)
  VALUES (p_conversation_id, p_user_id, v_user_id)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION remove_channel_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_channel_member(UUID, UUID) TO authenticated;

-- ---------- close_channel (creator only) ----------
CREATE OR REPLACE FUNCTION close_channel(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE channels SET closed_at = now() WHERE conversation_id = p_conversation_id AND closed_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION close_channel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION close_channel(UUID) TO authenticated;

-- ---------- read-only on closed channels (belt across every insert path) ----------
CREATE OR REPLACE FUNCTION messages_block_closed_channel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM channels WHERE conversation_id = NEW.conversation_id AND closed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER messages_no_closed_channel
  BEFORE INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION messages_block_closed_channel();
