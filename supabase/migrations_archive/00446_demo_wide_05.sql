-- ============================================================================
-- 00446 — Demo mode élargi (Scott 2026-10-15) : 15 nouveaux faux comptes et
-- 20 nouvelles sorties à venir, éparses sur tout le 05 et autour (Gap, Serre-
-- Ponçon, Buëch, Queyras, Dévoluy, Valgaudemar, Vars, Ubaye, Montgenèvre,
-- Maurienne, Bardonecchia). Aucune nouvelle sortie dans le Briançonnais, qui
-- en a déjà quatre.
--
-- Même mécanique que 00334/00415/00438 :
--   (1) auth.users à UUID fixe → trigger → identité posée sous bypass
--       (portrait, bio, sports déclarés + niveaux, is_demo).
--   (2) 12 sorties d'HISTORIQUE terminées (c0000000-…28→33) avec présences
--       EXPLICITES (jamais NULL : le sweep expirerait l'historique), 2 retraits
--       tardifs → la fiabilité est DÉRIVÉE par la vraie formule, paliers variés
--       (Lukas faible, Marta moyenne, Youssef un oubli).
--   (3) Votes de traits comptés pour Inès (ponctuelle), Mathieu (préparé),
--       Baptiste (prudent), Anaïs (conciliante).
--   (4) 20 sorties à venir (a0000000-…05→18), rendez-vous AVEC commune
--       (00441), 1 à 4 participants démo acceptés + la ligne du créateur.
--   (5) admin_set_demo_mode (live 00415, reconstruite intégralement) : le
--       re-datage passe d'une sortie tous les 2 jours à une par jour — avec 24
--       sorties la carte vit un mois au lieu de sept semaines. Appliqué tout de
--       suite, pas besoin de re-basculer le mode.
-- Coordonnées de rendez-vous estimées (comme 00334) — Scott corrige sur
-- l'appareil si un pin est décalé. Tout est is_demo = true (rideau admin).
-- ============================================================================

-- ---------- (1) Comptes ----------
INSERT INTO auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000000a', 'authenticated', 'authenticated', 'demo.ines@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000000b', 'authenticated', 'authenticated', 'demo.mathieu@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000000c', 'authenticated', 'authenticated', 'demo.sofia@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000000d', 'authenticated', 'authenticated', 'demo.lukas@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000000e', 'authenticated', 'authenticated', 'demo.anais@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000000f', 'authenticated', 'authenticated', 'demo.remi@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000010', 'authenticated', 'authenticated', 'demo.chloe@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000011', 'authenticated', 'authenticated', 'demo.youssef@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000012', 'authenticated', 'authenticated', 'demo.elise@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000013', 'authenticated', 'authenticated', 'demo.baptiste@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000014', 'authenticated', 'authenticated', 'demo.marta@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000015', 'authenticated', 'authenticated', 'demo.antoine@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000016', 'authenticated', 'authenticated', 'demo.noor@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000017', 'authenticated', 'authenticated', 'demo.pierre-yves@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000018', 'authenticated', 'authenticated', 'demo.hanna@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}')
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.users u SET
    display_name     = d.display_name,
    avatar_url       = d.avatar_url,
    bio              = d.bio,
    sports           = d.sports,
    levels_per_sport = d.levels,
    is_demo          = true
  FROM (VALUES
    ('d0000000-0000-4000-a000-00000000000a'::uuid, 'Inès F.', 'https://randomuser.me/api/portraits/women/5.jpg', 'Trail et course à pied autour de Gap. Lève-tôt, sorties avant le boulot.', '["trail-running", "running"]'::jsonb, '{"trail-running": "avancé", "running": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-00000000000b'::uuid, 'Mathieu G.', 'https://randomuser.me/api/portraits/men/12.jpg', 'Kayak et paddle sur Serre-Ponçon dès que le vent tombe.', '["kayaking", "stand-up-paddle", "swimming"]'::jsonb, '{"kayaking": "intermédiaire", "stand-up-paddle": "intermédiaire", "swimming": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-00000000000c'::uuid, 'Sofia R.', 'https://randomuser.me/api/portraits/women/12.jpg', 'Da Oulx — rando, raquettes et ski de rando des deux côtés de la frontière.', '["hiking", "snowshoeing", "ski-touring"]'::jsonb, '{"hiking": "avancé", "snowshoeing": "intermédiaire", "ski-touring": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-00000000000d'::uuid, 'Lukas W.', 'https://randomuser.me/api/portraits/men/23.jpg', 'Saisonnier à Serre-Che, VTT enduro l''été, snowboard l''hiver.', '["mtb-xc", "mtb-enduro"]'::jsonb, '{"mtb-xc": "avancé", "mtb-enduro": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-00000000000e'::uuid, 'Anaïs C.', 'https://randomuser.me/api/portraits/women/27.jpg', 'Queyras de cœur. Rando, trek et trail, jamais sans carte papier.', '["hiking", "trekking", "trail-running"]'::jsonb, '{"hiking": "avancé", "trekking": "avancé", "trail-running": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-00000000000f'::uuid, 'Rémi T.', 'https://randomuser.me/api/portraits/men/33.jpg', 'Gravel et route dans le Buëch. Cols au lever du jour.', '["gravel", "cycling"]'::jsonb, '{"gravel": "avancé", "cycling": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000010'::uuid, 'Chloé D.', 'https://randomuser.me/api/portraits/women/44.jpg', 'Parapente à Chabre, rando quand ça ne vole pas.', '["paragliding", "hiking"]'::jsonb, '{"paragliding": "intermédiaire", "hiking": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000011'::uuid, 'Youssef A.', 'https://randomuser.me/api/portraits/men/52.jpg', 'Grimpeur gapençais : Céüse, Orpierre, blocs quand il pleut.', '["climbing-sport", "bouldering", "climbing-multipitch"]'::jsonb, '{"climbing-sport": "avancé", "bouldering": "intermédiaire", "climbing-multipitch": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000012'::uuid, 'Élise P.', 'https://randomuser.me/api/portraits/women/60.jpg', 'Windsurf et voile à Savines, du printemps à l''automne.', '["windsurfing", "sailing"]'::jsonb, '{"windsurfing": "avancé", "sailing": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000013'::uuid, 'Baptiste H.', 'https://randomuser.me/api/portraits/men/61.jpg', 'Alpinisme et ski de rando dans le Champsaur et le Valgaudemar.', '["mountaineering", "ski-touring", "via-ferrata"]'::jsonb, '{"mountaineering": "avancé", "ski-touring": "avancé", "via-ferrata": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000014'::uuid, 'Marta S.', 'https://randomuser.me/api/portraits/women/68.jpg', 'Temporada en Vars — enduro l''été, snowboard l''hiver.', '["mtb-enduro", "snowboarding"]'::jsonb, '{"mtb-enduro": "intermédiaire", "snowboarding": "avancé"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000015'::uuid, 'Antoine M.', 'https://randomuser.me/api/portraits/men/84.jpg', 'Eau vive dans l''Ubaye : rafting, canyon, kayak.', '["rafting", "canyoning", "kayaking"]'::jsonb, '{"rafting": "avancé", "canyoning": "avancé", "kayaking": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000016'::uuid, 'Noor B.', 'https://randomuser.me/api/portraits/women/8.jpg', 'Course, vélo, natation en lac dès que l''eau passe 16°. Gapençaise.', '["running", "swimming", "cycling"]'::jsonb, '{"running": "intermédiaire", "swimming": "avancé", "cycling": "intermédiaire"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000017'::uuid, 'Pierre-Yves L.', 'https://randomuser.me/api/portraits/men/90.jpg', 'Dévoluy : via ferrata, grandes voies, un peu de spéléo.', '["via-ferrata", "climbing-multipitch", "caving"]'::jsonb, '{"via-ferrata": "avancé", "climbing-multipitch": "avancé", "caving": "débutant"}'::jsonb),
    ('d0000000-0000-4000-a000-000000000018'::uuid, 'Hanna K.', 'https://randomuser.me/api/portraits/women/37.jpg', 'Modane. Trail en Maurienne, rando quand les jambes disent stop.', '["trail-running", "hiking"]'::jsonb, '{"trail-running": "avancé", "hiking": "intermédiaire"}'::jsonb)
  ) AS d(id, display_name, avatar_url, bio, sports, levels)
  WHERE u.id = d.id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- (2) Historique terminé ----------
