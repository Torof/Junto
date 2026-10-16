-- ============================================================================
-- 00460 — a…01 (Croix d'Aquila) : son fil a perdu son message d'ouverture en
-- 00459 (il était attribué au mauvais auteur). Marie L., créatrice, ouvre.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.skip_message_push', 'true', true);

  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002',
         'Salut tout le monde ! Rendez-vous au parking de Puy-Chalvin, je serai là un quart d''heure avant.',
         coalesce((SELECT min(m.created_at) FROM messages m WHERE m.conversation_id = c.id), now()) - INTERVAL '3 hours'
  FROM conversations c
  WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000001';
END $$;
