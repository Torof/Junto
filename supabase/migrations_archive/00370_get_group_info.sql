-- ============================================================================
-- 00370 — get_group_info (Brique 4d) : lecture curée d'un fil de groupe.
--
-- Le hub renvoie déjà name/icon/member_count (00368), mais l'écran conversation
-- charge son propre contexte et doit lister les membres (header + gestion). DM =
-- get_conversation_peer ; groupe = cette RPC. Membre-gated, type='group' only.
--
-- Chaîne (validée) : auth → conversation type='group' ET appelant membre
--   (private.is_conversation_member) → une ligne par membre (méta répétée).
-- ============================================================================

CREATE OR REPLACE FUNCTION get_group_info(p_conversation_id UUID)
RETURNS TABLE (
  group_name TEXT, group_icon TEXT, created_by UUID,
  member_id UUID, member_name TEXT, member_avatar TEXT, member_joined_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.name, c.icon, c.created_by,
         cm.user_id, COALESCE(pp.display_name, '?'), pp.avatar_url, cm.joined_at
  FROM conversations c
  JOIN conversation_members cm ON cm.conversation_id = c.id
  LEFT JOIN public_profiles pp ON pp.id = cm.user_id
  WHERE c.id = p_conversation_id
    AND c.type = 'group'
    AND auth.uid() IS NOT NULL
    AND private.is_conversation_member(c.id, auth.uid())
  ORDER BY cm.joined_at ASC
$$;

REVOKE ALL ON FUNCTION get_group_info(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_group_info(UUID) TO authenticated;
