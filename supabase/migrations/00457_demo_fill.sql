-- ============================================================================
-- 00457 — Demo mode : 26 sorties de plus et des sorties REMPLIES (Scott
-- 2026-10-16 : « produire encore plus d'activités démo, et les remplir : chat,
-- matériel, transport »).
--
--   (1) 26 nouvelles sorties à venir (a0000000-…19→32), tout le 05 et les
--       voisins (Briançonnais et Gap compris cette fois, Champsaur, Dévoluy,
--       Écrins, Queyras, Ubaye, Verdon, Vercors, versant italien), sports
--       d'hiver inclus puisque le calendrier roule jusqu'en décembre.
--       created_at intercalé entre les 24 existantes → le re-datage mélange
--       anciennes et nouvelles au lieu de les empiler.
--   (2) Sur les 50 sorties à venir : 2 à 6 messages de mur (logistique, sans
--       date ni heure absolue — les sorties sont re-datées), 2 à 5 objets de
--       matériel dont des partagés + « il manque » sur une sortie sur deux,
--       1 à 2 conducteurs (car/carpool, 2 à 4 places, départ nommé, heure
--       relative à la sortie) avec demandes de siège acceptées/en attente sur
--       ~70 % des sorties ; les 4 sorties du Briançonnais gardent leur
--       transport existant.
--   (3) admin_set_demo_mode (live 00446, corps complet) : DEUX sorties par
--       jour, et les heures de covoiturage / pickups suivent la sortie
--       (CTE modifiante, même instantané). Appliqué tout de suite.
-- Push coupé pendant l'insertion (junto.skip_message_push) : un vrai compte
-- est membre d'une sortie démo. Tout est is_demo = true (rideau admin).
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  PERFORM set_config('junto.skip_message_push', 'true', true);

  -- ---------- (1) Nouvelles sorties ----------
  INSERT INTO activities
    (id, creator_id, sport_id, title, description, level, level_max,
     max_participants, location_meeting, meeting_name, meeting_locality,
     location_objective, objective_name,
     starts_at, duration, visibility, requires_presence, status,
     distance_km, elevation_gain_m, is_demo, created_at)
  VALUES
    ('a0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000008',
     (SELECT id FROM sports WHERE key = 'ski-touring'),
     'Ski de rando au col de Buffère',
     'Départ de Névache, montée régulière en forêt puis grands champs. Retour par la même trace.',
     'intermédiaire', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.605, 45.03), 4326)::geography, 'Parking de Névache', 'Névache',
     ST_SetSRID(ST_MakePoint(6.56, 45.03), 4326)::geography, 'Col de Buffère',
     now() + INTERVAL '30 days', INTERVAL '300 minutes', 'public', true, 'published',
     9, 900, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000001') + INTERVAL '1 minutes'),
    ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000c',
     (SELECT id FROM sports WHERE key = 'snowshoeing'),
     'Raquettes au lac de Roue',
     'Boucle tranquille au-dessus d''Arvieux, idéale pour une première sortie de la saison.',
     'débutant', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.745, 44.77), 4326)::geography, 'Pont de l''Ange', 'Arvieux',
     ST_SetSRID(ST_MakePoint(6.74, 44.75), 4326)::geography, 'Lac de Roue',
     now() + INTERVAL '31 days', INTERVAL '180 minutes', 'public', true, 'published',
     7, 350, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000002') + INTERVAL '2 minutes'),
    ('a0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-00000000000a',
     (SELECT id FROM sports WHERE key = 'trail-running'),
     'Trail du Puy de Manse',
     'Montée franche depuis Ancelle, crête panoramique, descente roulante.',
     'intermédiaire', 'avancé', 10,
     ST_SetSRID(ST_MakePoint(6.205, 44.62), 4326)::geography, 'Centre d''Ancelle', 'Ancelle',
     ST_SetSRID(ST_MakePoint(6.17, 44.61), 4326)::geography, 'Puy de Manse',
     now() + INTERVAL '32 days', INTERVAL '150 minutes', 'public', true, 'published',
     16, 900, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000003') + INTERVAL '3 minutes'),
    ('a0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000011',
     (SELECT id FROM sports WHERE key = 'climbing-sport'),
     'Grimpe à Sigottier',
     'Falaise calme du Buëch, voies de 5b à 6b, exposition sud.',
     'intermédiaire', 'avancé', 5,
     ST_SetSRID(ST_MakePoint(5.735, 44.465), 4326)::geography, 'Parking de la falaise', 'Sigottier',
     NULL, NULL,
     now() + INTERVAL '33 days', INTERVAL '300 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000004') + INTERVAL '4 minutes'),
    ('a0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000013',
     (SELECT id FROM sports WHERE key = 'hiking'),
     'Lac de Pétarel',
     'Rando classique du Valgaudemar, lacs et vue sur les Bans.',
     'intermédiaire', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.19, 44.805), 4326)::geography, 'Parking du Casset', 'La Chapelle-en-Valgaudemar',
     ST_SetSRID(ST_MakePoint(6.16, 44.78), 4326)::geography, 'Lac de Pétarel',
     now() + INTERVAL '34 days', INTERVAL '330 minutes', 'public', true, 'published',
     11, 850, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000005') + INTERVAL '5 minutes'),
    ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000f',
     (SELECT id FROM sports WHERE key = 'gravel'),
     'Gravel autour du Dévoluy',
     'Pistes et petites routes, passage au col du Festre. Allure tranquille.',
     'intermédiaire', NULL, 8,
     ST_SetSRID(ST_MakePoint(5.93, 44.69), 4326)::geography, 'Place du village', 'Saint-Étienne-en-Dévoluy',
     ST_SetSRID(ST_MakePoint(5.9, 44.68), 4326)::geography, 'Col du Festre',
     now() + INTERVAL '35 days', INTERVAL '240 minutes', 'public', true, 'published',
     52, 900, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000006') + INTERVAL '6 minutes'),
    ('a0000000-0000-4000-a000-00000000001f', 'd0000000-0000-4000-a000-000000000016',
     (SELECT id FROM sports WHERE key = 'running'),
     'Tour du lac de Pelleautier',
     'Footing plat au bord du lac, parfait pour reprendre doucement.',
     'débutant', NULL, 12,
     ST_SetSRID(ST_MakePoint(6.02, 44.52), 4326)::geography, 'Parking du lac', 'Pelleautier',
     NULL, NULL,
     now() + INTERVAL '36 days', INTERVAL '60 minutes', 'public', true, 'published',
     6, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000007') + INTERVAL '7 minutes'),
    ('a0000000-0000-4000-a000-000000000020', 'd0000000-0000-4000-a000-000000000015',
     (SELECT id FROM sports WHERE key = 'via-ferrata'),
     'Via ferrata de la Fresquière',
     'Belle via au-dessus de l''Ubaye, passages aériens, pont de singe.',
     'intermédiaire', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.52, 44.4), 4326)::geography, 'Parking de la via', 'Méolans-Revel',
     NULL, NULL,
     now() + INTERVAL '37 days', INTERVAL '210 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000008') + INTERVAL '8 minutes'),
    ('a0000000-0000-4000-a000-000000000021', 'd0000000-0000-4000-a000-000000000014',
     (SELECT id FROM sports WHERE key = 'mtb-enduro'),
     'Enduro du Mélezet',
     'Navette perso jusqu''au sommet des pistes, trois descentes en forêt.',
     'avancé', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.78, 44.67), 4326)::geography, 'Parking du Mélezet', 'Ceillac',
     NULL, NULL,
     now() + INTERVAL '38 days', INTERVAL '240 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000009') + INTERVAL '9 minutes'),
    ('a0000000-0000-4000-a000-000000000022', 'd0000000-0000-4000-a000-000000000009',
     (SELECT id FROM sports WHERE key = 'kayaking'),
     'Kayak sur le lac au lever du jour',
     'Mise à l''eau à Savines, eau plate, retour avant le vent.',
     'débutant', NULL, 6,
     ST_SetSRID(ST_MakePoint(6.4, 44.53), 4326)::geography, 'Base nautique', 'Savines-le-Lac',
     NULL, NULL,
     now() + INTERVAL '39 days', INTERVAL '150 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000a') + INTERVAL '10 minutes'),
    ('a0000000-0000-4000-a000-000000000023', 'd0000000-0000-4000-a000-00000000000d',
     (SELECT id FROM sports WHERE key = 'mtb-xc'),
     'VTT dans la forêt de Boscodon',
     'Boucle XC roulante sous les sapins, quelques relances.',
     'intermédiaire', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.46, 44.53), 4326)::geography, 'Abbaye de Boscodon', 'Crots',
     NULL, NULL,
     now() + INTERVAL '40 days', INTERVAL '180 minutes', 'public', true, 'published',
     24, 650, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000b') + INTERVAL '11 minutes'),
    ('a0000000-0000-4000-a000-000000000024', 'd0000000-0000-4000-a000-000000000002',
     (SELECT id FROM sports WHERE key = 'hiking'),
     'Balcon du Pelvoux',
     'Sentier en balcon au-dessus de Vallouise, vue sur les Écrins.',
     'intermédiaire', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.49, 44.845), 4326)::geography, 'Parking de Vallouise', 'Vallouise',
     NULL, NULL,
     now() + INTERVAL '41 days', INTERVAL '270 minutes', 'public', true, 'published',
     12, 700, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000c') + INTERVAL '12 minutes'),
    ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000003',
     (SELECT id FROM sports WHERE key = 'bouldering'),
     'Blocs à Ailefroide',
     'Session blocs sous les mélèzes, du 4 au 7a, crashpads bienvenus.',
     'débutant', 'avancé', 6,
     ST_SetSRID(ST_MakePoint(6.43, 44.89), 4326)::geography, 'Camping d''Ailefroide', 'Ailefroide',
     NULL, NULL,
     now() + INTERVAL '42 days', INTERVAL '240 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000d') + INTERVAL '13 minutes'),
    ('a0000000-0000-4000-a000-000000000026', 'd0000000-0000-4000-a000-000000000005',
     (SELECT id FROM sports WHERE key = 'paragliding'),
     'Vol d''automne à Mont-Dauphin',
     'Déco face sud, conditions calmes attendues, atterro au bord de la Durance.',
     'intermédiaire', NULL, 4,
     ST_SetSRID(ST_MakePoint(6.62, 44.67), 4326)::geography, 'Déco de Mont-Dauphin', 'Eygliers',
     NULL, NULL,
     now() + INTERVAL '43 days', INTERVAL '180 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000e') + INTERVAL '14 minutes'),
    ('a0000000-0000-4000-a000-000000000027', 'd0000000-0000-4000-a000-000000000006',
     (SELECT id FROM sports WHERE key = 'cross-country-ski'),
     'Ski de fond au Lautaret',
     'Premières traces de la saison sur le plateau, skating ou classique.',
     'débutant', 'intermédiaire', 8,
     ST_SetSRID(ST_MakePoint(6.405, 45.035), 4326)::geography, 'Col du Lautaret', 'Le Monêtier-les-Bains',
     NULL, NULL,
     now() + INTERVAL '44 days', INTERVAL '150 minutes', 'public', true, 'published',
     12, 150, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000f') + INTERVAL '15 minutes'),
    ('a0000000-0000-4000-a000-000000000028', 'd0000000-0000-4000-a000-000000000007',
     (SELECT id FROM sports WHERE key = 'cycling'),
     'Montée de l''Izoard avant la fermeture',
     'Dernière montée de l''année côté Briançon, allure endurance.',
     'intermédiaire', 'avancé', 10,
     ST_SetSRID(ST_MakePoint(6.64, 44.9), 4326)::geography, 'Place du Champ de Mars', 'Briançon',
     ST_SetSRID(ST_MakePoint(6.735, 44.82), 4326)::geography, 'Col d''Izoard',
     now() + INTERVAL '45 days', INTERVAL '240 minutes', 'public', true, 'published',
     40, 1100, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000010') + INTERVAL '16 minutes'),
    ('a0000000-0000-4000-a000-000000000029', 'd0000000-0000-4000-a000-00000000000b',
     (SELECT id FROM sports WHERE key = 'hiking'),
     'Pic de Morgon',
     'Montée depuis Boscodon, sommet panoramique sur Serre-Ponçon.',
     'avancé', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.47, 44.505), 4326)::geography, 'Parking de la Fontaine de l''Ours', 'Crots',
     ST_SetSRID(ST_MakePoint(6.45, 44.49), 4326)::geography, 'Pic de Morgon',
     now() + INTERVAL '46 days', INTERVAL '360 minutes', 'public', true, 'published',
     14, 1100, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000011') + INTERVAL '17 minutes'),
    ('a0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-00000000000e',
     (SELECT id FROM sports WHERE key = 'trekking'),
     'Tour du Viso, 3 jours',
     'Refuges italiens, cols à 2 900 m, sacs légers. Expérience en itinérance demandée.',
     'avancé', NULL, 6,
     ST_SetSRID(ST_MakePoint(7.0, 44.76), 4326)::geography, 'Parking de la Roche Écroulée', 'Ristolas',
     ST_SetSRID(ST_MakePoint(7.09, 44.67), 4326)::geography, 'Monte Viso',
     now() + INTERVAL '47 days', INTERVAL '2880 minutes', 'public', true, 'published',
     45, 2800, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000012') + INTERVAL '18 minutes'),
    ('a0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-000000000010',
     (SELECT id FROM sports WHERE key = 'hiking'),
     'Gorges de la Méouge',
     'Balade facile le long des gorges, baignade possible si il fait doux.',
     'débutant', NULL, 10,
     ST_SetSRID(ST_MakePoint(5.73, 44.27), 4326)::geography, 'Pont roman', 'Barret-sur-Méouge',
     NULL, NULL,
     now() + INTERVAL '48 days', INTERVAL '180 minutes', 'public', true, 'published',
     8, 250, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000013') + INTERVAL '19 minutes'),
    ('a0000000-0000-4000-a000-00000000002c', 'd0000000-0000-4000-a000-000000000012',
     (SELECT id FROM sports WHERE key = 'climbing-sport'),
     'Escalade à l''Escalès, Verdon',
     'Journée dans le Verdon, voies en 6, rappels au départ.',
     'avancé', NULL, 4,
     ST_SetSRID(ST_MakePoint(6.34, 43.78), 4326)::geography, 'Belvédère de l''Escalès', 'La Palud-sur-Verdon',
     NULL, NULL,
     now() + INTERVAL '49 days', INTERVAL '420 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000014') + INTERVAL '20 minutes'),
    ('a0000000-0000-4000-a000-00000000002d', 'd0000000-0000-4000-a000-000000000017',
     (SELECT id FROM sports WHERE key = 'climbing-multipitch'),
     'Grande voie à la Tête d''Aval',
     'Voie classique en 6a max, 8 longueurs, marche d''approche 1 h.',
     'avancé', NULL, 3,
     ST_SetSRID(ST_MakePoint(6.49, 44.84), 4326)::geography, 'Parking de Vallouise', 'Vallouise',
     ST_SetSRID(ST_MakePoint(6.47, 44.83), 4326)::geography, 'Tête d''Aval',
     now() + INTERVAL '50 days', INTERVAL '480 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000015') + INTERVAL '21 minutes'),
    ('a0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-000000000018',
     (SELECT id FROM sports WHERE key = 'ski-touring'),
     'Ski de rando à la Vallée Étroite',
     'Depuis Valfréjus, montée au col puis descente sur le versant italien si la neige suit.',
     'avancé', NULL, 5,
     ST_SetSRID(ST_MakePoint(6.64, 45.15), 4326)::geography, 'Parking de Valfréjus', 'Modane',
     NULL, NULL,
     now() + INTERVAL '51 days', INTERVAL '360 minutes', 'public', true, 'published',
     12, 1100, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000016') + INTERVAL '22 minutes'),
    ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-00000000000c',
     (SELECT id FROM sports WHERE key = 'ice-climbing'),
     'Cascade de glace à Ceillac, initiation',
     'Première glace de la saison, structures faciles, matériel prêté si besoin.',
     'débutant', NULL, 5,
     ST_SetSRID(ST_MakePoint(6.78, 44.67), 4326)::geography, 'Parking du Mélezet', 'Ceillac',
     NULL, NULL,
     now() + INTERVAL '52 days', INTERVAL '300 minutes', 'public', true, 'published',
     NULL, NULL, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000017') + INTERVAL '23 minutes'),
    ('a0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-00000000000a',
     (SELECT id FROM sports WHERE key = 'trail-running'),
     'Trail du plateau d''Ambel',
     'Vercors sud, plateau sauvage, allure endurance et pique-nique au sommet.',
     'intermédiaire', NULL, 8,
     ST_SetSRID(ST_MakePoint(5.33, 44.85), 4326)::geography, 'Col de la Bataille', 'Omblèze',
     NULL, NULL,
     now() + INTERVAL '53 days', INTERVAL '210 minutes', 'public', true, 'published',
     22, 900, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000018') + INTERVAL '24 minutes'),
    ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000015',
     (SELECT id FROM sports WHERE key = 'snowshoeing'),
     'Raquettes au col d''Allos',
     'Boucle douce depuis le col, grand soleil annoncé, thermos conseillé.',
     'débutant', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.6, 44.27), 4326)::geography, 'Col d''Allos', 'Allos',
     NULL, NULL,
     now() + INTERVAL '54 days', INTERVAL '180 minutes', 'public', true, 'published',
     8, 300, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000001') + INTERVAL '25 minutes'),
    ('a0000000-0000-4000-a000-000000000032', 'd0000000-0000-4000-a000-000000000016',
     (SELECT id FROM sports WHERE key = 'hiking'),
     'Lago di Thures depuis Bousson',
     'Rando frontalière côté italien, lac d''altitude, café à Bousson au retour.',
     'intermédiaire', NULL, 8,
     ST_SetSRID(ST_MakePoint(6.8, 44.93), 4326)::geography, 'Parking de Bousson', 'Cesana Torinese',
     ST_SetSRID(ST_MakePoint(6.76, 44.92), 4326)::geography, 'Lago di Thures',
     now() + INTERVAL '55 days', INTERVAL '300 minutes', 'public', true, 'published',
     13, 750, true,
     (SELECT created_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000002') + INTERVAL '26 minutes')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO participations (activity_id, user_id, status)
  SELECT x.activity_id, x.user_id, 'accepted' FROM (VALUES
    ('a0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-000000000019'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-00000000001a'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-00000000001a'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-00000000001a'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
    ('a0000000-0000-4000-a000-00000000001b'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-00000000001b'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-00000000001b'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000001b'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
    ('a0000000-0000-4000-a000-00000000001c'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000001c'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-00000000001c'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-00000000001d'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
    ('a0000000-0000-4000-a000-00000000001d'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-00000000001d'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-00000000001d'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-00000000001d'::uuid, 'd0000000-0000-4000-a000-000000000010'::uuid),
    ('a0000000-0000-4000-a000-00000000001e'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
    ('a0000000-0000-4000-a000-00000000001e'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-00000000001e'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-00000000001e'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-00000000001f'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-00000000001f'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-00000000001f'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000001f'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
    ('a0000000-0000-4000-a000-00000000001f'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000020'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000021'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000009'::uuid),
    ('a0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000022'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000023'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000024'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid),
    ('a0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000025'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000026'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-000000000026'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000026'::uuid, 'd0000000-0000-4000-a000-000000000010'::uuid),
    ('a0000000-0000-4000-a000-000000000027'::uuid, 'd0000000-0000-4000-a000-000000000006'::uuid),
    ('a0000000-0000-4000-a000-000000000027'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid),
    ('a0000000-0000-4000-a000-000000000027'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000027'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-000000000007'::uuid),
    ('a0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
    ('a0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000028'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-000000000029'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-00000000002a'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid),
    ('a0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-000000000010'::uuid),
    ('a0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-000000000005'::uuid),
    ('a0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-00000000000f'::uuid),
    ('a0000000-0000-4000-a000-00000000002b'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-000000000012'::uuid),
    ('a0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-00000000002c'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-00000000002d'::uuid, 'd0000000-0000-4000-a000-000000000004'::uuid),
    ('a0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
    ('a0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-00000000002e'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-00000000000c'::uuid),
    ('a0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-00000000000e'::uuid),
    ('a0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid),
    ('a0000000-0000-4000-a000-00000000002f'::uuid, 'd0000000-0000-4000-a000-000000000017'::uuid),
    ('a0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000030'::uuid, 'd0000000-0000-4000-a000-000000000018'::uuid),
    ('a0000000-0000-4000-a000-000000000031'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid),
    ('a0000000-0000-4000-a000-000000000031'::uuid, 'd0000000-0000-4000-a000-000000000014'::uuid),
    ('a0000000-0000-4000-a000-000000000031'::uuid, 'd0000000-0000-4000-a000-00000000000b'::uuid),
    ('a0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000016'::uuid),
    ('a0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-00000000000a'::uuid),
    ('a0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000011'::uuid),
    ('a0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-00000000000d'::uuid),
    ('a0000000-0000-4000-a000-000000000032'::uuid, 'd0000000-0000-4000-a000-000000000008'::uuid)
  ) AS x(activity_id, user_id)
  ON CONFLICT DO NOTHING;

  -- ---------- (2) Chat ----------
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Puy-Chalvin. N''hésitez pas si vous avez des questions.', now() - INTERVAL '118 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000001';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '115 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000001';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '111 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000001';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Hello ! Pour le départ : au parking de Villar-Saint-Pancrace. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '63 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000002';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Je prends la corde de 70, ça suffit ?', now() - INTERVAL '61 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000002';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '56 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000002';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Première fois pour moi sur ce site, j''ai hâte !', now() - INTERVAL '52 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000002';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Oui 70 m c''est parfait, les voies font 30 m max.', now() - INTERVAL '45 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000002';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Hello ! Pour le départ : au parking de Puy-Chalvin. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '50 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000003';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '44 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000003';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Le topo est dans le matériel partagé, je l''amène.', now() - INTERVAL '35 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000003';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Je prends la corde de 70, ça suffit ?', now() - INTERVAL '29 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000003';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Oui 70 m c''est parfait, les voies font 30 m max.', now() - INTERVAL '24 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000003';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Top, merci pour l''orga !', now() - INTERVAL '18 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000003';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Salut ! Petit rappel du rendez-vous : au parking de Les Combes. La météo a l''air bonne pour l''instant.', now() - INTERVAL '116 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000004';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Parfait, hâte d''y être !', now() - INTERVAL '113 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000004';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de La Chapelle-en-Valgaudemar. N''hésitez pas si vous avez des questions.', now() - INTERVAL '76 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000005';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Il reste de la neige là-haut ou ça passe en chaussures ?', now() - INTERVAL '73 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000005';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '67 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000005';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Parfait, hâte d''y être !', now() - INTERVAL '64 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000005';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Salut ! Petit rappel du rendez-vous : au parking de Sigoyer. La météo a l''air bonne pour l''instant.', now() - INTERVAL '108 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Je prends la corde de 70, ça suffit ?', now() - INTERVAL '99 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Le topo est dans le matériel partagé, je l''amène.', now() - INTERVAL '96 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Première fois pour moi sur ce site, j''ai hâte !', now() - INTERVAL '94 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Oui 70 m c''est parfait, les voies font 30 m max.', now() - INTERVAL '87 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Parfait, hâte d''y être !', now() - INTERVAL '82 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000006';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Chorges. N''hésitez pas si vous avez des questions.', now() - INTERVAL '80 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000007';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Combinaison obligatoire ou ça passe en lycra ?', now() - INTERVAL '79 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000007';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'La mise à l''eau est juste à côté du parking.', now() - INTERVAL '74 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000007';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Ça marche, à très vite !', now() - INTERVAL '66 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000007';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Gap. N''hésitez pas si vous avez des questions.', now() - INTERVAL '109 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000008';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '107 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000008';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '101 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000008';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Il reste de la neige là-haut ou ça passe en chaussures ?', now() - INTERVAL '98 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000008';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '93 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000008';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Salut tout le monde ! Rendez-vous au parking de Vars, je serai là un quart d''heure avant.', now() - INTERVAL '109 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000009';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Quelqu''un a une pompe à pied dans le coffre ?', now() - INTERVAL '102 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000009';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Pas de souci, on t''attend dix minutes, pas plus.', now() - INTERVAL '93 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000009';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '86 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000009';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000010', 'Hello ! Pour le départ : au parking de Laragne-Montéglin. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '113 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Quelqu''un a une radio en plus ?', now() - INTERVAL '104 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000010', 'Brise de vallée à partir de midi, on décolle avant.', now() - INTERVAL '101 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000f', 'Salut ! Petit rappel du rendez-vous : au parking de Veynes. La météo a l''air bonne pour l''instant.', now() - INTERVAL '88 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Quelqu''un a une pompe à pied dans le coffre ?', now() - INTERVAL '83 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000f', 'Tubeless pour moi aussi, un kit à deux ça suffit.', now() - INTERVAL '78 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '74 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Hello ! Pour le départ : au parking de La Faurie. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '55 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Quelqu''un a un casque en rab ? Le mien est resté chez ma sœur.', now() - INTERVAL '53 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '50 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Ça marche, à très vite !', now() - INTERVAL '43 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Salut ! Petit rappel du rendez-vous : au parking de Savines-le-Lac. La météo a l''air bonne pour l''instant.', now() - INTERVAL '67 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Quelqu''un a une pompe à pied dans le coffre ?', now() - INTERVAL '64 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Deux voitures pour la navette, on verra sur place.', now() - INTERVAL '57 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Salut ! Petit rappel du rendez-vous : au parking de Le Lauzet-Ubaye. La météo a l''air bonne pour l''instant.', now() - INTERVAL '68 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Combinaison obligatoire ou ça passe en lycra ?', now() - INTERVAL '66 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Combi conseillée, l''eau est à 14 degrés.', now() - INTERVAL '62 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Prunières. N''hésitez pas si vous avez des questions.', now() - INTERVAL '78 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Je peux amener un bidon étanche pour les téléphones.', now() - INTERVAL '74 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'La mise à l''eau est juste à côté du parking.', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Il y a une mise à l''eau facile ?', now() - INTERVAL '58 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Je prends le bidon, merci !', now() - INTERVAL '53 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Parfait, hâte d''y être !', now() - INTERVAL '44 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000000f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Salut ! Petit rappel du rendez-vous : au parking de Arvieux. La météo a l''air bonne pour l''instant.', now() - INTERVAL '88 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000010';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Je peux amener la trousse de secours et un thermos.', now() - INTERVAL '86 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000010';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '79 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000010';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Top, merci pour l''orga !', now() - INTERVAL '76 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000010';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Hello ! Pour le départ : au parking de Saint-Véran. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '100 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000011';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Je peux amener la trousse de secours et un thermos.', now() - INTERVAL '98 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000011';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '94 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000011';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '90 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000011';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '87 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000011';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Hello ! Pour le départ : au parking de Orpierre. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '99 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000012';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '97 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000012';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '90 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000012';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Ça marche, à très vite !', now() - INTERVAL '87 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000012';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Hello ! Pour le départ : au parking de Savines-le-Lac. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '102 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000013';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Je peux amener un bidon étanche pour les téléphones.', now() - INTERVAL '99 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000013';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'La mise à l''eau est juste à côté du parking.', now() - INTERVAL '97 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000013';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Salut ! Petit rappel du rendez-vous : au parking de Embrun. La météo a l''air bonne pour l''instant.', now() - INTERVAL '110 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000014';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Quelqu''un passe par Modane ? Je peux prendre deux personnes.', now() - INTERVAL '105 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000014';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '97 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000014';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Embrun. N''hésitez pas si vous avez des questions.', now() - INTERVAL '110 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000015';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '101 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000015';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Modane. N''hésitez pas si vous avez des questions.', now() - INTERVAL '119 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000016';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '115 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000016';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '114 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000016';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Quelqu''un passe par Gap ? Je peux prendre deux personnes.', now() - INTERVAL '111 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000016';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '105 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000016';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Parfait, hâte d''y être !', now() - INTERVAL '100 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000016';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Montgenèvre. N''hésitez pas si vous avez des questions.', now() - INTERVAL '89 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000017';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Vous roulez tubeless ? Je prends le kit au cas où.', now() - INTERVAL '86 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000017';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Deux voitures pour la navette, on verra sur place.', now() - INTERVAL '77 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000017';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Hello ! Pour le départ : au parking de Bardonecchia. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '116 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000018';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '114 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000018';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Salut tout le monde ! Rendez-vous au parking de Névache, je serai là un quart d''heure avant.', now() - INTERVAL '58 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000019';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Vous prenez les crampons ou c''est inutile ?', now() - INTERVAL '54 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000019';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Bulletin à 2 sur 5, on reste sur les pentes douces.', now() - INTERVAL '51 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000019';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Ça marche, à très vite !', now() - INTERVAL '45 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000019';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Hello ! Pour le départ : à « Pont de l''Ange ». On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '63 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Parfait, hâte d''y être !', now() - INTERVAL '59 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Hello ! Pour le départ : à « Centre d''Ancelle ». On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '102 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Je peux amener la trousse de secours et un thermos.', now() - INTERVAL '100 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '92 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Hello ! Pour le départ : au parking de la falaise. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '113 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Quelqu''un a un casque en rab ? Le mien est resté chez ma sœur.', now() - INTERVAL '112 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '108 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Parfait, hâte d''y être !', now() - INTERVAL '105 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Salut tout le monde ! Rendez-vous au parking du Casset, je serai là un quart d''heure avant.', now() - INTERVAL '62 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Je peux amener la trousse de secours et un thermos.', now() - INTERVAL '58 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Compte deux bonnes heures de montée, tranquille.', now() - INTERVAL '49 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '42 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '34 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Ça marche, à très vite !', now() - INTERVAL '29 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000f', 'Salut tout le monde ! Rendez-vous à « Place du village », je serai là un quart d''heure avant.', now() - INTERVAL '102 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Parfait, hâte d''y être !', now() - INTERVAL '97 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking du lac. N''hésitez pas si vous avez des questions.', now() - INTERVAL '63 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '54 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '53 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000001f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de la via. N''hésitez pas si vous avez des questions.', now() - INTERVAL '111 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000020';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '109 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000020';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '105 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000020';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Quelqu''un a un casque en rab ? Le mien est resté chez ma sœur.', now() - INTERVAL '98 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000020';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Le topo est dans le matériel partagé, je l''amène.', now() - INTERVAL '97 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000020';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Parfait, hâte d''y être !', now() - INTERVAL '92 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000020';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Salut tout le monde ! Rendez-vous au parking du Mélezet, je serai là un quart d''heure avant.', now() - INTERVAL '80 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000021';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Quelqu''un a une pompe à pied dans le coffre ?', now() - INTERVAL '71 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000021';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Deux voitures pour la navette, on verra sur place.', now() - INTERVAL '68 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000021';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Salut tout le monde ! Rendez-vous à « Base nautique », je serai là un quart d''heure avant.', now() - INTERVAL '50 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000022';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Il y a une mise à l''eau facile ?', now() - INTERVAL '46 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000022';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Débit correct cette semaine d''après la météo, ça passe.', now() - INTERVAL '45 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000022';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Combinaison obligatoire ou ça passe en lycra ?', now() - INTERVAL '37 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000022';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000009', 'Combi conseillée, l''eau est à 14 degrés.', now() - INTERVAL '29 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000022';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Parfait, hâte d''y être !', now() - INTERVAL '23 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000022';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Salut tout le monde ! Rendez-vous à « Abbaye de Boscodon », je serai là un quart d''heure avant.', now() - INTERVAL '74 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000023';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000014', 'Vous roulez tubeless ? Je prends le kit au cas où.', now() - INTERVAL '73 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000023';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Tubeless pour moi aussi, un kit à deux ça suffit.', now() - INTERVAL '72 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000023';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'On est en combien pour la navette ?', now() - INTERVAL '65 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000023';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Deux voitures pour la navette, on verra sur place.', now() - INTERVAL '61 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000023';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de Vallouise. N''hésitez pas si vous avez des questions.', now() - INTERVAL '60 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000024';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000008', 'Quelqu''un passe par Briançon ? Je peux prendre deux personnes.', now() - INTERVAL '53 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000024';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '45 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000024';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'C''est combien de temps de montée à peu près ?', now() - INTERVAL '42 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000024';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000002', 'J''ai mis la trace GPX sur la sortie, jetez-y un œil.', now() - INTERVAL '38 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000024';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'Parfait, hâte d''y être !', now() - INTERVAL '36 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000024';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Camping d''Ailefroide ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '81 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000025';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Quelqu''un a un casque en rab ? Le mien est resté chez ma sœur.', now() - INTERVAL '79 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000025';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Avec deux cordes et une vingtaine de dégaines on est larges.', now() - INTERVAL '73 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000025';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000004', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '68 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000025';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000003', 'Le topo est dans le matériel partagé, je l''amène.', now() - INTERVAL '66 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000025';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Déco de Mont-Dauphin ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '56 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000026';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'On monte au déco en voiture ou à pied ?', now() - INTERVAL '53 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000026';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'En voiture jusqu''au déco, on se regroupe en bas.', now() - INTERVAL '44 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000026';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '43 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000026';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000006', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Col du Lautaret ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '84 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000027';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '78 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000027';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Salut tout le monde ! Rendez-vous à « Place du Champ de Mars », je serai là un quart d''heure avant.', now() - INTERVAL '63 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000028';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Vous roulez tubeless ? Je prends le kit au cas où.', now() - INTERVAL '54 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000028';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000007', 'Tubeless pour moi aussi, un kit à deux ça suffit.', now() - INTERVAL '47 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000028';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Bienvenue sur la sortie ! Le point de rendez-vous est au parking de la Fontaine de l''Ours. N''hésitez pas si vous avez des questions.', now() - INTERVAL '67 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000029';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Quelqu''un passe par Gap ? Je peux prendre deux personnes.', now() - INTERVAL '66 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000029';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'J''ai mis la trace GPX sur la sortie, jetez-y un œil.', now() - INTERVAL '61 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000029';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Top, merci pour l''orga !', now() - INTERVAL '52 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000029';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Hello ! Pour le départ : au parking de la Roche Écroulée. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '96 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Il reste de la neige là-haut ou ça passe en chaussures ?', now() - INTERVAL '95 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '87 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Quelqu''un passe par Guillestre ? Je peux prendre deux personnes.', now() - INTERVAL '79 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000e', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '75 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000013', 'Top, merci pour l''orga !', now() - INTERVAL '67 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002a';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000010', 'Bienvenue sur la sortie ! Le point de rendez-vous est à « Pont roman ». N''hésitez pas si vous avez des questions.', now() - INTERVAL '103 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Je peux amener la trousse de secours et un thermos.', now() - INTERVAL '97 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000010', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '95 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Il reste de la neige là-haut ou ça passe en chaussures ?', now() - INTERVAL '92 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000010', 'Ça passe en chaussures, les bâtons aident sur la fin.', now() - INTERVAL '88 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000005', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '82 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002b';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Salut tout le monde ! Rendez-vous à « Belvédère de l''Escalès », je serai là un quart d''heure avant.', now() - INTERVAL '113 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Première fois pour moi sur ce site, j''ai hâte !', now() - INTERVAL '107 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000012', 'Casque obligatoire, j''en ai un de prêt.', now() - INTERVAL '106 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '98 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002c';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Hello ! Pour le départ : au parking de Vallouise. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '86 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'On a assez de dégaines à nous tous ?', now() - INTERVAL '85 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Le topo est dans le matériel partagé, je l''amène.', now() - INTERVAL '84 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002d';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Hello ! Pour le départ : au parking de Valfréjus. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '84 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Ça marche, à très vite !', now() - INTERVAL '81 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002e';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000c', 'Hello ! Pour le départ : au parking du Mélezet. On part pile à l''heure, prévoyez un peu de marge.', now() - INTERVAL '54 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000017', 'Ça marche, à très vite !', now() - INTERVAL '50 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-00000000002f';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Salut ! Petit rappel du rendez-vous : à « Col de la Bataille ». La météo a l''air bonne pour l''instant.', now() - INTERVAL '76 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000030';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000018', 'Quelqu''un passe par Modane ? Je peux prendre deux personnes.', now() - INTERVAL '69 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000030';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000a', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '62 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000030';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Parfait, hâte d''y être !', now() - INTERVAL '57 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000030';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'Salut tout le monde ! Rendez-vous à « Col d''Allos », je serai là un quart d''heure avant.', now() - INTERVAL '62 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000031';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Vous prenez les crampons ou c''est inutile ?', now() - INTERVAL '54 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000031';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000015', 'DVA, pelle, sonde pour tout le monde, pas d''exception.', now() - INTERVAL '45 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000031';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000b', 'Top, merci pour l''orga !', now() - INTERVAL '38 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000031';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Salut tout le monde ! Rendez-vous au parking de Bousson, je serai là un quart d''heure avant.', now() - INTERVAL '120 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000032';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-00000000000d', 'Quelqu''un passe par Briançon ? Je peux prendre deux personnes.', now() - INTERVAL '116 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000032';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000016', 'Pensez à 1,5 L d''eau par personne et un coupe-vent.', now() - INTERVAL '108 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000032';
  INSERT INTO messages (conversation_id, sender_id, content, created_at)
  SELECT c.id, 'd0000000-0000-4000-a000-000000000011', 'Nickel, je prépare le sac ce soir.', now() - INTERVAL '101 hours'
  FROM conversations c WHERE c.type = 'activity' AND c.activity_id = 'a0000000-0000-4000-a000-000000000032';

  UPDATE conversations c SET last_message_at = m.last_at
  FROM (SELECT conversation_id, max(created_at) AS last_at FROM messages GROUP BY conversation_id) m
  WHERE m.conversation_id = c.id AND c.type = 'activity'
    AND c.activity_id IN (SELECT id FROM activities WHERE is_demo AND id::text LIKE 'a0000000-%');

  -- ---------- (3) Matériel ----------
  INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared) VALUES
    ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000008', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000008', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000005', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000003', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000003', 'Baudrier', 1, false),
    ('a0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000003', 'Corde 70 m', 1, true),
    ('a0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000003', 'Chaussons', 1, false),
    ('a0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000004', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000006', 'Crashpad', 1, true),
    ('a0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000004', 'Sangles et mousquetons de relais', 4, true),
    ('a0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000008', 'Manche à air', 1, true),
    ('a0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000008', 'Sellette', 1, false),
    ('a0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000008', 'Variomètre', 1, false),
    ('a0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000e', 'Frontale', 1, false),
    ('a0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000013', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000e', 'Bâtons', 1, false),
    ('a0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000e', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000011', 'Baudrier', 1, false),
    ('a0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000011', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000011', 'Chaussons', 1, false),
    ('a0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000a', 'Combinaison', 1, false),
    ('a0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000a', 'Pagaie de rechange', 1, true),
    ('a0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000a', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000018', 'Barres et gels à partager', 6, true),
    ('a0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000a', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000018', 'Bâtons', 1, false),
    ('a0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000007', 'Chambres à air', 2, true),
    ('a0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000014', 'Lumières', 1, false),
    ('a0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000007', 'Bidon de 1 L', 1, false),
    ('a0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000007', 'Kit tubeless', 1, true),
    ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000005', 'Variomètre', 1, false),
    ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000005', 'Voile', 1, false),
    ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000005', 'Manche à air', 1, true),
    ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000010', 'Radio', 1, true),
    ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000010', 'Sellette', 1, false),
    ('a0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000016', 'Kit tubeless', 1, true),
    ('a0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000000f', 'Lumières', 1, false),
    ('a0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000000d', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000000d', 'Chambres à air', 2, true),
    ('a0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000000d', 'Multi-outil', 1, true),
    ('a0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000c', 'Longe de via ferrata', 1, false),
    ('a0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000017', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000013', 'Baudrier', 1, false),
    ('a0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000c', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000000f', 'Bidon de 1 L', 1, false),
    ('a0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000016', 'Multi-outil', 1, true),
    ('a0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000000f', 'Kit tubeless', 1, true),
    ('a0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000000b', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000000b', 'Lumières', 1, false),
    ('a0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000014', 'Bidon étanche', 1, true),
    ('a0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-00000000000b', 'Combinaison', 1, false),
    ('a0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000015', 'Gilet', 1, false),
    ('a0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-000000000012', 'Combinaison', 1, false),
    ('a0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-00000000000b', 'Descendeur', 1, false),
    ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-00000000000c', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-00000000000e', 'Bâtons', 1, false),
    ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000013', 'Frontale', 1, false),
    ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000013', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-00000000000e', 'Couverture de survie', 1, true),
    ('a0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-00000000000e', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-000000000013', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000011', 'Baudrier', 1, false),
    ('a0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000017', 'Sangles et mousquetons de relais', 4, true),
    ('a0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-00000000000a', 'Corde 70 m', 1, true),
    ('a0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000000b', 'Leash', 1, false),
    ('a0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000000b', 'Combinaison', 1, false),
    ('a0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-000000000012', 'Gilet', 1, false),
    ('a0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000018', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000018', 'Frontale', 1, false),
    ('a0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000016', 'Barres et gels à partager', 6, true),
    ('a0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000018', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000012', 'Leash', 1, false),
    ('a0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000016', 'Bidon étanche', 1, true),
    ('a0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-00000000000a', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-00000000000d', 'Couverture de survie', 1, true),
    ('a0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000c', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000d', 'Chambres à air', 2, true),
    ('a0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000e', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000d', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000d', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000e', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000008', 'Sonde', 1, false),
    ('a0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000008', 'Pelle', 1, false),
    ('a0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-00000000000d', 'Peaux', 1, false),
    ('a0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000008', 'Couteaux', 1, false),
    ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000e', 'Raquettes', 1, false),
    ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000c', 'Thermos', 1, true),
    ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000e', 'Pelle', 1, false),
    ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000c', 'Crampons', 1, false),
    ('a0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000011', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000016', 'Barres et gels à partager', 6, true),
    ('a0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000017', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000017', 'Longe de via ferrata', 1, false),
    ('a0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000011', 'Dégaines', 12, true),
    ('a0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000010', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000010', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-00000000000c', 'Bâtons', 1, false),
    ('a0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000010', 'Frontale', 1, false),
    ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000f', 'Barres', 6, true),
    ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000f', 'Kit tubeless', 1, true),
    ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000b', 'Multi-outil', 1, true),
    ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000d', 'Chambres à air', 2, true),
    ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000b', 'Bidon de 1 L', 1, false),
    ('a0000000-0000-4000-a000-00000000001f', 'd0000000-0000-4000-a000-000000000018', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-00000000001f', 'd0000000-0000-4000-a000-000000000017', 'Bâtons', 1, false),
    ('a0000000-0000-4000-a000-00000000001f', 'd0000000-0000-4000-a000-000000000017', 'Frontale', 1, false),
    ('a0000000-0000-4000-a000-000000000020', 'd0000000-0000-4000-a000-000000000014', 'Longe de via ferrata', 1, false),
    ('a0000000-0000-4000-a000-000000000020', 'd0000000-0000-4000-a000-000000000012', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-000000000020', 'd0000000-0000-4000-a000-00000000000b', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000021', 'd0000000-0000-4000-a000-00000000000d', 'Barres', 6, true),
    ('a0000000-0000-4000-a000-000000000021', 'd0000000-0000-4000-a000-000000000014', 'Multi-outil', 1, true),
    ('a0000000-0000-4000-a000-000000000021', 'd0000000-0000-4000-a000-000000000007', 'Kit tubeless', 1, true),
    ('a0000000-0000-4000-a000-000000000022', 'd0000000-0000-4000-a000-00000000000b', 'Gilet', 1, false),
    ('a0000000-0000-4000-a000-000000000022', 'd0000000-0000-4000-a000-000000000012', 'Pagaie de rechange', 1, true),
    ('a0000000-0000-4000-a000-000000000023', 'd0000000-0000-4000-a000-000000000014', 'Lumières', 1, false),
    ('a0000000-0000-4000-a000-000000000023', 'd0000000-0000-4000-a000-00000000000d', 'Pompe', 1, true),
    ('a0000000-0000-4000-a000-000000000023', 'd0000000-0000-4000-a000-000000000014', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-000000000024', 'd0000000-0000-4000-a000-000000000006', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000024', 'd0000000-0000-4000-a000-000000000008', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000024', 'd0000000-0000-4000-a000-000000000004', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000004', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000003', 'Dégaines', 12, true),
    ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-00000000000d', 'Chaussons', 1, false),
    ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000005', 'Longe de via ferrata', 1, false),
    ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000003', 'Baudrier', 1, false),
    ('a0000000-0000-4000-a000-000000000026', 'd0000000-0000-4000-a000-000000000005', 'Voile', 1, false),
    ('a0000000-0000-4000-a000-000000000026', 'd0000000-0000-4000-a000-000000000010', 'Radio', 1, true),
    ('a0000000-0000-4000-a000-000000000026', 'd0000000-0000-4000-a000-000000000005', 'Sellette', 1, false),
    ('a0000000-0000-4000-a000-000000000027', 'd0000000-0000-4000-a000-000000000006', 'Skis de fond', 1, false),
    ('a0000000-0000-4000-a000-000000000027', 'd0000000-0000-4000-a000-000000000007', 'Thermos', 1, true),
    ('a0000000-0000-4000-a000-000000000027', 'd0000000-0000-4000-a000-000000000002', 'Fart', 1, true),
    ('a0000000-0000-4000-a000-000000000028', 'd0000000-0000-4000-a000-00000000000b', 'Barres', 6, true),
    ('a0000000-0000-4000-a000-000000000028', 'd0000000-0000-4000-a000-000000000007', 'Multi-outil', 1, true),
    ('a0000000-0000-4000-a000-000000000029', 'd0000000-0000-4000-a000-000000000015', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000029', 'd0000000-0000-4000-a000-000000000012', 'Couverture de survie', 1, true),
    ('a0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-00000000000c', 'Barres et gels à partager', 6, true),
    ('a0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-000000000013', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-000000000013', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-00000000000c', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-00000000002a', 'd0000000-0000-4000-a000-000000000013', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-000000000010', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-000000000005', 'Couverture de survie', 1, true),
    ('a0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-000000000011', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-000000000010', 'Thermos de thé', 1, true),
    ('a0000000-0000-4000-a000-00000000002b', 'd0000000-0000-4000-a000-00000000000f', 'Bâtons', 1, false),
    ('a0000000-0000-4000-a000-00000000002c', 'd0000000-0000-4000-a000-000000000017', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-00000000002c', 'd0000000-0000-4000-a000-00000000000a', 'Corde 70 m', 1, true),
    ('a0000000-0000-4000-a000-00000000002d', 'd0000000-0000-4000-a000-000000000011', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-00000000002d', 'd0000000-0000-4000-a000-000000000004', 'Topo du site', 1, true),
    ('a0000000-0000-4000-a000-00000000002d', 'd0000000-0000-4000-a000-000000000004', 'Chaussons', 1, false),
    ('a0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-000000000018', 'Couteaux', 1, false),
    ('a0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-00000000000a', 'Sonde', 1, false),
    ('a0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-00000000000a', 'Pelle', 1, false),
    ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-000000000017', 'Casque', 1, false),
    ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-00000000000e', 'Crampons', 1, false),
    ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-00000000000e', 'Corde à double 50 m', 1, true),
    ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-000000000003', 'Thermos', 1, true),
    ('a0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-000000000018', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-000000000016', 'Barres et gels à partager', 6, true),
    ('a0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-000000000018', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-000000000016', 'Gilet d''hydratation', 1, false),
    ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000015', 'Pelle', 1, false),
    ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-00000000000b', 'Raquettes', 1, false),
    ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000014', 'Thermos', 1, true),
    ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000014', 'Crampons', 1, false),
    ('a0000000-0000-4000-a000-000000000032', 'd0000000-0000-4000-a000-00000000000a', 'Carte IGN du secteur', 1, true),
    ('a0000000-0000-4000-a000-000000000032', 'd0000000-0000-4000-a000-000000000008', 'Trousse de secours', 1, true),
    ('a0000000-0000-4000-a000-000000000032', 'd0000000-0000-4000-a000-000000000011', 'Barres et gels à partager', 6, true);

  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by) VALUES
    ('a0000000-0000-4000-a000-000000000002', 'Dégaines supplémentaires', 2, 'd0000000-0000-4000-a000-000000000003'),
    ('a0000000-0000-4000-a000-000000000002', 'Un casque en plus', 1, 'd0000000-0000-4000-a000-000000000003'),
    ('a0000000-0000-4000-a000-000000000006', 'Dégaines supplémentaires', 2, 'd0000000-0000-4000-a000-000000000011'),
    ('a0000000-0000-4000-a000-000000000009', 'Chambre à air 29"', 1, 'd0000000-0000-4000-a000-000000000014'),
    ('a0000000-0000-4000-a000-00000000000a', 'Manche à air', 1, 'd0000000-0000-4000-a000-000000000010'),
    ('a0000000-0000-4000-a000-00000000000a', 'Radio de secours', 2, 'd0000000-0000-4000-a000-000000000010'),
    ('a0000000-0000-4000-a000-00000000000c', 'Un casque en plus', 1, 'd0000000-0000-4000-a000-000000000017'),
    ('a0000000-0000-4000-a000-00000000000c', 'Corde 60 m', 1, 'd0000000-0000-4000-a000-000000000017'),
    ('a0000000-0000-4000-a000-00000000000d', 'Chambre à air 29"', 2, 'd0000000-0000-4000-a000-000000000016'),
    ('a0000000-0000-4000-a000-000000000010', 'Thermos de thé', 1, 'd0000000-0000-4000-a000-00000000000e'),
    ('a0000000-0000-4000-a000-000000000010', 'Carte IGN du secteur', 1, 'd0000000-0000-4000-a000-00000000000e'),
    ('a0000000-0000-4000-a000-000000000012', 'Dégaines supplémentaires', 1, 'd0000000-0000-4000-a000-000000000011'),
    ('a0000000-0000-4000-a000-000000000017', 'Multi-outil', 2, 'd0000000-0000-4000-a000-00000000000d'),
    ('a0000000-0000-4000-a000-000000000019', 'Une sonde supplémentaire', 2, 'd0000000-0000-4000-a000-000000000008'),
    ('a0000000-0000-4000-a000-00000000001a', 'Une sonde supplémentaire', 2, 'd0000000-0000-4000-a000-00000000000c'),
    ('a0000000-0000-4000-a000-00000000001b', 'Trousse de secours', 2, 'd0000000-0000-4000-a000-00000000000a'),
    ('a0000000-0000-4000-a000-00000000001b', 'Carte IGN du secteur', 1, 'd0000000-0000-4000-a000-00000000000a'),
    ('a0000000-0000-4000-a000-00000000001c', 'Un casque en plus', 1, 'd0000000-0000-4000-a000-000000000011'),
    ('a0000000-0000-4000-a000-00000000001c', 'Dégaines supplémentaires', 1, 'd0000000-0000-4000-a000-000000000011'),
    ('a0000000-0000-4000-a000-00000000001f', 'Thermos de thé', 2, 'd0000000-0000-4000-a000-000000000016'),
    ('a0000000-0000-4000-a000-00000000001f', 'Carte IGN du secteur', 2, 'd0000000-0000-4000-a000-000000000016'),
    ('a0000000-0000-4000-a000-000000000021', 'Chambre à air 29"', 2, 'd0000000-0000-4000-a000-000000000014'),
    ('a0000000-0000-4000-a000-000000000021', 'Pompe à pied', 1, 'd0000000-0000-4000-a000-000000000014'),
    ('a0000000-0000-4000-a000-000000000023', 'Pompe à pied', 2, 'd0000000-0000-4000-a000-00000000000d'),
    ('a0000000-0000-4000-a000-000000000028', 'Chambre à air 29"', 1, 'd0000000-0000-4000-a000-000000000007'),
    ('a0000000-0000-4000-a000-000000000029', 'Trousse de secours', 2, 'd0000000-0000-4000-a000-00000000000b'),
    ('a0000000-0000-4000-a000-00000000002a', 'Thermos de thé', 2, 'd0000000-0000-4000-a000-00000000000e'),
    ('a0000000-0000-4000-a000-00000000002e', 'Thermos de thé', 2, 'd0000000-0000-4000-a000-000000000018'),
    ('a0000000-0000-4000-a000-00000000002f', 'Crampons de rechange', 1, 'd0000000-0000-4000-a000-00000000000c'),
    ('a0000000-0000-4000-a000-00000000002f', 'Une sonde supplémentaire', 2, 'd0000000-0000-4000-a000-00000000000c'),
    ('a0000000-0000-4000-a000-000000000032', 'Thermos de thé', 1, 'd0000000-0000-4000-a000-000000000016')
  ON CONFLICT DO NOTHING;

  -- ---------- (4) Transport ----------
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Guillestre', transport_from_lng = 6.65, transport_from_lat = 44.66,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000005') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000005' AND user_id = 'd0000000-0000-4000-a000-00000000000e';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000e', 'accepted', 'Depuis Guillestre', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-000000000005' AND user_id = 'd0000000-0000-4000-a000-000000000017';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000006') - INTERVAL '90 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000006' AND user_id = 'd0000000-0000-4000-a000-000000000011';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-000000000011', 'accepted', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000007') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000007' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-00000000000a', 'pending', 'Depuis Gap', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-00000000000a', 'pending', 'Depuis Barcelonnette', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000007' AND user_id = 'd0000000-0000-4000-a000-000000000012';
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000007' AND user_id = 'd0000000-0000-4000-a000-00000000000b';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Modane', transport_from_lng = 6.659, transport_from_lat = 45.195,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000008') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000008' AND user_id = 'd0000000-0000-4000-a000-000000000018';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000018', 'pending', 'Depuis Gap', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-000000000008' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000a') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000000a' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000005', 'accepted', 'Depuis Laragne-Montéglin', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Modane', transport_from_lng = 6.659, transport_from_lat = 45.195,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000e') - INTERVAL '90 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000000e' AND user_id = 'd0000000-0000-4000-a000-000000000018';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000018', 'accepted', 'Depuis Chorges', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000018', 'accepted', 'Depuis Vars', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Barcelonnette', transport_from_lng = 6.651, transport_from_lat = 44.387,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000e') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000000e' AND user_id = 'd0000000-0000-4000-a000-000000000015';
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Embrun', transport_from_lng = 6.495, transport_from_lat = 44.564,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000000f') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000000f' AND user_id = 'd0000000-0000-4000-a000-000000000012';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000012', 'accepted', 'Depuis Chorges', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000012', 'pending', 'Depuis Barcelonnette', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Guillestre', transport_from_lng = 6.65, transport_from_lat = 44.66,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000010') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000010' AND user_id = 'd0000000-0000-4000-a000-00000000000e';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-00000000000e', 'accepted', 'Depuis Briançon', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000000e', 'accepted', 'Depuis Saint-Bonnet-en-Champsaur', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-000000000010' AND user_id = 'd0000000-0000-4000-a000-00000000000c';
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000012') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000012' AND user_id = 'd0000000-0000-4000-a000-000000000017';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-000000000017', 'accepted', 'Depuis Gap', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000017', 'pending', 'Depuis Gap', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Embrun', transport_from_lng = 6.495, transport_from_lat = 44.564,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000013') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000013' AND user_id = 'd0000000-0000-4000-a000-000000000009';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000009', 'pending', 'Depuis Chorges', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000009', 'accepted', 'Depuis Embrun', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Chorges', transport_from_lng = 6.277, transport_from_lat = 44.549,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000014') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000014' AND user_id = 'd0000000-0000-4000-a000-00000000000b';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000b', 'pending', 'Depuis Modane', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000014' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000015') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000015' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000016', 'accepted', 'Depuis Embrun', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000016', 'accepted', 'Depuis Chorges', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000016') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000016' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000000a', 'pending', 'Depuis Briançon', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000017') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000017' AND user_id = 'd0000000-0000-4000-a000-00000000000d';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-00000000000d', 'accepted', 'Depuis Vars', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000d', 'accepted', 'Depuis Guillestre', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-000000000017' AND user_id = 'd0000000-0000-4000-a000-000000000007';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Guillestre', transport_from_lng = 6.65, transport_from_lat = 44.66,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001a') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001a' AND user_id = 'd0000000-0000-4000-a000-00000000000c';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-00000000000c', 'accepted', 'Depuis Guillestre', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000000c', 'pending', 'Depuis Saint-Bonnet-en-Champsaur', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001b') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001b' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000a', 'accepted', 'Depuis Modane', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-00000000000a', 'accepted', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-00000000001b' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001c') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001c' AND user_id = 'd0000000-0000-4000-a000-000000000011';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000011', 'accepted', 'Depuis Gap', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-000000000011', 'pending', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Guillestre', transport_from_lng = 6.65, transport_from_lat = 44.66,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001d') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001d' AND user_id = 'd0000000-0000-4000-a000-00000000000e';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000e', 'pending', 'Depuis Guillestre', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000001d' AND user_id = 'd0000000-0000-4000-a000-000000000017';
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-00000000001d' AND user_id = 'd0000000-0000-4000-a000-000000000013';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Veynes', transport_from_lng = 5.819, transport_from_lat = 44.534,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001e') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001e' AND user_id = 'd0000000-0000-4000-a000-00000000000f';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001e', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000000f', 'accepted', 'Depuis Chorges', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000001e' AND user_id = 'd0000000-0000-4000-a000-00000000000d';
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000001e' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001f') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001f' AND user_id = 'd0000000-0000-4000-a000-000000000011';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001f', 'd0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-000000000011', 'accepted', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000001f') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000001f' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000001f', 'd0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000a', 'pending', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-00000000001f' AND user_id = 'd0000000-0000-4000-a000-000000000018';
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000021') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000021' AND user_id = 'd0000000-0000-4000-a000-000000000007';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000021', 'd0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000007', 'accepted', 'Depuis Vars', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000021' AND user_id = 'd0000000-0000-4000-a000-00000000000d';
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Embrun', transport_from_lng = 6.495, transport_from_lat = 44.564,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000022') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000022' AND user_id = 'd0000000-0000-4000-a000-000000000009';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000022', 'd0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000009', 'accepted', 'Depuis Chorges', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000022', 'd0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000009', 'pending', 'Depuis Embrun', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000022') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000022' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000024') - INTERVAL '90 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000024' AND user_id = 'd0000000-0000-4000-a000-000000000004';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000024', 'd0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000004', 'accepted', 'Depuis Briançon', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-000000000024' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-000000000024' AND user_id = 'd0000000-0000-4000-a000-000000000003';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000025') - INTERVAL '90 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000025' AND user_id = 'd0000000-0000-4000-a000-00000000000d';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-00000000000d', 'accepted', 'Depuis Briançon', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000025', 'd0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-00000000000d', 'accepted', 'Depuis Briançon', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'bike' WHERE activity_id = 'a0000000-0000-4000-a000-000000000025' AND user_id = 'd0000000-0000-4000-a000-000000000005';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000027') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000027' AND user_id = 'd0000000-0000-4000-a000-000000000007';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000027', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000007', 'pending', 'Depuis Guillestre', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'public_transport' WHERE activity_id = 'a0000000-0000-4000-a000-000000000027' AND user_id = 'd0000000-0000-4000-a000-000000000006';
  UPDATE participations SET transport_type = 'on_foot' WHERE activity_id = 'a0000000-0000-4000-a000-000000000027' AND user_id = 'd0000000-0000-4000-a000-000000000002';
  UPDATE participations SET transport_type = 'car', transport_seats = 3,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000002c') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000002c' AND user_id = 'd0000000-0000-4000-a000-000000000011';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000002c', 'd0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000011', 'accepted', 'Depuis Embrun', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000002c', 'd0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-000000000011', 'accepted', 'Depuis Gap', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000002c') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000002c' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000002e') - INTERVAL '45 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000002e' AND user_id = 'd0000000-0000-4000-a000-00000000000a';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000000a', 'accepted', 'Depuis Briançon', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000002e', 'd0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000000a', 'accepted', 'Depuis Modane', 'Une place pour moi ? Je participe à l''essence.')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Guillestre', transport_from_lng = 6.65, transport_from_lat = 44.66,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000002f') - INTERVAL '90 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000002f' AND user_id = 'd0000000-0000-4000-a000-00000000000e';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000e', 'accepted', 'Depuis Guillestre', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-00000000002f', 'd0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000e', 'pending', 'Depuis Gap', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Briançon', transport_from_lng = 6.635, transport_from_lat = 44.897,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-00000000002f') - INTERVAL '60 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-00000000002f' AND user_id = 'd0000000-0000-4000-a000-000000000003';
  UPDATE participations SET transport_type = 'car', transport_seats = 4,
    transport_from_name = 'Gap', transport_from_lng = 6.079, transport_from_lat = 44.559,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000030') - INTERVAL '75 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000030' AND user_id = 'd0000000-0000-4000-a000-000000000016';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000030', 'd0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-000000000016', 'accepted', 'Depuis Modane', 'Je prends une place si c''est encore possible ?')
  ON CONFLICT DO NOTHING;
  UPDATE participations SET transport_type = 'car', transport_seats = 2,
    transport_from_name = 'Chorges', transport_from_lng = 6.277, transport_from_lat = 44.549,
    transport_departs_at = (SELECT starts_at FROM activities WHERE id = 'a0000000-0000-4000-a000-000000000031') - INTERVAL '90 minutes'
  WHERE activity_id = 'a0000000-0000-4000-a000-000000000031' AND user_id = 'd0000000-0000-4000-a000-00000000000b';
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-00000000000b', 'pending', 'Depuis Barcelonnette', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
  INSERT INTO seat_requests (activity_id, requester_id, driver_id, status, pickup_from, message)
  VALUES ('a0000000-0000-4000-a000-000000000031', 'd0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-00000000000b', 'pending', 'Depuis Vars', 'Je peux monter avec toi ? Je suis sur ta route.')
  ON CONFLICT DO NOTHING;
END $$;

-- ---------- (5) Re-datage : deux sorties par jour + covoiturages qui suivent (base live 00446, corps complet) ----------
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
    ),
    target AS (
      SELECT a.id, a.starts_at AS old_start,
             date_trunc('day', now())
               + make_interval(
                   days  => (1 + ((o.rn - 1) / 2))::int, -- 00457 : deux sorties par jour (50 sorties → 25 jours)
                   hours => (ARRAY[9,14,8,16,10,17,11,15])[((o.rn - 1) % 8) + 1],
                   mins  => (ARRAY[0,30,15,0,45,30,0,30])[((o.rn - 1) % 8) + 1]
                 ) AS new_start
      FROM activities a JOIN ordered o ON o.id = a.id
    ),
    -- Carpool departures and pickups follow their outing (same snapshot).
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
  ),
  target AS (
    SELECT a.id, a.starts_at AS old_start,
           date_trunc('day', now())
             + make_interval(
                 days  => (1 + ((o.rn - 1) / 2))::int, -- 00457 : deux sorties par jour (50 sorties → 25 jours)
                 hours => (ARRAY[9,14,8,16,10,17,11,15])[((o.rn - 1) % 8) + 1],
                 mins  => (ARRAY[0,30,15,0,45,30,0,30])[((o.rn - 1) % 8) + 1]
               ) AS new_start
    FROM activities a JOIN ordered o ON o.id = a.id
  ),
  -- Carpool departures and pickups follow their outing (same snapshot).
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