INSERT INTO activities
  (id, creator_id, sport_id, title, description, level, level_max,
   max_participants, location_meeting, meeting_name, meeting_locality,
   location_objective, objective_name,
   starts_at, duration, visibility, requires_presence, status,
   distance_km, elevation_gain_m, is_demo)
VALUES
  ('c0000000-0000-4000-a000-000000000028', 'd0000000-0000-4000-a000-00000000000a',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Trail de Charance',
   'Montée au pic par les balcons, retour par le domaine.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.056, 44.585), 4326)::geography, 'Domaine de Charance', 'Gap',
   ST_SetSRID(ST_MakePoint(6.03, 44.59), 4326)::geography, 'Pic de Charance',
   now() - INTERVAL '200 days', INTERVAL '150 minutes', 'public', true, 'completed',
   14, 700, true),
  ('c0000000-0000-4000-a000-000000000029', 'd0000000-0000-4000-a000-00000000000b',
   (SELECT id FROM sports WHERE key = 'kayaking'),
   'Kayak au coucher du soleil',
   'Baie de Chanteloube, eau plate, retour à la frontale.',
   'débutant', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.325, 44.515), 4326)::geography, 'Baie de Chanteloube', 'Chorges',
   NULL, NULL,
   now() - INTERVAL '90 days', INTERVAL '180 minutes', 'public', true, 'completed',
   NULL, NULL, true),
  ('c0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-00000000000c',
   (SELECT id FROM sports WHERE key = 'snowshoeing'),
   'Raquettes au col de l''Échelle',
   'Montée douce depuis Névache, neige froide, grand soleil.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.613, 45.027), 4326)::geography, 'Névache', 'Névache',
   ST_SetSRID(ST_MakePoint(6.655, 45.04), 4326)::geography, 'Col de l''Échelle',
   now() - INTERVAL '240 days', INTERVAL '300 minutes', 'public', true, 'completed',
   10, 450, true),
  ('c0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-00000000000d',
   (SELECT id FROM sports WHERE key = 'mtb-enduro'),
   'Enduro au bike park de Serre-Che',
   'Journée remontées, pistes rouges et noires.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.567, 44.921), 4326)::geography, 'Chantemerle', 'Saint-Chaffrey',
   NULL, NULL,
   now() - INTERVAL '110 days', INTERVAL '360 minutes', 'public', true, 'completed',
   NULL, NULL, true),
  ('c0000000-0000-4000-a000-00000000002c', 'd0000000-0000-4000-a000-00000000000e',
   (SELECT id FROM sports WHERE key = 'trekking'),
   'Tour du Queyras — étape du col Agnel',
   'Molines → refuge Agnel, longue étape avec vue sur le Viso.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.845, 44.725), 4326)::geography, 'Molines-en-Queyras', 'Molines-en-Queyras',
   ST_SetSRID(ST_MakePoint(6.979, 44.684), 4326)::geography, 'Col Agnel',
   now() - INTERVAL '140 days', INTERVAL '480 minutes', 'public', true, 'completed',
   18, 1200, true),
  ('c0000000-0000-4000-a000-00000000002d', 'd0000000-0000-4000-a000-00000000000f',
   (SELECT id FROM sports WHERE key = 'gravel'),
   'Gravel par le col de Cabre',
   'Boucle Veynes – Cabre – Aspres, pistes roulantes.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(5.815, 44.535), 4326)::geography, 'Gare de Veynes', 'Veynes',
   ST_SetSRID(ST_MakePoint(5.605, 44.64), 4326)::geography, 'Col de Cabre',
   now() - INTERVAL '60 days', INTERVAL '300 minutes', 'public', true, 'completed',
   78, 1100, true),
  ('c0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-000000000010',
   (SELECT id FROM sports WHERE key = 'paragliding'),
   'Marche-vol au Morgon',
   'Montée au Morgon, décollage sud, posé à Savines.',
   'intermédiaire', NULL, 5,
   ST_SetSRID(ST_MakePoint(6.405, 44.525), 4326)::geography, 'Savines-le-Lac', 'Savines-le-Lac',
   ST_SetSRID(ST_MakePoint(6.42, 44.47), 4326)::geography, 'Pic de Morgon',
   now() - INTERVAL '75 days', INTERVAL '300 minutes', 'public', true, 'completed',
   NULL, NULL, true),
  ('c0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-000000000011',
   (SELECT id FROM sports WHERE key = 'bouldering'),
   'Session blocs à Céüse',
   'Blocs au pied de la falaise, crash pads en commun.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(5.945, 44.505), 4326)::geography, 'Parking des Guérins', 'Sigoyer',
   NULL, NULL,
   now() - INTERVAL '45 days', INTERVAL '240 minutes', 'public', true, 'completed',
   NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-000000000012',
   (SELECT id FROM sports WHERE key = 'sailing'),
   'Régate amicale à Savines',
   'Deux manches sur dériveurs, vent de nord établi.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.4, 44.53), 4326)::geography, 'Base nautique de Savines', 'Savines-le-Lac',
   NULL, NULL,
   now() - INTERVAL '100 days', INTERVAL '240 minutes', 'public', true, 'completed',
   NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000013',
   (SELECT id FROM sports WHERE key = 'mountaineering'),
   'Arête nord du Pic d''Olan',
   'Course d''arête, cordée de trois, départ 4h du refuge.',
   'expert', NULL, 3,
   ST_SetSRID(ST_MakePoint(6.233, 44.82), 4326)::geography, 'Refuge du Gioberney', 'La Chapelle-en-Valgaudemar',
   ST_SetSRID(ST_MakePoint(6.185, 44.84), 4326)::geography, 'Pic d''Olan',
   now() - INTERVAL '160 days', INTERVAL '720 minutes', 'public', true, 'completed',
   NULL, 1400, true),
  ('c0000000-0000-4000-a000-000000000032', 'd0000000-0000-4000-a000-000000000015',
   (SELECT id FROM sports WHERE key = 'rafting'),
   'Rafting sur l''Ubaye, parcours classique',
   'Le Lauzet → Le Martinet, classe III, bonne ambiance.',
   'débutant', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.435, 44.43), 4326)::geography, 'Le Lauzet-Ubaye', 'Le Lauzet-Ubaye',
   NULL, NULL,
   now() - INTERVAL '80 days', INTERVAL '180 minutes', 'public', true, 'completed',
   NULL, NULL, true),
  ('c0000000-0000-4000-a000-000000000033', 'd0000000-0000-4000-a000-000000000018',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Trail du col du Fréjus',
   'Montée régulière depuis Modane, retour par la forêt.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.66, 45.195), 4326)::geography, 'Modane gare', 'Modane',
   ST_SetSRID(ST_MakePoint(6.69, 45.12), 4326)::geography, 'Col du Fréjus',
   now() - INTERVAL '30 days', INTERVAL '240 minutes', 'public', true, 'completed',
   20, 1400, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO participations (activity_id, user_id, status)
SELECT x.activity_id, x.user_id, 'accepted' FROM (VALUES
  ('c0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('c0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('c0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('c0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
  ('c0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('c0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
  ('c0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('c0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
  ('c0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('c0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('c0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('c0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('c0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('c0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
  ('c0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('c0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
  ('c0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('c0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('c0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('c0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('c0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
  ('c0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('c0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('c0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('c0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-000000000010'::uuid),
  ('c0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('c0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('c0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
  ('c0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('c0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
  ('c0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('c0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
  ('c0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('c0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('c0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-000000000010'::uuid),
  ('c0000000-0000-4000-a000-000000000031'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('c0000000-0000-4000-a000-000000000031'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('c0000000-0000-4000-a000-000000000031'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('c0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
  ('c0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('c0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('c0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
  ('c0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
  ('c0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('c0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('c0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('c0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid)
) AS x(activity_id, user_id)
ON CONFLICT (user_id, activity_id) DO NOTHING;

INSERT INTO participations (activity_id, user_id, status, left_at, left_reason, created_at)
SELECT p.activity_id, p.user_id, 'withdrawn', a.starts_at - INTERVAL '2 hours', 'Empêchement de dernière minute', a.starts_at - INTERVAL '9 days'
FROM (VALUES
  ('c0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('c0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid)
) AS p(activity_id, user_id)
JOIN activities a ON a.id = p.activity_id
ON CONFLICT (user_id, activity_id) DO NOTHING;

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations p SET confirmed_present = true
  FROM activities a
  WHERE a.id = p.activity_id AND a.is_demo = true
    AND a.id::text BETWEEN 'c0000000-0000-4000-a000-000000000028' AND 'c0000000-0000-4000-a000-000000000033'
    AND p.status = 'accepted' AND p.confirmed_present IS NULL;
  UPDATE participations p SET confirmed_present = false
  FROM (VALUES
    ('c0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('c0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('c0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('c0000000-0000-4000-a000-000000000033'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid)
  ) AS x(activity_id, user_id)
  WHERE p.activity_id = x.activity_id AND p.user_id = x.user_id AND p.status = 'accepted';
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- (3) Votes de traits comptés ----------
INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, counted_at, created_at)
SELECT v.voter, v.voted, v.activity, v.badge, a.starts_at + a.duration + INTERVAL '26 hours', a.starts_at + a.duration + INTERVAL '5 hours'
FROM (VALUES
  ('d0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid, 'c0000000-0000-4000-a000-000000000028'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid, 'c0000000-0000-4000-a000-000000000028'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-00000000000f'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid, 'c0000000-0000-4000-a000-00000000002d'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid, 'c0000000-0000-4000-a000-000000000033'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid, 'c0000000-0000-4000-a000-000000000033'::uuid, 'punctual'),
  ('d0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid, 'c0000000-0000-4000-a000-000000000029'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid, 'c0000000-0000-4000-a000-000000000029'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid, 'c0000000-0000-4000-a000-000000000029'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid, 'c0000000-0000-4000-a000-000000000030'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid, 'c0000000-0000-4000-a000-000000000032'::uuid, 'prepared'),
  ('d0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid, 'c0000000-0000-4000-a000-000000000031'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-00000000000e'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid, 'c0000000-0000-4000-a000-000000000031'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid, 'c0000000-0000-4000-a000-00000000002e'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-00000000000c'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid, 'c0000000-0000-4000-a000-00000000002c'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid, 'c0000000-0000-4000-a000-00000000002c'::uuid, 'prudent'),
  ('d0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid, 'c0000000-0000-4000-a000-00000000002c'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-00000000000c'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid, 'c0000000-0000-4000-a000-00000000002c'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid, 'c0000000-0000-4000-a000-00000000002c'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-00000000000d'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid, 'c0000000-0000-4000-a000-00000000002a'::uuid, 'conciliant'),
  ('d0000000-0000-4000-a000-000000000002'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid, 'c0000000-0000-4000-a000-00000000002a'::uuid, 'conciliant')
) AS v(voter, voted, activity, badge)
JOIN activities a ON a.id = v.activity
ON CONFLICT DO NOTHING;

-- ---------- (4) Sorties à venir ----------
INSERT INTO activities
  (id, creator_id, sport_id, title, description, level, level_max,
   max_participants, location_meeting, meeting_name, meeting_locality,
   location_objective, objective_name,
   starts_at, duration, visibility, requires_presence, status,
   distance_km, elevation_gain_m, is_demo)
VALUES
  ('a0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000013',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Lac du Lauzon depuis le Gioberney',
   'Montée en lacets au-dessus du refuge, lac à 2008 m face aux Bans. Rythme tranquille, on prend le temps des photos.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.233, 44.82), 4326)::geography, 'Parking du Gioberney', 'La Chapelle-en-Valgaudemar',
   ST_SetSRID(ST_MakePoint(6.245, 44.806), 4326)::geography, 'Lac du Lauzon',
   now() + INTERVAL '2 days', INTERVAL '300 minutes', 'public', true, 'published',
   9, 600, true),
  ('a0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000011',
   (SELECT id FROM sports WHERE key = 'climbing-multipitch'),
   'Grande voie à Céüse',
   'Une classique de la face sud, 6 longueurs en 6a/6b. Cordée de deux ou trois, on part tôt pour l''ombre.',
   'avancé', 'expert', 3,
   ST_SetSRID(ST_MakePoint(5.945, 44.505), 4326)::geography, 'Parking des Guérins', 'Sigoyer',
   ST_SetSRID(ST_MakePoint(5.942, 44.498), 4326)::geography, 'Falaise de Céüse',
   now() + INTERVAL '2 days', INTERVAL '420 minutes', 'public', true, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000b',
   (SELECT id FROM sports WHERE key = 'kayaking'),
   'Kayak dans la baie de Chanteloube',
   'Tour de la baie, pause baignade si l''eau le permet. Kayaks de location possibles sur place.',
   'débutant', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.325, 44.515), 4326)::geography, 'Plage de Chanteloube', 'Chorges',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '180 minutes', 'public', false, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000a',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Trail des balcons de Charance',
   'Montée au pic de Charance par les balcons, descente roulante. Allure 7 min/km en montée, on regroupe aux croisements.',
   'intermédiaire', NULL, 10,
   ST_SetSRID(ST_MakePoint(6.056, 44.585), 4326)::geography, 'Domaine de Charance', 'Gap',
   ST_SetSRID(ST_MakePoint(6.03, 44.59), 4326)::geography, 'Pic de Charance',
   now() + INTERVAL '2 days', INTERVAL '150 minutes', 'public', true, 'published',
   14, 700, true),
  ('a0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000014',
   (SELECT id FROM sports WHERE key = 'mtb-enduro'),
   'Enduro Vars – Risoul',
   'Remontées de Vars puis liaison Risoul, retour par les singles de la forêt. Protections obligatoires.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.684, 44.573), 4326)::geography, 'Vars les Claux', 'Vars',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '240 minutes', 'public', true, 'published',
   30, 1200, true),
  ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000010',
   (SELECT id FROM sports WHERE key = 'paragliding'),
   'Vol rando à Chabre',
   'Montée à pied au décollage sud de Chabre (1h30), vol vers l''atterrissage de Laragne. Brevet et voile perso.',
   'intermédiaire', NULL, 5,
   ST_SetSRID(ST_MakePoint(5.82, 44.315), 4326)::geography, 'Atterrissage de Laragne', 'Laragne-Montéglin',
   ST_SetSRID(ST_MakePoint(5.86, 44.3), 4326)::geography, 'Décollage sud de Chabre',
   now() + INTERVAL '2 days', INTERVAL '240 minutes', 'public', true, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000000f',
   (SELECT id FROM sports WHERE key = 'gravel'),
   'Gravel dans le Buëch',
   'Boucle Veynes – Montmaur – Saint-Julien par les pistes, 65 km et 900 m de D+. Pneus 40 mm minimum.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(5.815, 44.535), 4326)::geography, 'Gare de Veynes', 'Veynes',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '240 minutes', 'public', false, 'published',
   65, 900, true),
  ('a0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000017',
   (SELECT id FROM sports WHERE key = 'via-ferrata'),
   'Via ferrata des gorges d''Agnielles',
   'Parcours au-dessus du torrent, deux ponts de singe. Kit via ferrata perso ou à louer à La Faurie.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(5.81, 44.63), 4326)::geography, 'La Faurie', 'La Faurie',
   ST_SetSRID(ST_MakePoint(5.8, 44.66), 4326)::geography, 'Gorges d''Agnielles',
   now() + INTERVAL '2 days', INTERVAL '210 minutes', 'public', true, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000016',
   (SELECT id FROM sports WHERE key = 'cycling'),
   'Tour du lac de Serre-Ponçon',
   '90 km et 1300 m de D+ par le pont de Savines, Embrun et le barrage. Allure tranquille, pause café à Embrun.',
   'intermédiaire', NULL, 10,
   ST_SetSRID(ST_MakePoint(6.405, 44.525), 4326)::geography, 'Savines-le-Lac', 'Savines-le-Lac',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '300 minutes', 'public', false, 'published',
   90, 1300, true),
  ('a0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000015',
   (SELECT id FROM sports WHERE key = 'rafting'),
   'Rafting sur l''Ubaye',
   'Parcours Le Lauzet → Le Martinet, classe III. Combinaisons fournies par la base, savoir nager.',
   'débutant', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.435, 44.43), 4326)::geography, 'Base de rafting du Lauzet', 'Le Lauzet-Ubaye',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '180 minutes', 'public', false, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-000000000015',
   (SELECT id FROM sports WHERE key = 'canyoning'),
   'Canyon de la Blache',
   'Canyon ludique au-dessus de Serre-Ponçon, sauts et toboggans. Combinaison 5 mm et casque.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.335, 44.53), 4326)::geography, 'Parking de la Blache', 'Prunières',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '240 minutes', 'public', true, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-00000000000e',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Lac de Souliers',
   'Montée depuis le hameau de Souliers, lac et panorama sur le Queyras. Ouverte à tous, pique-nique au lac.',
   'débutant', 'intermédiaire', 10,
   ST_SetSRID(ST_MakePoint(6.78, 44.78), 4326)::geography, 'Hameau de Souliers', 'Arvieux',
   ST_SetSRID(ST_MakePoint(6.76, 44.79), 4326)::geography, 'Lac de Souliers',
   now() + INTERVAL '2 days', INTERVAL '240 minutes', 'public', true, 'published',
   8, 500, true),
  ('a0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-00000000000e',
   (SELECT id FROM sports WHERE key = 'trekking'),
   'Autour du Pain de Sucre, 2 jours',
   'Saint-Véran → refuge Agnel → col Vieux → retour. Nuit en refuge, 28 km et 1800 m de D+ au total.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.87, 44.7), 4326)::geography, 'Saint-Véran', 'Saint-Véran',
   ST_SetSRID(ST_MakePoint(6.98, 44.69), 4326)::geography, 'Pain de Sucre',
   now() + INTERVAL '2 days', INTERVAL '1800 minutes', 'public', true, 'published',
   28, 1800, true),
  ('a0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000011',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Falaise d''Orpierre',
   'Secteur du Belleric, voies du 4 au 6b. Idéal pour une première sortie en falaise.',
   'débutant', 'intermédiaire', 6,
   ST_SetSRID(ST_MakePoint(5.695, 44.313), 4326)::geography, 'Orpierre village', 'Orpierre',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '300 minutes', 'public', false, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-000000000012',
   (SELECT id FROM sports WHERE key = 'windsurfing'),
   'Windsurf à Savines',
   'Session de l''après-midi avec la thermique. Matériel de location à la base.',
   'intermédiaire', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.4, 44.53), 4326)::geography, 'Base nautique de Savines', 'Savines-le-Lac',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '180 minutes', 'public', false, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000016',
   (SELECT id FROM sports WHERE key = 'running'),
   'Footing au plan d''eau d''Embrun',
   'Deux tours du plan d''eau, allure 6 min/km, discussion possible. Ouvert à tous.',
   'débutant', NULL, 12,
   ST_SetSRID(ST_MakePoint(6.5, 44.555), 4326)::geography, 'Plan d''eau d''Embrun', 'Embrun',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '60 minutes', 'public', false, 'published',
   8, 50, true),
  ('a0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-00000000000b',
   (SELECT id FROM sports WHERE key = 'stand-up-paddle'),
   'Paddle au coucher du soleil',
   'Depuis la plage d''Embrun, tour des criques au calme. Planches de location à la base.',
   'débutant', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.5, 44.555), 4326)::geography, 'Plage d''Embrun', 'Embrun',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '120 minutes', 'public', false, 'published',
   NULL, NULL, true),
  ('a0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-000000000018',
   (SELECT id FROM sports WHERE key = 'trail-running'),
   'Mont Thabor depuis Valfréjus',
   'Montée par le vallon du Lavoir, 1600 m de D+. Bonne forme nécessaire, on part à 7h.',
   'avancé', NULL, 6,
   ST_SetSRID(ST_MakePoint(6.64, 45.15), 4326)::geography, 'Valfréjus', 'Modane',
   ST_SetSRID(ST_MakePoint(6.57, 45.12), 4326)::geography, 'Mont Thabor',
   now() + INTERVAL '2 days', INTERVAL '360 minutes', 'public', true, 'published',
   22, 1600, true),
  ('a0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000d',
   (SELECT id FROM sports WHERE key = 'mtb-xc'),
   'VTT Montgenèvre – Clavière',
   'Boucle transfrontalière par les pistes de la Durance et retour par Clavière. 25 km, roulant.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.72, 44.93), 4326)::geography, 'Office de tourisme de Montgenèvre', 'Montgenèvre',
   NULL, NULL,
   now() + INTERVAL '2 days', INTERVAL '180 minutes', 'public', false, 'published',
   25, 700, true),
  ('a0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000c',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Lago Verde depuis Bardonecchia',
   'Montée depuis Pian del Colle au lac, puis mélèzes dorés. Passaporto non richiesto !',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.65, 45.06), 4326)::geography, 'Pian del Colle', 'Bardonecchia',
   ST_SetSRID(ST_MakePoint(6.68, 45.03), 4326)::geography, 'Lago Verde',
   now() + INTERVAL '2 days', INTERVAL '300 minutes', 'public', true, 'published',
   12, 700, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO participations (activity_id, user_id, status)
SELECT x.activity_id, x.user_id, 'accepted' FROM (VALUES
  ('a0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('a0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('a0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('a0000000-0000-4000-a000-000000000005'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('a0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
  ('a0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('a0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
  ('a0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('a0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
  ('a0000000-0000-4000-a000-000000000007'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('a0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('a0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('a0000000-0000-4000-a000-000000000008'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('a0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
  ('a0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('a0000000-0000-4000-a000-000000000009'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('a0000000-0000-4000-a000-00000000000a'::uuid, 'd0000000-0000-4000-a000-000000000010'::uuid),
  ('a0000000-0000-4000-a000-00000000000a'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
  ('a0000000-0000-4000-a000-00000000000b'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
  ('a0000000-0000-4000-a000-00000000000b'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('a0000000-0000-4000-a000-00000000000b'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('a0000000-0000-4000-a000-00000000000c'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('a0000000-0000-4000-a000-00000000000c'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('a0000000-0000-4000-a000-00000000000c'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('a0000000-0000-4000-a000-00000000000d'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('a0000000-0000-4000-a000-00000000000d'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
  ('a0000000-0000-4000-a000-00000000000d'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-00000000000e'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
  ('a0000000-0000-4000-a000-00000000000e'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-00000000000e'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('a0000000-0000-4000-a000-00000000000e'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
  ('a0000000-0000-4000-a000-00000000000f'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
  ('a0000000-0000-4000-a000-00000000000f'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-00000000000f'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
  ('a0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('a0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('a0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('a0000000-0000-4000-a000-000000000010'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
  ('a0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('a0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
  ('a0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('a0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('a0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
  ('a0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('a0000000-0000-4000-a000-000000000012'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
  ('a0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
  ('a0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
  ('a0000000-0000-4000-a000-000000000013'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('a0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('a0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('a0000000-0000-4000-a000-000000000014'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
  ('a0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
  ('a0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
  ('a0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
  ('a0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
  ('a0000000-0000-4000-a000-000000000016'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('a0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('a0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
  ('a0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('a0000000-0000-4000-a000-000000000017'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
  ('a0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
  ('a0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
  ('a0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
  ('a0000000-0000-4000-a000-000000000018'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid)
) AS x(activity_id, user_id)
ON CONFLICT (user_id, activity_id) DO NOTHING;

-- ---------- (5) Re-datage : une sortie par jour (base live 00415, corps complet) ----------
CREATE OR REPLACE FUNCTION admin_set_demo_mode(p_on boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin uuid;
  v_base GEOGRAPHY;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_sports TEXT[];
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE app_config SET value = CASE WHEN p_on THEN 'true' ELSE 'false' END
  WHERE name = 'demo_mode';

  IF p_on THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);

    -- Showcase demo activities only → future dates. The completed HISTORY
    -- (c0000000-…, feeds the rich profiles) is excluded by UUID range so it can
    -- never be dragged into the re-date pool (a status-only guard traps it).
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities
      WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
    )
    UPDATE activities a
    SET starts_at = date_trunc('day', now())
          + make_interval(
              days  => (1 + o.rn)::int, -- 00446 : une sortie par jour (24 sorties → un mois)
              hours => (ARRAY[9,14,11,17,8,16,10,15])[((o.rn - 1) % 8) + 1],
              mins  => (ARRAY[0,30,0,30,15,0,45,30])[((o.rn - 1) % 8) + 1]
            ),
        status = 'published'
    FROM ordered o
    WHERE a.id = o.id;

    -- Demo dispos: each partner keeps ONE of the admin's sports (rotation →
    -- every card matches) + up to 2 of its own flavor sports, on a varied
    -- sub-window of the admin's window, with varied radius/offset per partner.
    SELECT d.base, d.window_start, d.window_end, d.sport_keys
      INTO v_base, v_ws, v_we, v_sports
    FROM discovery_availabilities d
    WHERE d.user_id = v_admin AND d.is_active AND d.is_demo = false;

    IF v_base IS NOT NULL THEN
      WITH ordered AS (
        SELECT id, user_id, row_number() OVER (ORDER BY user_id) AS rn
        FROM discovery_availabilities WHERE is_demo = true
      ),
      flavors(user_id, extras) AS (VALUES
        ('d0000000-0000-4000-a000-000000000002'::uuid, ARRAY['trail-running','hiking']),
        ('d0000000-0000-4000-a000-000000000003'::uuid, ARRAY['climbing-sport','bouldering']),
        ('d0000000-0000-4000-a000-000000000004'::uuid, ARRAY['climbing-multipitch','mountaineering']),
        ('d0000000-0000-4000-a000-000000000005'::uuid, ARRAY['paragliding','hiking']),
        ('d0000000-0000-4000-a000-000000000006'::uuid, ARRAY['via-ferrata','canyoning']),
        ('d0000000-0000-4000-a000-000000000007'::uuid, ARRAY['mtb-enduro','gravel']),
        ('d0000000-0000-4000-a000-000000000008'::uuid, ARRAY['trail-running','running']),
        ('d0000000-0000-4000-a000-000000000009'::uuid, ARRAY['windsurfing','swimming'])
      )
      UPDATE discovery_availabilities dd
      SET sport_keys = (
            ARRAY[v_sports[((o.rn - 1) % cardinality(v_sports)) + 1]]
            || array_remove(COALESCE(f.extras, '{}'::text[]),
                            v_sports[((o.rn - 1) % cardinality(v_sports)) + 1])
          )[1:3],
          window_start = v_ws + (v_we - v_ws)
            * ((ARRAY[0,2,1,3,0,2,1,3])[((o.rn - 1) % 8) + 1] / 10.0),
          window_end   = v_we - (v_we - v_ws)
            * ((ARRAY[0,1,2,0,3,1,0,2])[((o.rn - 1) % 8) + 1] / 10.0),
          radius_km    = (ARRAY[30,50,15,NULL,50,10,30,15])[((o.rn - 1) % 8) + 1],
          base = ST_SetSRID(ST_MakePoint(
                   ST_X(v_base::geometry) + (ARRAY[0.06,0.13,-0.08,0.10,-0.12,0.15,0.04,-0.05])[((o.rn - 1) % 8) + 1],
                   ST_Y(v_base::geometry) + (ARRAY[0.00,0.03,-0.02,0.05,0.02,0.01,-0.04,0.04])[((o.rn - 1) % 8) + 1]),
                 4326)::geography,
          is_active = true
      FROM ordered o
      LEFT JOIN flavors f ON f.user_id = o.user_id
      WHERE dd.id = o.id;
    END IF;
  END IF;

  PERFORM log_admin_action(
    v_admin,
    CASE WHEN p_on THEN 'demo_mode_on' ELSE 'demo_mode_off' END,
    'app_config', NULL, NULL, NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION admin_set_demo_mode(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_demo_mode(boolean) TO authenticated;

-- Appliquer le nouveau calendrier tout de suite (miroir de la fonction).
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM activities
    WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
  )
  UPDATE activities a
  SET starts_at = date_trunc('day', now())
        + make_interval(
            days  => (1 + o.rn)::int,
            hours => (ARRAY[9,14,11,17,8,16,10,15])[((o.rn - 1) % 8) + 1],
            mins  => (ARRAY[0,30,0,30,15,0,45,30])[((o.rn - 1) % 8) + 1]
          ),
      status = 'published'
  FROM ordered o
  WHERE a.id = o.id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- ---------- (6) Fiabilité dérivée ----------
DO $$
DECLARE v_u RECORD;
BEGIN
  FOR v_u IN SELECT id FROM users WHERE is_demo = true AND id::text LIKE 'd0000000-%' AND id <> 'd0000000-0000-4000-a000-000000000001' LOOP
    PERFORM recalculate_reliability_score(v_u.id);
  END LOOP;
  FOR v_u IN SELECT display_name, reliability_score FROM users WHERE is_demo = true AND id::text LIKE 'd0000000-%' ORDER BY display_name LOOP
    RAISE NOTICE 'demo reliability % = %', v_u.display_name, v_u.reliability_score;
  END LOOP;
END $$;
