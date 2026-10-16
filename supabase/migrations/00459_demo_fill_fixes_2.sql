-- ============================================================================
-- 00459 — Dernier reliquat de 00457 sur a…01 (Croix d'Aquila) : le créateur de
-- cette sortie démo est le compte réel de l'admin (suffixe « 08 »), pas Hugo P.
-- (d…08). Les 2 messages « créateur » attribués à Hugo n'ont pas d'auteur
-- légitime → supprimés ; ses 2 objets passent à Thomas B., participant réel.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  DELETE FROM messages m
  USING conversations c
  WHERE c.id = m.conversation_id AND c.type = 'activity'
    AND c.activity_id = 'a0000000-0000-4000-a000-000000000001'
    AND m.sender_id = 'd0000000-0000-4000-a000-000000000008';

  UPDATE activity_gear SET user_id = 'd0000000-0000-4000-a000-000000000003'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000001'
    AND user_id = 'd0000000-0000-4000-a000-000000000008';

  UPDATE conversations c SET last_message_at = m.last_at
  FROM (SELECT conversation_id, max(created_at) AS last_at FROM messages GROUP BY conversation_id) m
  WHERE m.conversation_id = c.id AND c.type = 'activity'
    AND c.activity_id = 'a0000000-0000-4000-a000-000000000001';
END $$;
