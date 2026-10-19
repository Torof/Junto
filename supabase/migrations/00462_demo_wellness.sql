-- ============================================================================
-- 00462 — Demo mode : 15 sorties sur les sept sports de 00461 (Scott
-- 2026-10-19 : « une dizaine, voire une quinzaine d'activités comprenant les
-- nouvelles activités »).
--
--   yoga ×3 · tai-chi ×2 · qi gong ×1 · méditation ×2 · marche nordique ×3 ·
--   kitesurf ×2 · wingfoil ×2 — a0000000-…33→41, tout le 05 (Briançon, Gap,
--   Embrun, Serre-Ponçon, Champsaur, Guillestre, Granon, Ubaye). Créateurs et
--   membres = utilisateurs démo existants, chaque créateur a sa ligne de
--   participation (piège n°3). created_at intercalé entre les sorties
--   existantes → le re-datage mélange tout. Chaque sortie reçoit 2 à 6
--   messages de mur, 2 à 5 objets de matériel, et un transport sur ~70 %.
--   Puis le calendrier « deux sorties par jour » de 00457 est ré-appliqué.
-- Push coupé pendant l'insertion (junto.skip_message_push). Tout is_demo.
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  PERFORM set_config('junto.skip_message_push', 'true', true);

  -- ---------- (1) Sorties ----------
  INSERT INTO activities
    (id, creator_id, sport_id, title, description, level, level_max,
     max_participants, location_meeting, meeting_name, meeting_locality,
     location_objective, objective_name,
     starts_at, duration, visibility, requires_presence, status,
     distance_km, elevation_gain_m, is_demo, created_at)
  VALUES
    ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000006',
     (SELECT id FROM sports WHERE key = 'yoga'),
     'Yoga au parc de la Schappe',
     'Séance douce sur l''herbe, vinyasa tranquille puis étirements. Tapis à amener, débutants bienvenus.',
     'Tous niveaux', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.645, 44.895), 4326)::geography, 'Entrée du parc de la Schappe', 'Briançon',
     NULL, NULL,
     now() + INTERVAL '30 days', INTERVAL '75 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000005') + INTERVAL '40 minutes'),
    ('a0000000-0000-4000-a000-000000000034', 'd0000000-0000-4000-a000-000000000012',
     (SELECT id FROM sports WHERE key = 'yoga'),
     'Yoga face au lac, plan d''eau d''Embrun',
     'Hatha yoga au bord de l''eau, rythme lent, on finit par une relaxation au soleil.',
     'Tous niveaux', NULL, 10,
     ST_SetSRID(ST_MakePoint(6.5, 44.555), 4326)::geography, 'Pelouse du plan d''eau', 'Embrun',
     NULL, NULL,
     now() + INTERVAL '31 days', INTERVAL '75 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000007') + INTERVAL '41 minutes'),
    ('a0000000-0000-4000-a000-000000000035', 'd0000000-0000-4000-a000-000000000016',
     (SELECT id FROM sports WHERE key = 'yoga'),
     'Salutations au soleil au lac de Pelleautier',
     'Rendez-vous tôt pour une séance énergique au lever du jour, puis café partagé.',
     'débutant', 'intermédiaire', 8,
     ST_SetSRID(ST_MakePoint(6.02, 44.52), 4326)::geography, 'Parking du lac', 'Pelleautier',
     NULL, NULL,
     now() + INTERVAL '32 days', INTERVAL '60 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000009') + INTERVAL '42 minutes'),
    ('a0000000-0000-4000-a000-000000000036', 'd0000000-0000-4000-a000-00000000000a',
     (SELECT id FROM sports WHERE key = 'tai-chi'),
     'Tai-chi au domaine de Charance',
     'Forme courte de style Yang dans les jardins, on reprend les premiers mouvements ensemble.',
     'Tous niveaux', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.05, 44.575), 4326)::geography, 'Parking du domaine', 'Gap',
     NULL, NULL,
     now() + INTERVAL '33 days', INTERVAL '60 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000b') + INTERVAL '43 minutes'),
    ('a0000000-0000-4000-a000-000000000037', 'd0000000-0000-4000-a000-000000000002',
     (SELECT id FROM sports WHERE key = 'tai-chi'),
     'Tai-chi sur le Champ de Mars',
     'Pratique calme en haut de la vieille ville, vue sur les forts. Venez en tenue souple.',
     'débutant', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.638, 44.898), 4326)::geography, 'Place du Champ de Mars', 'Briançon',
     NULL, NULL,
     now() + INTERVAL '34 days', INTERVAL '60 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000d') + INTERVAL '44 minutes'),
    ('a0000000-0000-4000-a000-000000000038', 'd0000000-0000-4000-a000-00000000000e',
     (SELECT id FROM sports WHERE key = 'qi-gong'),
     'Qi gong au bord de la Durance',
     'Les huit pièces de brocart, pieds dans l''herbe au bord de l''eau. Respiration et lenteur.',
     'Tous niveaux', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.655, 44.655), 4326)::geography, 'Berges de la Durance, pont de Guillestre', 'Guillestre',
     NULL, NULL,
     now() + INTERVAL '35 days', INTERVAL '60 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000f') + INTERVAL '45 minutes'),
    ('a0000000-0000-4000-a000-000000000039', 'd0000000-0000-4000-a000-00000000000d',
     (SELECT id FROM sports WHERE key = 'meditation'),
     'Méditation au lever du soleil, col du Granon',
     'On monte en voiture dans la nuit, assise silencieuse de 30 minutes face aux Écrins, puis thé chaud.',
     'Tous niveaux', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.6, 44.96), 4326)::geography, 'Col du Granon', 'Saint-Chaffrey',
     NULL, NULL,
     now() + INTERVAL '36 days', INTERVAL '90 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000011') + INTERVAL '46 minutes'),
    ('a0000000-0000-4000-a000-00000000003a', 'd0000000-0000-4000-a000-000000000009',
     (SELECT id FROM sports WHERE key = 'meditation'),
     'Marche méditative en forêt de Boscodon',
     'Alternance de marche lente en silence et d''assises sous les sapins. Rythme très doux.',
     'Tous niveaux', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.46, 44.53), 4326)::geography, 'Abbaye de Boscodon', 'Crots',
     NULL, NULL,
     now() + INTERVAL '37 days', INTERVAL '120 minutes', 'public', true, 'published',
     3, 100, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000013') + INTERVAL '47 minutes'),
    ('a0000000-0000-4000-a000-00000000003b', 'd0000000-0000-4000-a000-000000000017',
     (SELECT id FROM sports WHERE key = 'nordic-walking'),
     'Marche nordique au plateau de Bayard',
     'Boucle roulante sur le plateau, bonne allure, bâtons obligatoires. Deux paires de prêt.',
     'intermédiaire', NULL, 10,
     ST_SetSRID(ST_MakePoint(6.08, 44.62), 4326)::geography, 'Parking du golf de Bayard', 'Gap',
     NULL, NULL,
     now() + INTERVAL '38 days', INTERVAL '120 minutes', 'public', true, 'published',
     10, 200, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000015') + INTERVAL '48 minutes'),
    ('a0000000-0000-4000-a000-00000000003c', 'd0000000-0000-4000-a000-00000000000b',
     (SELECT id FROM sports WHERE key = 'nordic-walking'),
     'Marche nordique, baie de Chanteloube',
     'Sentier au bord de Serre-Ponçon, quelques montées courtes, retour par la plage.',
     'débutant', 'intermédiaire', 10,
     ST_SetSRID(ST_MakePoint(6.3, 44.52), 4326)::geography, 'Parking de la baie', 'Chorges',
     NULL, NULL,
     now() + INTERVAL '39 days', INTERVAL '105 minutes', 'public', true, 'published',
     8, 150, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000017') + INTERVAL '49 minutes'),
    ('a0000000-0000-4000-a000-00000000003d', 'd0000000-0000-4000-a000-000000000013',
     (SELECT id FROM sports WHERE key = 'nordic-walking'),
     'Marche nordique dans le Champsaur',
     'Chemins entre les haies bocagères, allure soutenue, vue sur le Vieux Chaillol.',
     'intermédiaire', 'avancé', 8,
     ST_SetSRID(ST_MakePoint(6.08, 44.68), 4326)::geography, 'Place de la mairie', 'Saint-Bonnet-en-Champsaur',
     NULL, NULL,
     now() + INTERVAL '40 days', INTERVAL '135 minutes', 'public', true, 'published',
     12, 300, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000019') + INTERVAL '50 minutes'),
    ('a0000000-0000-4000-a000-00000000003e', 'd0000000-0000-4000-a000-000000000015',
     (SELECT id FROM sports WHERE key = 'kitesurfing'),
     'Kite à Savines, thermique de l''après-midi',
     'On gréé vers 13 h quand le thermique rentre. Spot de la plage, eau plate le long de la rive.',
     'intermédiaire', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.4, 44.53), 4326)::geography, 'Plage de Savines', 'Savines-le-Lac',
     NULL, NULL,
     now() + INTERVAL '41 days', INTERVAL '180 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001b') + INTERVAL '51 minutes'),
    ('a0000000-0000-4000-a000-00000000003f', 'd0000000-0000-4000-a000-000000000018',
     (SELECT id FROM sports WHERE key = 'kitesurfing'),
     'Session kite à la baie Saint-Michel',
     'Navigation autour de la chapelle, vent de sud-ouest annoncé, on surveille les rafales.',
     'avancé', NULL, 5,
     ST_SetSRID(ST_MakePoint(6.33, 44.51), 4326)::geography, 'Parking de la baie Saint-Michel', 'Prunières',
     NULL, NULL,
     now() + INTERVAL '42 days', INTERVAL '180 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001d') + INTERVAL '52 minutes'),
    ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000011',
     (SELECT id FROM sports WHERE key = 'wingfoil'),
     'Wingfoil au plan d''eau d''Embrun',
     'Mise à l''eau facile, on travaille les premiers vols. Une aile de 5 m à prêter.',
     'débutant', 'intermédiaire', 6,
     ST_SetSRID(ST_MakePoint(6.5, 44.56), 4326)::geography, 'Base nautique du plan d''eau', 'Embrun',
     NULL, NULL,
     now() + INTERVAL '43 days', INTERVAL '150 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001f') + INTERVAL '53 minutes'),
    ('a0000000-0000-4000-a000-000000000041', 'd0000000-0000-4000-a000-000000000014',
     (SELECT id FROM sports WHERE key = 'wingfoil'),
     'Wing au lac du Lauzet',
     'Petit lac abrité, parfait pour progresser sans clapot. Combinaison conseillée.',
     'intermédiaire', NULL, 5,
     ST_SetSRID(ST_MakePoint(6.435, 44.43), 4326)::geography, 'Plage du lac', 'Le Lauzet-Ubaye',
     NULL, NULL,
     now() + INTERVAL '44 days', INTERVAL '150 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000021') + INTERVAL '54 minutes')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO participations (activity_id, user_id, status)
  SELECT x.activity_id, x.user_id, 'accepted' FROM (VALUES
    ('a0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000034'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-000000000034'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
    ('a0000000-0000-4000-a000-000000000034'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000034'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000035'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000035'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-000000000035'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-000000000035'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-000000000036'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-000000000036'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000036'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-000000000036'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-000000000037'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000037'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000037'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000038'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-000000000038'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-000000000038'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
    ('a0000000-0000-4000-a000-000000000039'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000039'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-000000000039'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000039'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-00000000003a'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
    ('a0000000-0000-4000-a000-00000000003a'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-00000000003a'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-00000000003a'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-00000000003b'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-00000000003b'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-00000000003b'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-00000000003b'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000003b'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
    ('a0000000-0000-4000-a000-00000000003c'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-00000000003c'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
    ('a0000000-0000-4000-a000-00000000003c'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-00000000003c'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-00000000003d'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
    ('a0000000-0000-4000-a000-00000000003d'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-00000000003d'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-00000000003d'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-00000000003e'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-00000000003e'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-00000000003e'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
    ('a0000000-0000-4000-a000-00000000003e'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-00000000003f'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
    ('a0000000-0000-4000-a000-00000000003f'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-00000000003f'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000040'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-000000000040'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-000000000040'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
    ('a0000000-0000-4000-a000-000000000040'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000041'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000041'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-000000000041'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid)
  ) AS x(activity_id, user_id)
  ON CONFLICT DO NOTHING;

  -- ---------- (2) Chat ----------
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Salut tout le monde ! Rendez-vous à « Entrée du parc de la Schappe », je serai là un quart d''heure avant.', now() - INTERVAL '82 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000033';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Je peux amener un thermos de tisane pour la fin.', now() - INTERVAL '79 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000033';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Super idée, merci !', now() - INTERVAL '73 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000033';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'On fait quoi s''il pleut ?', now() - INTERVAL '72 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000033';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'S''il pleut on se replie sous le préau juste à côté.', now() - INTERVAL '68 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000033';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Ça marche, à très vite !', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000033';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Hello ! Pour le départ : à « Pelouse du plan d''eau ». On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '81 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000034';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Je peux amener un thermos de tisane pour la fin.', now() - INTERVAL '72 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000034';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Super idée, merci !', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000034';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Parfait, hâte d''y être !', now() - INTERVAL '60 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000034';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Salut ! Petit rappel du rendez-vous : au parking du lac. La météo a l''air bonne pour l''instant.', now() - INTERVAL '81 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000035';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'On fait quoi s''il pleut ?', now() - INTERVAL '80 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000035';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'S''il pleut on se replie sous le préau juste à côté.', now() - INTERVAL '75 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000035';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Parfait, hâte d''y être !', now() - INTERVAL '73 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000035';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Hello ! Pour le départ : au parking du domaine. On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '52 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000036';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'C''est ok pour une grande débutante ?', now() - INTERVAL '46 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000036';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Oui, tout le monde est bienvenu, on adapte.', now() - INTERVAL '43 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000036';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'On fait quoi s''il pleut ?', now() - INTERVAL '35 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000036';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'S''il pleut on se replie sous le préau juste à côté.', now() - INTERVAL '32 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000036';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Salut tout le monde ! Rendez-vous à « Place du Champ de Mars », je serai là un quart d''heure avant.', now() - INTERVAL '75 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000037';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Nickel, je prépare mes affaires ce soir.', now() - INTERVAL '66 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000037';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Hello ! Pour le départ : à « Berges de la Durance, pont de Guillestre ». On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '93 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000038';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'C''est ok pour une grande débutante ?', now() - INTERVAL '85 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000038';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Oui, tout le monde est bienvenu, on adapte.', now() - INTERVAL '82 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000038';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'On fait quoi s''il pleut ?', now() - INTERVAL '81 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000038';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'S''il pleut on se replie sous le préau juste à côté.', now() - INTERVAL '76 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000038';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Bienvenue ! Le point de rendez-vous est à « Col du Granon ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '57 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000039';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'On fait quoi s''il pleut ?', now() - INTERVAL '50 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000039';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'S''il pleut on se replie sous le préau juste à côté.', now() - INTERVAL '45 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000039';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Je n''ai pas de tapis, quelqu''un en a un en plus ?', now() - INTERVAL '43 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000039';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'J''ai deux tapis de prêt, pas de souci.', now() - INTERVAL '38 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000039';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Hello ! Pour le départ : à « Abbaye de Boscodon ». On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '94 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'On fait quoi s''il pleut ?', now() - INTERVAL '91 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'S''il pleut on se replie sous le préau juste à côté.', now() - INTERVAL '82 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Nickel, je prépare mes affaires ce soir.', now() - INTERVAL '74 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Bienvenue ! Le point de rendez-vous est au parking du golf de Bayard. N''hésitez pas si vous avez des questions.', now() - INTERVAL '104 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000f', 'Quelqu''un passe par Veynes ? Je peux prendre deux personnes.', now() - INTERVAL '102 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Compte une dizaine de kilomètres, plat ou presque.', now() - INTERVAL '98 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Nickel, je prépare mes affaires ce soir.', now() - INTERVAL '93 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Salut tout le monde ! Rendez-vous au parking de la baie, je serai là un quart d''heure avant.', now() - INTERVAL '70 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Ça fait combien de kilomètres au total ?', now() - INTERVAL '64 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Ça marche, merci pour le covoit !', now() - INTERVAL '55 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Hello ! Pour le départ : à « Place de la mairie ». On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '55 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Vous avez des bâtons de prêt ? Je n''en ai jamais fait.', now() - INTERVAL '52 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Deux paires de prêt dans le coffre, on vous montre la technique au départ.', now() - INTERVAL '49 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Ça fait combien de kilomètres au total ?', now() - INTERVAL '41 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Ça marche, merci pour le covoit !', now() - INTERVAL '38 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Bienvenue ! Le point de rendez-vous est à « Plage de Savines ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Ça marche, à très vite !', now() - INTERVAL '61 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Salut tout le monde ! Rendez-vous au parking de la baie Saint-Michel, je serai là un quart d''heure avant.', now() - INTERVAL '81 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Le vent est annoncé comment ? Je prends la 9 ou la 12 ?', now() - INTERVAL '77 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', '15 à 20 nœuds annoncés, la 9 devrait suffire.', now() - INTERVAL '69 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Il y a de la place pour gréer sur la plage ?', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Oui, large à cette saison, on sera tranquilles.', now() - INTERVAL '56 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000003f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Hello ! Pour le départ : à « Base nautique du plan d''eau ». On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '72 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000040';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Parfait, hâte d''y être !', now() - INTERVAL '68 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000040';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Hello ! Pour le départ : à « Plage du lac ». On commence pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '78 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000041';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Quelqu''un a une pompe dans le coffre ?', now() - INTERVAL '76 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000041';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'J''ai la pompe, pas de souci.', now() - INTERVAL '69 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000041';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Il y a de la place pour gréer sur la plage ?', now() - INTERVAL '68 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000041';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Oui, large à cette saison, on sera tranquilles.', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000041';

  UPDATE conversations c SET last_message_at = m.last_at
  FROM (SELECT conversation_id, max(created_at) AS last_at FROM messages GROUP BY conversation_id) m
  WHERE m.conversation_id = c.id AND c.type = 'activity'
    AND c.activity_id IN ('a0000000-0000-4000-a000-000000000033', 'a0000000-0000-4000-a000-000000000034', 'a0000000-0000-4000-a000-000000000035', 'a0000000-0000-4000-a000-000000000036', 'a0000000-0000-4000-a000-000000000037', 'a0000000-0000-4000-a000-000000000038', 'a0000000-0000-4000-a000-000000000039', 'a0000000-0000-4000-a000-00000000003a', 'a0000000-0000-4000-a000-00000000003b', 'a0000000-0000-4000-a000-00000000003c', 'a0000000-0000-4000-a000-00000000003d', 'a0000000-0000-4000-a000-00000000003e', 'a0000000-0000-4000-a000-00000000003f', 'a0000000-0000-4000-a000-000000000040', 'a0000000-0000-4000-a000-000000000041');

  -- ---------- (3) Matériel ----------
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES
    ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000007', 'Tapis de prêt', 2, true),
    ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000006', 'Plaid', 1, false),
    ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000002', 'Enceinte', 1, true),
    ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000007', 'Brique de yoga', 2, true),
    ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000004', 'Thermos de tisane', 1, true),
    ('a0000000-0000-4000-a000-000000000034', 'd0000000-0000-4000-a000-00000000000b', 'Enceinte', 1, true),
    ('a0000000-0000-4000-a000-000000000034', 'd0000000-0000-4000-a000-000000000012', 'Coussin de méditation', 1, false),
    ('a0000000-0000-4000-a000-000000000035', 'd0000000-0000-4000-a000-00000000000a', 'Coussin de méditation', 1, false),
    ('a0000000-0000-4000-a000-000000000035', 'd0000000-0000-4000-a000-000000000011', 'Thermos de tisane', 1, true),
    ('a0000000-0000-4000-a000-000000000035', 'd0000000-0000-4000-a000-000000000011', 'Tapis', 1, false),
    ('a0000000-0000-4000-a000-000000000036', 'd0000000-0000-4000-a000-000000000011', 'Enceinte', 1, true),
    ('a0000000-0000-4000-a000-000000000036', 'd0000000-0000-4000-a000-000000000017', 'Plaid', 1, false),
    ('a0000000-0000-4000-a000-000000000037', 'd0000000-0000-4000-a000-000000000006', 'Thermos de tisane', 1, true),
    ('a0000000-0000-4000-a000-000000000037', 'd0000000-0000-4000-a000-000000000002', 'Plaid', 1, false),
    ('a0000000-0000-4000-a000-000000000037', 'd0000000-0000-4000-a000-000000000006', 'Enceinte', 1, true),
    ('a0000000-0000-4000-a000-000000000038', 'd0000000-0000-4000-a000-00000000000c', 'Enceinte', 1, true),
    ('a0000000-0000-4000-a000-000000000038', 'd0000000-0000-4000-a000-00000000000e', 'Thermos de tisane', 1, true),
    ('a0000000-0000-4000-a000-000000000038', 'd0000000-0000-4000-a000-000000000013', 'Plaid', 1, false),
    ('a0000000-0000-4000-a000-000000000039', 'd0000000-0000-4000-a000-000000000003', 'Plaid', 1, false),
    ('a0000000-0000-4000-a000-000000000039', 'd0000000-0000-4000-a000-00000000000d', 'Tapis', 1, false),
    ('a0000000-0000-4000-a000-000000000039', 'd0000000-0000-4000-a000-000000000007', 'Coussin de méditation', 1, false),
    ('a0000000-0000-4000-a000-00000000003a', 'd0000000-0000-4000-a000-000000000015', 'Thermos de tisane', 1, true),
    ('a0000000-0000-4000-a000-00000000003a', 'd0000000-0000-4000-a000-000000000015', 'Plaid', 1, false),
    ('a0000000-0000-4000-a000-00000000003a', 'd0000000-0000-4000-a000-000000000009', 'Coussin de méditation', 1, false),
    ('a0000000-0000-4000-a000-00000000003b', 'd0000000-0000-4000-a000-000000000017', 'Coupe-vent', 1, false),
    ('a0000000-0000-4000-a000-00000000003b', 'd0000000-0000-4000-a000-000000000011', 'Barres à partager', 6, true),
    ('a0000000-0000-4000-a000-00000000003b', 'd0000000-0000-4000-a000-000000000017', 'Bâtons de prêt', 2, true),
    ('a0000000-0000-4000-a000-00000000003b', 'd0000000-0000-4000-a000-000000000016', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-00000000003c', 'd0000000-0000-4000-a000-000000000012', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-00000000003c', 'd0000000-0000-4000-a000-00000000000b', 'Barres à partager', 6, true),
    ('a0000000-0000-4000-a000-00000000003c', 'd0000000-0000-4000-a000-000000000016', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-00000000003d', 'd0000000-0000-4000-a000-000000000017', 'Bâtons de marche nordique', 1, false),
    ('a0000000-0000-4000-a000-00000000003d', 'd0000000-0000-4000-a000-000000000013', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-00000000003d', 'd0000000-0000-4000-a000-00000000000c', 'Coupe-vent', 1, false),
    ('a0000000-0000-4000-a000-00000000003d', 'd0000000-0000-4000-a000-000000000013', 'Bâtons de prêt', 2, true),
    ('a0000000-0000-4000-a000-00000000003d', 'd0000000-0000-4000-a000-000000000017', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-00000000003e', 'd0000000-0000-4000-a000-00000000000b', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-00000000003e', 'd0000000-0000-4000-a000-00000000000b', 'Planche', 1, false),
    ('a0000000-0000-4000-a000-00000000003e', 'd0000000-0000-4000-a000-00000000000b', 'Leash', 1, false),
    ('a0000000-0000-4000-a000-00000000003e', 'd0000000-0000-4000-a000-000000000018', 'Aile 9 m', 1, false),
    ('a0000000-0000-4000-a000-00000000003f', 'd0000000-0000-4000-a000-000000000018', 'Aile 9 m', 1, false),
    ('a0000000-0000-4000-a000-00000000003f', 'd0000000-0000-4000-a000-000000000015', 'Aile 12 m', 1, false),
    ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000009', 'Combinaison', 1, false),
    ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000009', 'Aile de wing 5 m de prêt', 1, true),
    ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000009', 'Pompe', 1, true),
    ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000009', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000041', 'd0000000-0000-4000-a000-000000000014', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000041', 'd0000000-0000-4000-a000-000000000014', 'Combinaison', 1, false),
    ('a0000000-0000-4000-a000-000000000041', 'd0000000-0000-4000-a000-000000000014', 'Aile de wing 5 m de prêt', 1, true),
    ('a0000000-0000-4000-a000-000000000041', 'd0000000-0000-4000-a000-00000000000b', 'Leash', 1, false);

  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES
    ('a0000000-0000-4000-a000-000000000033', 'Un tapis en plus', 1, 'd0000000-0000-4000-a000-000000000006'),
    ('a0000000-0000-4000-a000-000000000033', 'Thermos', 2, 'd0000000-0000-4000-a000-000000000006'),
    ('a0000000-0000-4000-a000-000000000035', 'Plaid pour la relaxation', 2, 'd0000000-0000-4000-a000-000000000016'),
    ('a0000000-0000-4000-a000-000000000035', 'Thermos', 1, 'd0000000-0000-4000-a000-000000000016'),
    ('a0000000-0000-4000-a000-000000000036', 'Thermos', 1, 'd0000000-0000-4000-a000-00000000000a'),
    ('a0000000-0000-4000-a000-000000000039', 'Un tapis en plus', 1, 'd0000000-0000-4000-a000-00000000000d'),
    ('a0000000-0000-4000-a000-000000000039', 'Plaid pour la relaxation', 1, 'd0000000-0000-4000-a000-00000000000d'),
    ('a0000000-0000-4000-a000-00000000003b', 'Une paire de bâtons en plus', 2, 'd0000000-0000-4000-a000-000000000017'),
    ('a0000000-0000-4000-a000-00000000003b', 'Trousse de secours', 2, 'd0000000-0000-4000-a000-000000000017'),
    ('a0000000-0000-4000-a000-00000000003d', 'Trousse de secours', 1, 'd0000000-0000-4000-a000-000000000013'),
    ('a0000000-0000-4000-a000-00000000003e', 'Casque', 2, 'd0000000-0000-4000-a000-000000000015'),
    ('a0000000-0000-4000-a000-000000000040', 'Combinaison 5/4 en prêt', 1, 'd0000000-0000-4000-a000-000000000011')
  ON CONFLICT DO NOTHING;

  -- ---------- (4) Transport ----------
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000033') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000033' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000002', 'pending', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000033') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000033' AND user_id = 'd0000000-0000-4000-a000-000000000004';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000004', 'accepted', 'Depuis Briançon', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000037') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000037' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000037', 'd0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000002', 'accepted', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Saint-Bonnet-en-Champsaur', transport_from_lng = 6.078, transport_from_lat = 44.682,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000038') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000038' AND user_id = 'd0000000-0000-4000-a000-000000000013';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000038', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000013', 'accepted', 'Depuis Guillestre', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000038', 'd0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000013', 'pending', 'Depuis Guillestre', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000039') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000039' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000039', 'd0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000005', 'accepted', 'Depuis Briançon', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000039', 'd0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000005', 'pending', 'Depuis Briançon', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-000000000039' AND user_id = 'd0000000-0000-4000-a000-000000000007';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Barcelonnette', transport_from_lng = 6.651, transport_from_lat = 44.387,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000003a') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000003a' AND user_id = 'd0000000-0000-4000-a000-000000000015';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003a', 'd0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000015', 'accepted', 'Depuis Embrun', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003a', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000015', 'pending', 'Depuis Chorges', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Embrun', transport_from_lng = 6.495, transport_from_lat = 44.564,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000003a') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000003a' AND user_id = 'd0000000-0000-4000-a000-000000000009';
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000003b') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000003b' AND user_id = 'd0000000-0000-4000-a000-000000000011';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003b', 'd0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000011', 'accepted', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-00000000003b' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000003b' AND user_id = 'd0000000-0000-4000-a000-000000000017';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Embrun', transport_from_lng = 6.495, transport_from_lat = 44.564,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000003c') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000003c' AND user_id = 'd0000000-0000-4000-a000-000000000009';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003c', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000009', 'accepted', 'Depuis Chorges', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-00000000003c' AND user_id = 'd0000000-0000-4000-a000-000000000012';
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-00000000003c' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Modane', transport_from_lng = 6.659, transport_from_lat = 45.195,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000003e') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000003e' AND user_id = 'd0000000-0000-4000-a000-000000000018';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003e', 'd0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000018', 'accepted', 'Depuis Barcelonnette', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000003e' AND user_id = 'd0000000-0000-4000-a000-00000000000b';
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-00000000003e' AND user_id = 'd0000000-0000-4000-a000-000000000014';
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Modane', transport_from_lng = 6.659, transport_from_lat = 45.195,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000003f') - INTERVAL '30 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000003f' AND user_id = 'd0000000-0000-4000-a000-000000000018';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003f', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000018', 'accepted', 'Depuis Chorges', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000003f', 'd0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000018', 'pending', 'Depuis Barcelonnette', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Embrun', transport_from_lng = 6.495, transport_from_lat = 44.564,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000040') - INTERVAL '30 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000040' AND user_id = 'd0000000-0000-4000-a000-000000000012';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000012', 'pending', 'Depuis Embrun', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000040', 'd0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-000000000012', 'pending', 'Depuis Gap', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000040') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000040' AND user_id = 'd0000000-0000-4000-a000-000000000011';
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Barcelonnette', transport_from_lng = 6.651, transport_from_lat = 44.387,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000041') - INTERVAL '30 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000041' AND user_id = 'd0000000-0000-4000-a000-000000000015';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000041', 'd0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000015', 'accepted', 'Depuis Vars', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-000000000041' AND user_id = 'd0000000-0000-4000-a000-00000000000b';

  -- ---------- (5) Re-datage : miroir de admin_set_demo_mode (00457, deux sorties par jour) ----------
  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM activities
    WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
  ),
  target AS (
    SELECT a.id, a.starts_at AS old_start,
           date_trunc('day', now())
             + make_interval(
                 days  => (1 + ((o.rn - 1) / 2))::int,
                 hours => (ARRAY[9,14,8,16,10,17,11,15])[((o.rn - 1) % 8) + 1],
                 mins  => (ARRAY[0,30,15,0,45,30,0,30])[((o.rn - 1) % 8) + 1]
               ) AS new_start
    FROM activities a JOIN ordered o ON o.id = a.id
  ),
  shifted_transport AS (
    UPDATE participations p
    SET transport_departs_at = p.transport_departs_at + (t.new_start - t.old_start)
    FROM target t
    WHERE p.activity_id = t.id AND p.transport_departs_at IS NOT NULL
    RETURNING p.id
  ),
  shifted_pickups AS (
    UPDATE seat_requests s
    SET requested_pickup_at = s.requested_pickup_at + (t.new_start - t.old_start)
    FROM target t
    WHERE s.activity_id = t.id AND s.requested_pickup_at IS NOT NULL
    RETURNING s.id
  )
  UPDATE activities a
  SET starts_at = t.new_start, status = 'published'
  FROM target t
  WHERE a.id = t.id;
END $$;
