-- ============================================================================
-- 00368 — Hub unifié (Brique 4a) : get_my_conversations rend les 3 types.
--
-- La 00363 filtrait `c.type = 'dm'` (hub DM-only). On étend la lecture curée aux
-- conversations d'activité et de groupe, avec l'identité par type et les non-lus
-- SERVEUR (last_read_at) — remplace le store local du mur.
--
-- Chaîne de visibilité (validée Scott 2026-08-04) :
--   auth → membre (conversation_members, hidden_at levé à l'arrivée d'un message)
--   → par type : DM active + paire non bloquée (parité 00031) · groupe · activité
--     (jamais deleted_at, rideau démo `is_demo = mien`, rétention 30 j sur starts_at)
--   → is_unread serveur → tri par récence. Lecture seule (pas de rate limit).
-- ============================================================================

-- RETURNS TABLE shape changes → must drop first (42P13).
DROP FUNCTION IF EXISTS get_my_conversations();

CREATE OR REPLACE FUNCTION get_my_conversations()
RETURNS TABLE (
  id UUID, type TEXT, status TEXT,
  last_message_at TIMESTAMPTZ, created_at TIMESTAMPTZ,
  last_message_content TEXT, last_message_sender_id UUID, last_message_metadata JSONB,
  is_unread BOOLEAN,
  -- DM
  user_1 UUID, user_2 UUID,
  other_user_id UUID, other_user_name TEXT, other_user_avatar TEXT, other_user_reliability_tier TEXT,
  -- groupe
  name TEXT, icon TEXT, member_count INTEGER,
  -- activité
  activity_id UUID, activity_title TEXT, sport_id UUID
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
        AND (me.last_read_at IS NULL OR m.created_at > me.last_read_at)
    ) AS is_unread,
    -- DM
    c.user_1, c.user_2,
    CASE WHEN c.type = 'dm' THEN (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END) END,
    CASE WHEN c.type = 'dm' THEN COALESCE(pp.display_name, '?') END,
    CASE WHEN c.type = 'dm' THEN pp.avatar_url END,
    CASE WHEN c.type = 'dm' THEN pp.reliability_tier END,
    -- groupe
    CASE WHEN c.type = 'group' THEN c.name END,
    CASE WHEN c.type = 'group' THEN c.icon END,
    CASE WHEN c.type = 'group' THEN (SELECT count(*)::int FROM conversation_members gm WHERE gm.conversation_id = c.id) END,
    -- activité
    CASE WHEN c.type = 'activity' THEN c.activity_id END,
    CASE WHEN c.type = 'activity' THEN act.title END,
    CASE WHEN c.type = 'activity' THEN act.sport_id END
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON c.type = 'dm' AND pp.id = (CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END)
  LEFT JOIN activities act
    ON c.type = 'activity' AND act.id = c.activity_id
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
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
