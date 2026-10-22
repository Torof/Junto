-- Migration 00177: re-introduce edit_wall_message.
--
-- The function existed in 00031 but was dropped in 00160 with the
-- comment "no wall-edit UI exists". We're now adding that UI (long-
-- press menu on own messages → Edit / Delete), so the function comes
-- back. Same signature and auth chain as the original — content edit
-- when p_delete=false, soft-delete (sets deleted_at) when p_delete=true.
--
-- Auth chain:
--   1. auth.uid() not null
--   2. caller not suspended
--   3. message exists
--   4. caller is the message author
--   5. message not already soft-deleted
--   6. activity is in published / in_progress (locked otherwise)

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
