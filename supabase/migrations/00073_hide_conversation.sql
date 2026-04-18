-- Migration 00073: hide conversation for individual users
-- "Hide for me" model — conversation disappears from your list.
-- Reappears if the other person sends a new message.
-- For permanent removal, use block (existing feature).

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS hidden_by_user_1 BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS hidden_by_user_2 BOOLEAN NOT NULL DEFAULT FALSE;

-- RPC: hide a conversation (sets hidden flag for the caller)
CREATE OR REPLACE FUNCTION hide_conversation(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_conv.user_1 THEN
    UPDATE conversations SET hidden_by_user_1 = TRUE WHERE id = p_conversation_id;
  ELSIF v_user_id = v_conv.user_2 THEN
    UPDATE conversations SET hidden_by_user_2 = TRUE WHERE id = p_conversation_id;
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION hide_conversation FROM anon;
GRANT EXECUTE ON FUNCTION hide_conversation TO authenticated;

-- When a new message is sent, unhide the conversation for the receiver
-- so it reappears in their list.
CREATE OR REPLACE FUNCTION unhide_on_new_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv RECORD;
BEGIN
  SELECT * INTO v_conv FROM conversations WHERE id = NEW.conversation_id;
  IF v_conv IS NULL THEN RETURN NEW; END IF;

  IF NEW.sender_id = v_conv.user_1 AND v_conv.hidden_by_user_2 THEN
    UPDATE conversations SET hidden_by_user_2 = FALSE WHERE id = NEW.conversation_id;
  ELSIF NEW.sender_id = v_conv.user_2 AND v_conv.hidden_by_user_1 THEN
    UPDATE conversations SET hidden_by_user_1 = FALSE WHERE id = NEW.conversation_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_unhide_on_new_message ON private_messages;
CREATE TRIGGER trg_unhide_on_new_message
  AFTER INSERT ON private_messages
  FOR EACH ROW
  EXECUTE FUNCTION unhide_on_new_message();
