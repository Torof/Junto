-- ============================================================================
-- 00369 — get_wall_messages renvoie aussi conversation_id (Brique 4a).
--
-- L'onglet Chat d'une activité ne connaît que l'activity_id ; pour marquer la
-- conversation lue côté serveur (mark_conversation_read, non-lus unifiés), il lui
-- faut le conversation_id. `conversations` est en lecture révoquée → get_wall_
-- messages est le porteur naturel. Aucune autre logique ne change.
-- ============================================================================

-- RETURNS shape change → drop first (42P13).
DROP FUNCTION IF EXISTS get_wall_messages(UUID);

CREATE OR REPLACE FUNCTION get_wall_messages(p_activity_id UUID)
RETURNS TABLE (
  id UUID, conversation_id UUID, user_id UUID, content TEXT, metadata JSONB,
  reply_to_message_id UUID, edited_at TIMESTAMPTZ, created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Latest 200 (server-side cap), returned oldest-first for the UI.
  SELECT * FROM (
    SELECT m.id, m.conversation_id, m.sender_id, m.content, m.metadata,
           m.reply_to_message_id, m.edited_at, m.created_at
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE auth.uid() IS NOT NULL
      AND c.activity_id = p_activity_id
      AND m.deleted_at IS NULL
      AND private.is_conversation_member(c.id, auth.uid())
      AND private.message_author_visible(c.id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC
    LIMIT 200
  ) sub
  ORDER BY created_at ASC
$$;

REVOKE ALL ON FUNCTION get_wall_messages(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_wall_messages(UUID) TO authenticated;
