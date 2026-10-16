-- ============================================================================
-- 00455 — get_conversation_peer exposes initiated_from (Scott 2026-10-16:
-- « Retirer de mes contacts » moves into the conversation's ⋯ menu, which must
-- show it only on a SOCIAL DM — never on a carpool / booking / reply thread).
--
-- Live body = 00351, unchanged except the extra column. Return type changes →
-- DROP first (PGRST203 otherwise). Same read gate: my conversation only.
-- ============================================================================
DROP FUNCTION IF EXISTS get_conversation_peer(UUID);

CREATE FUNCTION get_conversation_peer(p_conversation_id UUID)
RETURNS TABLE (other_id UUID, display_name TEXT, avatar_url TEXT, initiated_from TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END AS other_id,
         pp.display_name, pp.avatar_url,
         CASE WHEN c.type = 'dm' THEN c.initiated_from END AS initiated_from
  FROM conversations c
  LEFT JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END
  WHERE auth.uid() IS NOT NULL
    AND c.id = p_conversation_id
    AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
$$;

REVOKE ALL ON FUNCTION get_conversation_peer(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_conversation_peer(UUID) TO authenticated;
