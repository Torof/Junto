-- ============================================================================
-- 00466 — Demo mode : 15 sorties de plus, serrées autour de Briançon (Scott
-- 2026-10-21 : test de surcharge d'une zone). Saint-Chaffrey, Villard-Saint-
-- Pancrace, La Vachette, Puy-Saint-André : chaque sortie sur un point distinct,
-- toutes dans un rayon de ~5 km. a0000000-…5b→69. Même remplissage et même
-- réécriture de séquence que 00465, calendrier deux-par-jour ré-appliqué.
-- ============================================================================
DO $$
DECLARE v_base TIMESTAMPTZ;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  PERFORM set_config('junto.skip_message_push', 'true', true);
  SELECT min(created_at) INTO v_base FROM activities WHERE is_demo AND id::text LIKE 'a0000000-%';

  INSERT INTO activities (id, creator_id, sport_id, title, description, level, level_max, max_participants, location_meeting, meeting_name, meeting_locality, location_objective, objective_name, starts_at, duration, visibility, requires_presence, status, distance_km, elevation_gain_m, is_demo, created_at) VALUES
    ('a0000000-0000-4000-a000-00000000005b', 'd0000000-0000-4000-a000-000000000002', (SELECT id FROM sports WHERE key = 'hiking'), 'Boucle des forts par les Salettes', 'Petite boucle entre les forts Vauban, tranquille, belle lumière en fin de journée.', 'débutant', NULL, 10, ST_SetSRID(ST_MakePoint(6.65, 44.895), 4326)::geography, 'Porte de Pignerol', 'Briançon', NULL, NULL, now() + INTERVAL '90 days', INTERVAL '150 minutes', 'public', true, 'published', 6, 350, true, v_base),
    ('a0000000-0000-4000-a000-00000000005c', 'd0000000-0000-4000-a000-000000000005', (SELECT id FROM sports WHERE key = 'climbing-sport'), 'Couenne au-dessus de La Vachette', 'Petit secteur ensoleillé, voies de 5b à 6b, approche de dix minutes.', 'intermédiaire', NULL, 6, ST_SetSRID(ST_MakePoint(6.68, 44.916), 4326)::geography, 'Parking du hameau', 'La Vachette', NULL, NULL, now() + INTERVAL '91 days', INTERVAL '210 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-000000000006', (SELECT id FROM sports WHERE key = 'yoga'), 'Yoga au bord de la Durance, pont d''Asfeld', 'Séance lente au pied du pont, bruit de l''eau, relaxation finale.', 'Tous niveaux', NULL, 10, ST_SetSRID(ST_MakePoint(6.6475, 44.9005), 4326)::geography, 'Pont d''Asfeld', 'Briançon', NULL, NULL, now() + INTERVAL '92 days', INTERVAL '75 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-00000000005e', 'd0000000-0000-4000-a000-000000000007', (SELECT id FROM sports WHERE key = 'running'), 'Footing au pont de Cervières', 'Sortie courte et vallonnée par les gorges de la Cerveyrette.', 'intermédiaire', NULL, 10, ST_SetSRID(ST_MakePoint(6.656, 44.889), 4326)::geography, 'Pont de Cervières', 'Briançon', NULL, NULL, now() + INTERVAL '93 days', INTERVAL '60 minutes', 'public', true, 'published', 7, 200, true, v_base),
    ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-00000000000d', (SELECT id FROM sports WHERE key = 'mtb-xc'), 'VTT dans la forêt de Saint-Chaffrey', 'Boucle XC sous les mélèzes, single tracks roulants et une montée sèche.', 'intermédiaire', NULL, 8, ST_SetSRID(ST_MakePoint(6.6, 44.928), 4326)::geography, 'Église de Saint-Chaffrey', 'Saint-Chaffrey', NULL, NULL, now() + INTERVAL '94 days', INTERVAL '150 minutes', 'public', true, 'published', 22, 600, true, v_base),
    ('a0000000-0000-4000-a000-000000000060', 'd0000000-0000-4000-a000-000000000003', (SELECT id FROM sports WHERE key = 'bouldering'), 'Blocs du Puy-Saint-André', 'Quelques blocs au soleil au-dessus de Briançon, du 4 au 6c.', 'Tous niveaux', NULL, 8, ST_SetSRID(ST_MakePoint(6.618, 44.887), 4326)::geography, 'Parking du village', 'Puy-Saint-André', NULL, NULL, now() + INTERVAL '95 days', INTERVAL '180 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-000000000061', 'd0000000-0000-4000-a000-000000000004', (SELECT id FROM sports WHERE key = 'nordic-walking'), 'Marche nordique à Villard-Saint-Pancrace', 'Chemins le long de la Durance, allure soutenue, bâtons de prêt.', 'débutant', 'intermédiaire', 10, ST_SetSRID(ST_MakePoint(6.633, 44.872), 4326)::geography, 'Mairie', 'Villard-Saint-Pancrace', NULL, NULL, now() + INTERVAL '96 days', INTERVAL '105 minutes', 'public', true, 'published', 9, 150, true, v_base),
    ('a0000000-0000-4000-a000-000000000062', 'd0000000-0000-4000-a000-000000000008', (SELECT id FROM sports WHERE key = 'trail-running'), 'Trail de Saint-Chaffrey au col du Granon', 'Grosse montée régulière, retour par les crêtes si le vent le permet.', 'avancé', NULL, 8, ST_SetSRID(ST_MakePoint(6.607, 44.924), 4326)::geography, 'Place du village', 'Saint-Chaffrey', ST_SetSRID(ST_MakePoint(6.6, 44.96), 4326)::geography, 'Col du Granon', now() + INTERVAL '97 days', INTERVAL '180 minutes', 'public', true, 'published', 18, 1300, true, v_base),
    ('a0000000-0000-4000-a000-000000000063', 'd0000000-0000-4000-a000-00000000000d', (SELECT id FROM sports WHERE key = 'climbing-multipitch'), 'Grande voie sous la Croix de Toulouse', 'Quatre longueurs faciles au-dessus de la ville, parfait pour débuter en grande voie.', 'débutant', 'intermédiaire', 4, ST_SetSRID(ST_MakePoint(6.637, 44.909), 4326)::geography, 'Départ du sentier de la Croix', 'Briançon', NULL, NULL, now() + INTERVAL '98 days', INTERVAL '240 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-000000000064', 'd0000000-0000-4000-a000-000000000002', (SELECT id FROM sports WHERE key = 'hiking'), 'Fort du Randouillet par le pont d''Asfeld', 'Montée courte et raide vers le fort, panorama sur les trois vallées.', 'intermédiaire', NULL, 10, ST_SetSRID(ST_MakePoint(6.661, 44.904), 4326)::geography, 'Pont d''Asfeld, rive gauche', 'Briançon', ST_SetSRID(ST_MakePoint(6.665, 44.906), 4326)::geography, 'Fort du Randouillet', now() + INTERVAL '99 days', INTERVAL '150 minutes', 'public', true, 'published', 5, 400, true, v_base),
    ('a0000000-0000-4000-a000-000000000065', 'd0000000-0000-4000-a000-00000000000e', (SELECT id FROM sports WHERE key = 'meditation'), 'Méditation au jardin de la Schappe', 'Assise guidée de vingt minutes puis marche lente sous les arbres.', 'Tous niveaux', NULL, 8, ST_SetSRID(ST_MakePoint(6.641, 44.892), 4326)::geography, 'Jardin de la Schappe', 'Briançon', NULL, NULL, now() + INTERVAL '100 days', INTERVAL '60 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-000000000066', 'd0000000-0000-4000-a000-000000000014', (SELECT id FROM sports WHERE key = 'cycling'), 'La Vachette, Montgenèvre', 'Montée régulière jusqu''au col, retour par la vallée de la Clarée.', 'intermédiaire', NULL, 10, ST_SetSRID(ST_MakePoint(6.677, 44.911), 4326)::geography, 'Arrêt de bus de La Vachette', 'La Vachette', ST_SetSRID(ST_MakePoint(6.723, 44.931), 4326)::geography, 'Montgenèvre', now() + INTERVAL '101 days', INTERVAL '180 minutes', 'public', true, 'published', 40, 900, true, v_base),
    ('a0000000-0000-4000-a000-000000000067', 'd0000000-0000-4000-a000-000000000005', (SELECT id FROM sports WHERE key = 'paragliding'), 'Vol sur Serre Chevalier, atterro Chantemerle', 'Déco au sommet du téléphérique, vol de fin d''après-midi, atterro au village.', 'intermédiaire', NULL, 4, ST_SetSRID(ST_MakePoint(6.59, 44.935), 4326)::geography, 'Télécabine de Chantemerle', 'Saint-Chaffrey', NULL, NULL, now() + INTERVAL '102 days', INTERVAL '150 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-000000000068', 'd0000000-0000-4000-a000-000000000006', (SELECT id FROM sports WHERE key = 'qi-gong'), 'Qi gong au bord de la Guisane', 'Les huit pièces de brocart sur la berge, pieds dans l''herbe.', 'Tous niveaux', NULL, 8, ST_SetSRID(ST_MakePoint(6.612, 44.919), 4326)::geography, 'Pont de la Guisane', 'Saint-Chaffrey', NULL, NULL, now() + INTERVAL '103 days', INTERVAL '60 minutes', 'public', true, 'published', NULL, NULL, true, v_base),
    ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-000000000007', (SELECT id FROM sports WHERE key = 'gravel'), 'Gravel par Villard et les Ayes', 'Pistes forestières vers le vallon des Ayes, quelques passages raides.', 'intermédiaire', NULL, 8, ST_SetSRID(ST_MakePoint(6.627, 44.88), 4326)::geography, 'Église de Villard-Saint-Pancrace', 'Villard-Saint-Pancrace', ST_SetSRID(ST_MakePoint(6.64, 44.83), 4326)::geography, 'Vallon des Ayes', now() + INTERVAL '104 days', INTERVAL '180 minutes', 'public', true, 'published', 30, 800, true, v_base)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO participations (activity_id, user_id, status) SELECT x.a, x.u, 'accepted' FROM (VALUES
    ('a0000000-0000-4000-a000-00000000005b'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-00000000005b'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-00000000005b'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-00000000005b'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-00000000005c'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-00000000005c'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-00000000005c'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-00000000005d'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-00000000005d'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-00000000005d'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-00000000005d'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-00000000005d'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-00000000005e'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-00000000005e'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-00000000005e'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-00000000005e'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-00000000005f'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-00000000005f'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-00000000005f'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-00000000005f'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000060'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-000000000060'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000060'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000060'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000061'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000061'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000061'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000061'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000062'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-000000000062'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000062'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000063'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000063'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-000000000063'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000064'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000064'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000064'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-000000000064'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000065'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-000000000065'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-000000000065'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000066'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000066'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000066'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000066'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000067'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000067'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000067'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-000000000068'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000068'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000068'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-000000000069'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000069'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000069'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000069'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid)
  ) AS x(a, u) ON CONFLICT DO NOTHING;

  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Salut tout le monde ! Rendez-vous à « Porte de Pignerol », je serai là un quart d''heure avant.', now() - INTERVAL '113 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Top, merci pour l''orga !', now() - INTERVAL '105 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005b';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005b', 'd0000000-0000-4000-a000-000000000002', 'Gilet d''hydratation', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005b', 'd0000000-0000-4000-a000-000000000006', 'Thermos de thé', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005b', 'd0000000-0000-4000-a000-000000000007', 'Barres et gels à partager', 6, true);
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Salut tout le monde ! Rendez-vous au parking du hameau, je serai là un quart d''heure avant.', now() - INTERVAL '80 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '72 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Avec deux cordes et une vingtaine de dégaines on est larges.', now() - INTERVAL '64 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Top, merci pour l''orga !', now() - INTERVAL '55 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005c';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005c', 'd0000000-0000-4000-a000-000000000005', 'Crashpad', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005c', 'd0000000-0000-4000-a000-000000000005', 'Chaussons', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005c', 'd0000000-0000-4000-a000-000000000003', 'Corde 70 m', 1, true);
  UPDATE participations SET transport_type = 'car', transport_seats = 2, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000005c') - INTERVAL '30 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-00000000005c' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-00000000005c', 'd0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000005', 'pending', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.') ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-00000000005c', 'd0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000005', 'pending', 'Depuis Briançon', 'Une place pour moi ? Je participe à l’essence.') ON CONFLICT DO NOTHING;
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Hello ! Pour le départ : à « Pont d''Asfeld ». On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '68 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Je n''ai pas de tapis, quelqu''un en a un en plus ?', now() - INTERVAL '59 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'J''ai deux tapis de prêt, pas de souci.', now() - INTERVAL '54 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Ça marche, à très vite !', now() - INTERVAL '45 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005d';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-00000000000e', 'Plaid', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-000000000002', 'Brique de yoga', 2, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-000000000002', 'Thermos de tisane', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-000000000006', 'Coussin de méditation', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-00000000000e', 'Tapis de prêt', 2, true);
  UPDATE participations SET transport_type = 'car', transport_seats = 2, transport_from_name = 'Guillestre', transport_from_lng = 6.65, transport_from_lat = 44.66, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000005d') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-00000000005d' AND user_id = 'd0000000-0000-4000-a000-00000000000e';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-00000000005d', 'd0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-00000000000e', 'accepted', 'Depuis Briançon', 'Je prends une place si c’est encore possible ?') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-00000000005d' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-00000000005d' AND user_id = 'd0000000-0000-4000-a000-000000000004';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Salut tout le monde ! Rendez-vous à « Pont de Cervières », je serai là un quart d''heure avant.', now() - INTERVAL '65 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Quelqu''un passe par Briançon ? Je peux prendre deux personnes.', now() - INTERVAL '59 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '52 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Il reste de la neige là-haut ou ça passe en chaussures ?', now() - INTERVAL '43 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '41 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005e';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005e', 'd0000000-0000-4000-a000-000000000005', 'Trousse de secours', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005e', 'd0000000-0000-4000-a000-000000000008', 'Frontale', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005e', 'd0000000-0000-4000-a000-000000000007', 'Carte IGN du secteur', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005e', 'd0000000-0000-4000-a000-000000000007', 'Gilet d''hydratation', 1, false);
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-00000000005e', 'Carte IGN du secteur', 2, 'd0000000-0000-4000-a000-000000000007') ON CONFLICT DO NOTHING;
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-00000000005e', 'Thermos de thé', 1, 'd0000000-0000-4000-a000-000000000007') ON CONFLICT DO NOTHING;
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Salut ! Petit rappel du rendez-vous : à « Église de Saint-Chaffrey ». La météo a l''air bonne pour l''instant.', now() - INTERVAL '54 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'On est en combien pour la navette ?', now() - INTERVAL '45 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Deux voitures pour la navette, on verra sur place.', now() - INTERVAL '43 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000005f';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-00000000000d', 'Barres', 6, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-00000000000d', 'Casque', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-000000000014', 'Lumières', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-000000000005', 'Chambres à air', 2, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-00000000000d', 'Kit tubeless', 1, true);
  UPDATE participations SET transport_type = 'car', transport_seats = 4, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000005f') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-00000000005f' AND user_id = 'd0000000-0000-4000-a000-000000000008';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-00000000005f', 'd0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000008', 'pending', 'Depuis Vars', 'Je prends une place si c’est encore possible ?') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000005f' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Salut tout le monde ! Rendez-vous au parking du village, je serai là un quart d''heure avant.', now() - INTERVAL '111 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000060';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Quelqu''un a un casque en rab ? Le mien est resté chez ma sœur.', now() - INTERVAL '102 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000060';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '98 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000060';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '97 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000060';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Avec deux cordes et une vingtaine de dégaines on est larges.', now() - INTERVAL '96 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000060';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000060', 'd0000000-0000-4000-a000-000000000006', 'Baudrier', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000060', 'd0000000-0000-4000-a000-00000000000d', 'Casque', 1, false);
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Salut ! Petit rappel du rendez-vous : à « Mairie ». La météo a l''air bonne pour l''instant.', now() - INTERVAL '81 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000061';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'C''est quelle allure à peu près ?', now() - INTERVAL '78 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000061';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Allure tranquille, on discute en marchant.', now() - INTERVAL '73 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000061';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Parfait, hâte d''y être !', now() - INTERVAL '68 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000061';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000061', 'd0000000-0000-4000-a000-000000000007', 'Bâtons de marche nordique', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000061', 'd0000000-0000-4000-a000-000000000004', 'Gilet d''hydratation', 1, false);
  UPDATE participations SET transport_type = 'car', transport_seats = 4, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000061') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000061' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000061', 'd0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000002', 'accepted', 'Depuis Briançon', 'Une place pour moi ? Je participe à l’essence.') ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000061', 'd0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000002', 'accepted', 'Depuis Briançon', 'Une place pour moi ? Je participe à l’essence.') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000061') - INTERVAL '30 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000061' AND user_id = 'd0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Place du village ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '64 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000062';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Parfait, hâte d''y être !', now() - INTERVAL '57 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000062';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000062', 'd0000000-0000-4000-a000-00000000000d', 'Gilet d''hydratation', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000062', 'd0000000-0000-4000-a000-00000000000d', 'Couverture de survie', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000062', 'd0000000-0000-4000-a000-00000000000d', 'Frontale', 1, false);
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Salut ! Petit rappel du rendez-vous : à « Départ du sentier de la Croix ». La météo a l''air bonne pour l''instant.', now() - INTERVAL '96 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000063';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '93 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000063';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Avec deux cordes et une vingtaine de dégaines on est larges.', now() - INTERVAL '90 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000063';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000063', 'd0000000-0000-4000-a000-00000000000d', 'Longe de via ferrata', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000063', 'd0000000-0000-4000-a000-00000000000d', 'Dégaines', 12, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000063', 'd0000000-0000-4000-a000-000000000003', 'Casque', 1, false);
  UPDATE participations SET transport_type = 'car', transport_seats = 3, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000063') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000063' AND user_id = 'd0000000-0000-4000-a000-00000000000d';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000063', 'd0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000d', 'accepted', 'Depuis Briançon', 'Je prends une place si c’est encore possible ?') ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000063', 'd0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000d', 'accepted', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.') ON CONFLICT DO NOTHING;
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Hello ! Pour le départ : à « Pont d''Asfeld, rive gauche ». On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '62 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000064';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Il reste de la neige là-haut ou ça passe en chaussures ?', now() - INTERVAL '56 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000064';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '51 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000064';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '44 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000064';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000064', 'd0000000-0000-4000-a000-000000000008', 'Trousse de secours', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000064', 'd0000000-0000-4000-a000-000000000004', 'Frontale', 1, false);
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000064', 'Carte IGN du secteur', 2, 'd0000000-0000-4000-a000-000000000002') ON CONFLICT DO NOTHING;
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000064', 'Thermos de thé', 2, 'd0000000-0000-4000-a000-000000000002') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000064') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000064' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000064', 'd0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000002', 'pending', 'Depuis Briançon', 'Je prends une place si c’est encore possible ?') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000064' AND user_id = 'd0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Jardin de la Schappe ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '68 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000065';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Je peux amener un thermos de tisane pour la fin.', now() - INTERVAL '59 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000065';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Super idée, merci !', now() - INTERVAL '56 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000065';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Parfait, hâte d''y être !', now() - INTERVAL '50 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000065';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000065', 'd0000000-0000-4000-a000-000000000006', 'Thermos de tisane', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000065', 'd0000000-0000-4000-a000-000000000006', 'Tapis de prêt', 2, true);
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000065', 'Thermos', 1, 'd0000000-0000-4000-a000-00000000000e') ON CONFLICT DO NOTHING;
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000065', 'Un tapis en plus', 2, 'd0000000-0000-4000-a000-00000000000e') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000065') - INTERVAL '60 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000065' AND user_id = 'd0000000-0000-4000-a000-000000000006';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000065', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000006', 'accepted', 'Depuis Guillestre', 'Une place pour moi ? Je participe à l’essence.') ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000065', 'd0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000006', 'accepted', 'Depuis Guillestre', 'Je prends une place si c’est encore possible ?') ON CONFLICT DO NOTHING;
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Arrêt de bus de La Vachette ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '87 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000066';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Quelqu''un a une pompe à pied dans le coffre ?', now() - INTERVAL '78 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000066';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Pompe et multi-outil dans mon sac, pas de souci.', now() - INTERVAL '73 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000066';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000066', 'd0000000-0000-4000-a000-00000000000d', 'Barres', 6, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000066', 'd0000000-0000-4000-a000-000000000005', 'Casque', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000066', 'd0000000-0000-4000-a000-000000000007', 'Chambres à air', 2, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000066', 'd0000000-0000-4000-a000-000000000005', 'Kit tubeless', 1, true);
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000066', 'Chambre à air 29"', 1, 'd0000000-0000-4000-a000-000000000014') ON CONFLICT DO NOTHING;
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000066', 'Pompe à pied', 1, 'd0000000-0000-4000-a000-000000000014') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3, transport_from_name = 'Vars', transport_from_lng = 6.684, transport_from_lat = 44.573, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000066') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000066' AND user_id = 'd0000000-0000-4000-a000-000000000014';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000066', 'd0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000014', 'accepted', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000066' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-000000000066' AND user_id = 'd0000000-0000-4000-a000-000000000007';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Salut ! Petit rappel du rendez-vous : à « Télécabine de Chantemerle ». La météo a l''air bonne pour l''instant.', now() - INTERVAL '95 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000067';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Quelqu''un a une radio en plus ?', now() - INTERVAL '94 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000067';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'J''ai deux radios, on se cale sur le canal habituel.', now() - INTERVAL '93 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000067';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000067', 'd0000000-0000-4000-a000-000000000006', 'Radio', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000067', 'd0000000-0000-4000-a000-000000000005', 'Voile', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000067', 'd0000000-0000-4000-a000-000000000006', 'Manche à air', 1, true);
  UPDATE participations SET transport_type = 'car', transport_seats = 2, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000067') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000067' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000067', 'd0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000005', 'accepted', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.') ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000067', 'd0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000005', 'pending', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.') ON CONFLICT DO NOTHING;
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Salut tout le monde ! Rendez-vous à « Pont de la Guisane », je serai là un quart d''heure avant.', now() - INTERVAL '65 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000068';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Je n''ai pas de tapis, quelqu''un en a un en plus ?', now() - INTERVAL '62 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000068';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'J''ai deux tapis de prêt, pas de souci.', now() - INTERVAL '55 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000068';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000068', 'd0000000-0000-4000-a000-000000000006', 'Tapis', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000068', 'd0000000-0000-4000-a000-000000000004', 'Tapis de prêt', 2, true);
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000068', 'Un tapis en plus', 1, 'd0000000-0000-4000-a000-000000000006') ON CONFLICT DO NOTHING;
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Salut tout le monde ! Rendez-vous à « Église de Villard-Saint-Pancrace », je serai là un quart d''heure avant.', now() - INTERVAL '72 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000069';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Vous roulez tubeless ? Je prends le kit au cas où.', now() - INTERVAL '65 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000069';
  INSERT INTO messages (conversation_id, sender_id, content, created_at) SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Tubeless pour moi aussi, un kit à deux ça suffit.', now() - INTERVAL '62 hours' FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000069';
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-000000000008', 'Casque', 1, false);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-000000000008', 'Barres', 6, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-00000000000d', 'Pompe', 1, true);
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-000000000007', 'Bidon de 1 L', 1, false);
  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES ('a0000000-0000-4000-a000-000000000069', 'Multi-outil', 1, 'd0000000-0000-4000-a000-000000000007') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3, transport_from_name = 'Vars', transport_from_lng = 6.684, transport_from_lat = 44.573, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000069') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000069' AND user_id = 'd0000000-0000-4000-a000-000000000014';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000014', 'accepted', 'Depuis Briançon', 'Je prends une place si c’est encore possible ?') ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message) VALUES ('a0000000-0000-4000-a000-000000000069', 'd0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000014', 'accepted', 'Depuis Briançon', 'Une place pour moi ? Je participe à l’essence.') ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4, transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897, transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000069') - INTERVAL '45 minutes' WHERE activity_id = 'a0000000-0000-4000-a000-000000000069' AND user_id = 'd0000000-0000-4000-a000-000000000008';
  UPDATE conversations c SET last_message_at = m.last_at FROM (SELECT conversation_id, max(created_at) AS last_at FROM messages GROUP BY conversation_id) m WHERE m.conversation_id = c.id AND c.type = 'activity' AND c.activity_id IN ('a0000000-0000-4000-a000-00000000005b', 'a0000000-0000-4000-a000-00000000005c', 'a0000000-0000-4000-a000-00000000005d', 'a0000000-0000-4000-a000-00000000005e', 'a0000000-0000-4000-a000-00000000005f', 'a0000000-0000-4000-a000-000000000060', 'a0000000-0000-4000-a000-000000000061', 'a0000000-0000-4000-a000-000000000062', 'a0000000-0000-4000-a000-000000000063', 'a0000000-0000-4000-a000-000000000064', 'a0000000-0000-4000-a000-000000000065', 'a0000000-0000-4000-a000-000000000066', 'a0000000-0000-4000-a000-000000000067', 'a0000000-0000-4000-a000-000000000068', 'a0000000-0000-4000-a000-000000000069');

  -- Séquence propre : les 25 nouvelles réparties uniformément parmi les existantes.
  WITH existing AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn, count(*) OVER () AS n
    FROM activities WHERE is_demo AND deleted_at IS NULL AND id::text LIKE 'a0000000-%'
      AND id::text NOT BETWEEN 'a0000000-0000-4000-a000-00000000005b' AND 'a0000000-0000-4000-a000-000000000069'
  ),
  fresh AS (
    SELECT id, row_number() OVER (ORDER BY id) AS k, count(*) OVER () AS n
    FROM activities WHERE id::text BETWEEN 'a0000000-0000-4000-a000-00000000005b' AND 'a0000000-0000-4000-a000-000000000069'
  ),
  keyed AS (
    SELECT id, rn::numeric / n AS key FROM existing
    UNION ALL SELECT id, (k - 0.5)::numeric / n FROM fresh
  ),
  seq AS (SELECT id, row_number() OVER (ORDER BY key, id) AS r FROM keyed)
  UPDATE activities a SET created_at = v_base + make_interval(mins => s.r::int)
  FROM seq s WHERE a.id = s.id;

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
