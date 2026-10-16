-- ============================================================================
-- 00451 — get_my_conversations expose `initiated_from` (messagerie pro, go
-- Scott 2026-10-16).
--
-- Un pro qui accepte une réservation obtient un DM retagué
-- initiated_from = 'booking' (00418), mais la liste des conversations ne le
-- disait pas : dans la messagerie un client ressemblait à n'importe quel
-- contact, et l'Espace pro n'avait ni compteur ni vue de ses clients.
--
-- Base live : 00413 (DROP + CREATE, type de retour modifié → même geste ici,
-- sinon PGRST203). Corps reproduit à l'identique + une colonne terminale
-- `initiated_from TEXT`. Aucune chaîne d'autorisation modifiée : même
-- membership, même rideau démo, mêmes blocages. La valeur n'apprend rien que
-- les deux parties ne sachent déjà (elles ont vécu la réservation).
-- ============================================================================

DROP FUNCTION IF EXISTS get_my_conversations();
CREATE FUNCTION get_my_conversations()
RETURNS TABLE (
  id UUID, type TEXT, status TEXT,
  last_message_at TIMESTAMPTZ, created_at TIMESTAMPTZ,
  last_message_content TEXT, last_message_sender_id UUID, last_message_metadata JSONB,
  is_unread BOOLEAN,
  user_1 UUID, user_2 UUID,
  other_user_id UUID, other_user_name TEXT, other_user_avatar TEXT, other_user_reliability_tier TEXT,
  name TEXT, icon TEXT, member_count INTEGER,
  activity_id UUID, activity_title TEXT, sport_id UUID, photo_url TEXT,
  initiated_from TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.type, c.status, c.last_message_at, c.created_at,
    lm.content, lm.sender_id, lm.metadata,
    EXISTS (
      SELECT 1 FROM messages m
      WHERE m.conversation_id = c.id
        AND m.deleted_at IS NULL
        AND m.sender_id IS DISTINCT FROM auth.uid()
        AND private.message_author_visible(c.id, m.sender_id, auth.uid())
        AND (me.last_read_at IS NULL OR m.created_at > me.last_read_at)
    ) AS is_unread,
    c.user_1, c.user_2,
    CASE WHEN c.type = 'dm' THEN (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END) END,
    CASE WHEN c.type = 'dm' THEN COALESCE(pp.display_name, '?') END,
    CASE WHEN c.type = 'dm' THEN pp.avatar_url END,
    CASE WHEN c.type = 'dm' THEN pp.reliability_tier END,
    CASE WHEN c.type IN ('group', 'channel') THEN c.name END,
    CASE WHEN c.type = 'group' THEN c.icon END,
    CASE WHEN c.type IN ('group', 'channel') THEN (SELECT count(*)::int FROM conversation_members gm WHERE gm.conversation_id = c.id) END,
    CASE WHEN c.type = 'activity' THEN c.activity_id END,
    CASE WHEN c.type = 'activity' THEN act.title END,
    CASE WHEN c.type = 'activity' THEN act.sport_id WHEN c.type = 'channel' THEN cs.id END,
    CASE WHEN c.type = 'channel' THEN ch.photo_url END,
    CASE WHEN c.type = 'dm' THEN c.initiated_from END
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON c.type = 'dm' AND pp.id = (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END)
  LEFT JOIN activities act
    ON c.type = 'activity' AND act.id = c.activity_id
  LEFT JOIN channels ch
    ON c.type = 'channel' AND ch.conversation_id = c.id
  LEFT JOIN sports cs
    ON ch.sport_key IS NOT NULL AND cs.key = ch.sport_key
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
      AND private.message_author_visible(m.conversation_id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND (
      (c.type = 'dm' AND c.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
             OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
        ))
      OR c.type = 'group'
      OR c.type = 'channel'
      OR (c.type = 'activity'
          AND act.id IS NOT NULL
          AND act.deleted_at IS NULL
          AND act.is_demo = (SELECT u.is_demo FROM users u WHERE u.id = auth.uid())
          AND (act.status IN ('published', 'in_progress')
               OR act.starts_at > now() - INTERVAL '30 days'))
    )
  ORDER BY COALESCE(c.last_message_at, c.created_at) DESC
$$;
REVOKE ALL ON FUNCTION get_my_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_conversations() TO authenticated;
