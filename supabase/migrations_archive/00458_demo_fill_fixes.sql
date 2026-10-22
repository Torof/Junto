-- ============================================================================
-- 00458 — Corrections de 00457 (vérification post-application).
--
-- (1) Les créateurs des 4 sorties du Briançonnais (a…01→04, époque 00334)
--     n'avaient pas leur ligne de participation → pas membres de leur propre
--     conversation, et « Créées » à 0 sur leur profil (piège n°3 des notes
--     démo). On les insère ; le trigger d'appartenance fait le reste.
-- (2) 00457 a pris le suffixe « 08 » d'un VRAI participant de ces 4 sorties
--     pour Hugo P. (d…08) : 2 messages et 3 objets de matériel lui étaient
--     attribués sur a…02/03/04 où il n'est pas inscrit. Réattribués à des
--     participants réels de chaque sortie (bypass pour sender_id, gelé).
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  PERFORM set_config('junto.skip_message_push', 'true', true);

  -- (1) Creators' own participation rows.
  INSERT INTO participations (activity_id, user_id, status)
  SELECT a.id, a.creator_id, 'accepted'
  FROM activities a
  WHERE a.is_demo AND a.id::text LIKE 'a0000000-%'
    AND NOT EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = a.id AND p.user_id = a.creator_id)
  ON CONFLICT DO NOTHING;

  -- (2) Hugo's misattributed wall messages → Karim on a…02, Léa on a…03.
  UPDATE messages m SET sender_id = 'd0000000-0000-4000-a000-000000000005'
  FROM conversations c
  WHERE c.id = m.conversation_id AND c.type = 'activity'
    AND c.activity_id = 'a0000000-0000-4000-a000-000000000002'
    AND m.sender_id = 'd0000000-0000-4000-a000-000000000008';

  UPDATE messages m SET sender_id = 'd0000000-0000-4000-a000-000000000006'
  FROM conversations c
  WHERE c.id = m.conversation_id AND c.type = 'activity'
    AND c.activity_id = 'a0000000-0000-4000-a000-000000000003'
    AND m.sender_id = 'd0000000-0000-4000-a000-000000000008';

  -- Hugo's gear on outings he is not in → the outing's creator.
  UPDATE activity_gear g SET user_id = a.creator_id
  FROM activities a
  WHERE a.id = g.activity_id
    AND g.user_id = 'd0000000-0000-4000-a000-000000000008'
    AND a.id::text IN ('a0000000-0000-4000-a000-000000000002',
                       'a0000000-0000-4000-a000-000000000003',
                       'a0000000-0000-4000-a000-000000000004');
END $$;
