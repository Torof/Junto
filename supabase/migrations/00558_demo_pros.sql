-- ============================================================================
-- 00558 — Cinq pros démo avec leur carnet complet (Scott 2026-10-27) :
--   Lise Arnaud (monitrice d'escalade, Ailefroide) · Théo Marchand (moniteur de
--   parapente, Chabre) · Les Ailes du Buëch (école, Laragne) · Nicolas
--   Pellissier (guide de haute montagne, Briançon) · Marion Isnard
--   (accompagnatrice, Guillestre). Chacun : profil approuvé avec métier,
--   3-4 sorties, photos de page et de sortie, avis sur le pro et sur les
--   sorties par les membres démo, sortie mise en avant. Les quatre voies du
--   pin sont représentées (photo, métier, univers, sport).
--
-- Même mécanique que 00334/00446 : auth.users à UUID fixe → trigger →
-- identité posée sous bypass ; tout est is_demo = true (rideau admin). Les
-- avis sont insérés directement : le gate « réservation acceptée et passée »
-- (00554) ne vaut que pour les nouveaux avis écrits depuis l'app.
-- Photos : Unsplash (licence Unsplash, usage libre) redimensionnées 1600 px,
-- déposées dans pro-photos/demo/pros/ ; quelques photos demo/ existantes
-- réutilisées. L'hôte vient de private.project_url(), jamais écrit ici.
-- Scott gère l'agenda (pro_availabilities) lui-même.
-- ============================================================================

-- ---------- (1) Comptes ----------
INSERT INTO auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000019', 'authenticated', 'authenticated', 'demo.lise@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000001a', 'authenticated', 'authenticated', 'demo.theo@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000001b', 'authenticated', 'authenticated', 'demo.ailes@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000001c', 'authenticated', 'authenticated', 'demo.nicolas@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-00000000001d', 'authenticated', 'authenticated', 'demo.marion@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_base text := private.project_url() || '/storage/v1/object/public/pro-photos/demo/';
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Identité des cinq comptes (le trigger a créé la ligne users).
  UPDATE public.users u SET
    display_name = d.display_name,
    avatar_url   = v_base || d.avatar,
    bio          = d.bio,
    tier         = 'pro',
    is_demo      = true
  FROM (VALUES
    ('d0000000-0000-4000-a000-000000000019'::uuid, 'Lise Arnaud', 'pros/lise-avatar.jpg', 'Monitrice d''escalade à Ailefroide. Falaise, grandes voies, via ferrata.'),
    ('d0000000-0000-4000-a000-00000000001a'::uuid, 'Théo Marchand', 'pros/theo-avatar.jpg', 'Moniteur de parapente à Chabre. Biplaces, pente-école, stages.'),
    ('d0000000-0000-4000-a000-00000000001b'::uuid, 'Les Ailes du Buëch', 'pros/ailes-avatar2.jpg', 'École de parapente à Laragne, site de Chabre.'),
    ('d0000000-0000-4000-a000-00000000001c'::uuid, 'Nicolas Pellissier', 'pros/nicolas-avatar.jpg', 'Guide de haute montagne à Briançon. Écrins, Clarée, canyons.'),
    ('d0000000-0000-4000-a000-00000000001d'::uuid, 'Marion Isnard', 'pros/marion-avatar.jpg', 'Accompagnatrice en montagne à Guillestre. Queyras à pied, en raquettes, en courant.')
  ) AS d(id, display_name, avatar, bio)
  WHERE u.id = d.id;

  -- ---------- (2) Pages pro ----------
  INSERT INTO public.pro_profiles
    (user_id, display_name, company_name, real_name, status, reviewed_at, profession, tagline, description,
     phone, email, instagram, website,
     primary_lng, primary_lat, primary_location, primary_location_name,
     pin_icon, pin_image_url, is_demo)
  VALUES
    ('d0000000-0000-4000-a000-000000000019', 'Lise Arnaud · Escalade Écrins', 'Lise Arnaud EI', 'Compte démo', 'approved', now() - interval '400 days', 'climbing_instructor', 'Falaise, grandes voies et via ferrata dans la Vallouise', 'Monitrice d''escalade diplômée d''État, installée à Ailefroide depuis dix ans. J''encadre de la première séance en falaise jusqu''aux grandes voies des Écrins, en petits groupes pour que chacun grimpe à son rythme. Matériel fourni, pédagogie douce, et toujours un œil sur la météo du massif.',
     '06 00 00 00 19', 'lise@escalade-ecrins.demo', 'escalade.ecrins', NULL,
     6.4357, 44.8866, extensions.ST_SetSRID(extensions.ST_MakePoint(6.4357, 44.8866), 4326)::extensions.geography, 'Ailefroide (Vallouise-Pelvoux)',
     NULL, v_base || 'pros/lise-pin.jpg', true),
    ('d0000000-0000-4000-a000-00000000001a', 'Théo Marchand · Vol libre Chabre', 'Théo Marchand EI', 'Compte démo', 'approved', now() - interval '400 days', 'paragliding_instructor', 'Biplaces et stages au décollage de Chabre', 'Moniteur de parapente depuis douze ans, basé à Laragne au pied de Chabre, l''un des plus beaux sites de vol d''Europe. Biplaces découverte ou thermiques, pente-école et stages d''initiation : je vole petit comité, et je ne décolle que quand les conditions sont vraiment bonnes.',
     '06 00 00 00 20', 'theo@vol-libre-chabre.demo', 'vollibre.chabre', 'https://vol-libre-chabre.demo',
     5.8266, 44.3156, extensions.ST_SetSRID(extensions.ST_MakePoint(5.8266, 44.3156), 4326)::extensions.geography, 'Laragne-Montéglin',
     NULL, NULL, true),
    ('d0000000-0000-4000-a000-00000000001b', 'Les Ailes du Buëch', 'Les Ailes du Buëch SARL', 'Compte démo', 'approved', now() - interval '400 days', 'school_office', 'École de parapente depuis 1994, au pied de Chabre', 'École de parapente labellisée, quatre moniteurs, des stages du débutant au cross toute la saison et des biplaces tous les jours quand ça vole. Site principal : Chabre, avec ses décollages orientés sud et nord qui offrent presque toujours une solution. Hébergement partenaire à Laragne.',
     '04 00 00 00 21', 'contact@ailes-du-buech.demo', 'ailesdubuech', 'https://ailes-du-buech.demo',
     5.83, 44.318, extensions.ST_SetSRID(extensions.ST_MakePoint(5.83, 44.318), 4326)::extensions.geography, 'Laragne-Montéglin',
     NULL, v_base || 'pros/ailes-logo2.jpg', true),
    ('d0000000-0000-4000-a000-00000000001c', 'Nicolas Pellissier', 'Nicolas Pellissier EI', 'Compte démo', 'approved', now() - interval '400 days', 'mountain_guide', 'Guide de haute montagne · alpinisme, ski de rando, canyon', 'Guide de haute montagne UIAGM, né à Briançon. L''été, les courses de neige et de glace des Écrins et les canyons de la Durance ; l''hiver, le ski de randonnée en Clarée et dans les Cerces. J''aime les petites cordées, les départs tôt et les sommets gagnés sans précipitation.',
     '06 00 00 00 22', 'nicolas@guide-ecrins.demo', NULL, 'https://guide-ecrins.demo',
     6.6357, 44.8963, extensions.ST_SetSRID(extensions.ST_MakePoint(6.6357, 44.8963), 4326)::extensions.geography, 'Briançon',
     'mountain', NULL, true),
    ('d0000000-0000-4000-a000-00000000001d', 'Marion Isnard · Queyras à pied', 'Marion Isnard EI', 'Compte démo', 'approved', now() - interval '400 days', 'mountain_leader', 'Accompagnatrice en montagne dans le Queyras', 'Accompagnatrice en montagne diplômée, installée à Guillestre. Je fais découvrir le Queyras à pied toute l''année : lacs d''altitude l''été, raquettes et soirées fondue l''hiver, trail en douceur sur les crêtes, et des randos-yoga pour prendre le temps. Groupes limités, allure tranquille, histoires du pays en prime.',
     '06 00 00 00 23', 'marion@queyras-a-pied.demo', 'queyras.apied', NULL,
     6.6493, 44.6603, extensions.ST_SetSRID(extensions.ST_MakePoint(6.6493, 44.6603), 4326)::extensions.geography, 'Guillestre',
     'snowshoeing', NULL, true)
  ON CONFLICT (user_id) DO NOTHING;

  -- ---------- (3) Sorties ----------
  INSERT INTO public.pro_offerings
    (id, pro_id, sport_id, title, description, level,
     location, location_name, duration, schedule_text,
     min_participants, max_participants, price_eur, price_unit,
     equipment_provided, equipment_required, is_demo)
  VALUES
    ('b0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000019', (SELECT id FROM public.sports WHERE key = 'climbing-sport'),
     'Initiation falaise à Ailefroide', 'Une demi-journée pour découvrir l''escalade sur les dalles-écoles d''Ailefroide : nœud d''encordement, assurage, premières voies en moulinette. Dès 8 ans, en famille ou entre amis. Tout le matériel est fourni.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.4357, 44.8866), 4326)::extensions.geography, 'Ailefroide', INTERVAL '3 hours', 'Mai à octobre · matin ou après-midi',
     2, 6, 45, 'person',
     '["Baudrier", "Casque", "Chaussons d''escalade", "Cordes et dégaines"]'::jsonb, '["Tenue souple", "Eau et encas", "Crème solaire"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000019', (SELECT id FROM public.sports WHERE key = 'climbing-multipitch'),
     'Grande voie découverte · Tête de la Draye', 'Votre première grande voie, encordés sur plusieurs longueurs face au Pelvoux. Vous savez grimper en moulinette du 5a : je vous apprends les relais, la gestion de la corde et le rappel. Une journée dense, au sommet vers 14 h.', 'Intermédiaire',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.4357, 44.8866), 4326)::extensions.geography, 'Ailefroide', INTERVAL '7 hours', 'Juin à septembre · départ 7h30',
     1, 2, 190, 'person',
     '["Baudrier et casque", "Corde, dégaines, coinceurs", "Chaussons si besoin"]'::jsonb, '["Sac 20 L", "1,5 L d''eau et pique-nique", "Veste coupe-vent", "Chaussures d''approche"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000019', (SELECT id FROM public.sports WHERE key = 'climbing-sport'),
     'Stage ado · 3 jours en falaise', 'Trois jours pour les 12-17 ans : techniques de pied, assurage en tête, lecture de voie, et une grande voie facile le dernier jour. Groupe de 8 maximum, deux encadrants. Goûter inclus, bonne humeur obligatoire.', 'Débutant à intermédiaire',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.4357, 44.8866), 4326)::extensions.geography, 'Ailefroide', INTERVAL '3 days', 'Vacances scolaires · juillet et août',
     4, 8, 240, 'person',
     '["Baudrier, casque, chaussons", "Cordes et dégaines"]'::jsonb, '["Tenue de sport", "Gourde", "Casquette"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000019', (SELECT id FROM public.sports WHERE key = 'via-ferrata'),
     'Via ferrata des Vigneaux', 'La via ferrata de la Falaise de la Balme, au-dessus des Vigneaux : échelles, passerelle et un pont de singe pour finir. Accessible dès 1,40 m, encadrement et matériel compris. Vue plongeante sur la vallée de la Durance.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.5306, 44.8172), 4326)::extensions.geography, 'Les Vigneaux', INTERVAL '3 hours 30 minutes', 'Avril à octobre · 9h ou 14h',
     2, 8, 55, 'person',
     '["Baudrier et longe de via ferrata", "Casque"]'::jsonb, '["Gants fins", "Chaussures fermées", "Eau"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000001a', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Biplace découverte depuis Chabre', 'Vingt minutes de vol au-dessus du Buëch, assis dans la sellette, les mains libres pour les photos. Briefing, montée en navette au décollage, atterrissage en douceur à Laragne. Dès 6 ans, jusqu''à 110 kg.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Décollage de Chabre', INTERVAL '1 hour 30 minutes', 'Toute l''année selon météo · navette depuis Laragne',
     1, 4, 95, 'person',
     '["Sellette passager et casque", "Navette au décollage"]'::jsonb, '["Chaussures montantes", "Pantalon long", "Lunettes de soleil"]'::jsonb, true),
    ('b0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-00000000001a', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Biplace thermique · le grand vol', 'Quand les thermiques montent, on monte avec eux : quarante-cinq minutes à une heure de vol, prise d''altitude, cheminement le long de la crête de Chabre. Pour ceux qui veulent sentir ce qu''est vraiment le vol libre.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Décollage de Chabre', INTERVAL '2 hours 30 minutes', 'Avril à octobre · départs 12h et 14h30',
     1, 2, 150, 'person',
     '["Sellette passager et casque", "Vidéo du vol"]'::jsonb, '["Chaussures montantes", "Veste chaude même l''été", "Estomac tranquille"]'::jsonb, true),
    ('b0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-00000000001a', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Journée pente-école', 'Une journée pour apprendre à gonfler et contrôler une aile sur la pente-école de Laragne, puis les premiers décollages de quelques mètres. Le vrai début du parapente, les pieds encore pas loin du sol.', 'Débutant',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.819, 44.308), 4326)::extensions.geography, 'Pente-école de Laragne', INTERVAL '6 hours', 'Mars à novembre · 9h-16h',
     2, 6, 110, 'person',
     '["Aile école, sellette, casque", "Radio"]'::jsonb, '["Chaussures montantes", "Gants", "Pique-nique et 2 L d''eau"]'::jsonb, true),
    ('b0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000001a', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Stage initiation · 5 jours', 'Cinq jours de la pente-école aux premiers grands vols encadrés par radio depuis Chabre. Théorie le soir (aérologie, matériel, règles de l''air), pratique toute la journée. Le carnet de vol signé à la fin.', 'Débutant',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Chabre et pente-école de Laragne', INTERVAL '5 days', 'Stages du lundi au vendredi · d''avril à octobre',
     3, 6, 650, 'person',
     '["Tout le matériel de vol", "Radio", "Navettes"]'::jsonb, '["Chaussures montantes", "Vêtements chauds", "Cahier"]'::jsonb, true),
    ('b0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-00000000001b', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Stage initiation · 5 jours', 'Le stage de base : pente-école les deux premiers jours, puis premiers vols depuis le petit décollage et enfin Chabre, guidés par radio. Cours théoriques chaque fin d''après-midi. Huit stagiaires maximum pour deux moniteurs.', 'Débutant',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Chabre', INTERVAL '5 days', 'Du lundi au vendredi · mars à novembre',
     4, 8, 590, 'person',
     '["Matériel complet", "Radio", "Navettes", "Assurance stage"]'::jsonb, '["Chaussures montantes", "Gants", "Vêtements chauds"]'::jsonb, true),
    ('b0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-00000000001b', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Stage perfectionnement · 5 jours', 'Pour les pilotes autonomes en vol calme : exploitation des thermiques, gestion du groupe en l''air, premiers transitions et petits cross au-dessus du Buëch. Débriefs vidéo chaque soir.', 'Intermédiaire',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Chabre', INTERVAL '5 days', 'Du lundi au vendredi · avril à septembre',
     3, 6, 620, 'person',
     '["Radio", "Navettes", "Débrief vidéo"]'::jsonb, '["Votre matériel de vol révisé", "Brevet initial", "Vario"]'::jsonb, true),
    ('b0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-00000000001b', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Vol biplace', 'Le vol découverte de l''école : quinze à vingt-cinq minutes au-dessus du Buëch avec l''un de nos quatre moniteurs biplaceurs. Plusieurs départs par jour, réservation conseillée le week-end.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Chabre', INTERVAL '1 hour 30 minutes', 'Tous les jours selon météo · 10h, 12h, 14h, 16h',
     1, 6, 90, 'person',
     '["Sellette passager et casque", "Navette"]'::jsonb, '["Chaussures fermées", "Pantalon long"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-00000000001b', (SELECT id FROM public.sports WHERE key = 'paragliding'),
     'Stage cross · 3 jours', 'Trois jours pour partir loin : stratégie de vol, lecture des nuages, transitions, et des cross de 30 à 60 km avec récupération en navette. Pilotes confirmés, 50 heures de vol minimum.', 'Avancé',
     extensions.ST_SetSRID(extensions.ST_MakePoint(5.801, 44.33), 4326)::extensions.geography, 'Chabre et Buëch', INTERVAL '3 days', 'Juin à août · selon les prévisions',
     2, 4, 420, 'person',
     '["Radio", "Récupération en navette", "Analyse des traces"]'::jsonb, '["Matériel de vol complet", "GPS ou vario-GPS", "Brevet de pilote"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-00000000001c', (SELECT id FROM public.sports WHERE key = 'mountaineering'),
     'Dôme des Écrins · 2 jours', 'Le 4 000 des Écrins en deux jours : montée au refuse des Écrins par le Glacier Blanc, départ nocturne, arête sommitale au lever du soleil. Il faut une bonne condition physique et une première expérience de cramponnage.', 'Intermédiaire',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.416, 44.922), 4326)::extensions.geography, 'Pré de Madame Carle (Pelvoux)', INTERVAL '2 days', 'Juin à septembre · nuit au refuge des Écrins',
     1, 2, 520, 'person',
     '["Corde, matériel de sécurité glacier", "Prêt de crampons et piolet si besoin"]'::jsonb, '["Chaussures cramponnables", "Baudrier et casque", "Sac 35 L, vêtements chauds", "Demi-pension au refuge (non comprise)"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-00000000001c', (SELECT id FROM public.sports WHERE key = 'mountaineering'),
     'Initiation glacier · Glacier Blanc', 'Une journée pour apprendre à marcher en crampons, s''encorder et évoluer sur un glacier, au pied de la Barre des Écrins. Le meilleur premier pas avant une course de neige.', 'Débutant',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.416, 44.922), 4326)::extensions.geography, 'Glacier Blanc (Pelvoux)', INTERVAL '8 hours', 'Juin à septembre · départ 6h30 du Pré de Madame Carle',
     2, 4, 160, 'person',
     '["Crampons, piolet, baudrier, casque", "Corde"]'::jsonb, '["Chaussures de montagne rigides", "Gants, bonnet, lunettes", "Pique-nique et 1,5 L d''eau"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000001c', (SELECT id FROM public.sports WHERE key = 'ski-touring'),
     'Ski de rando à la journée · Cerces, Clarée', 'Une journée de ski de randonnée adaptée au groupe et à la neige du jour : vallée de la Clarée, Cerces, Montgenèvre. 800 à 1 200 m de dénivelé, descentes choisies pour le plaisir, pas pour la photo.', 'Intermédiaire',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.602, 45.019), 4326)::extensions.geography, 'Névache (vallée de la Clarée)', INTERVAL '7 hours', 'Décembre à mai · rendez-vous 8h à Névache',
     2, 5, 95, 'person',
     '["DVA, pelle, sonde si besoin", "Lecture de la nivologie du jour"]'::jsonb, '["Skis de rando, peaux, couteaux", "Casque conseillé", "Pique-nique"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-00000000001c', (SELECT id FROM public.sports WHERE key = 'canyoning'),
     'Canyon du Fournel', 'Le canyon du Fournel au-dessus de L''Argentière : toboggans, sauts facultatifs et un rappel de 12 m dans une gorge étroite. Dès 12 ans, à l''aise dans l''eau. Combinaison fournie, eau fraîche garantie.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.523, 44.792), 4326)::extensions.geography, 'Canyon du Fournel (L''Argentière-la-Bessée)', INTERVAL '4 hours', 'Juin à septembre · 9h et 13h30',
     2, 8, 65, 'person',
     '["Combinaison néoprène", "Casque, baudrier, longe", "Sac étanche"]'::jsonb, '["Maillot de bain", "Baskets qui vont dans l''eau", "Serviette"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-00000000001d', (SELECT id FROM public.sports WHERE key = 'hiking'),
     'Les lacs du Queyras · journée', 'Une boucle par les lacs Sainte-Anne et Miroir au-dessus de Ceillac, ou les lacs de Saint-Véran selon la saison. 700 m de dénivelé à allure tranquille, pause longue au bord de l''eau, lecture du paysage et des alpages.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.869, 44.701), 4326)::extensions.geography, 'Saint-Véran', INTERVAL '7 hours', 'Juin à octobre · départ 8h30',
     3, 10, 38, 'person',
     '["Bâtons si besoin", "Trousse de secours"]'::jsonb, '["Chaussures de randonnée", "Pique-nique et 1,5 L d''eau", "Veste chaude et coupe-vent"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-00000000001d', (SELECT id FROM public.sports WHERE key = 'snowshoeing'),
     'Raquettes nocturne et fondue', 'Deux heures de raquettes à la frontale dans les mélèzes de Ceillac, puis une fondue dans un chalet d''alpage. Le silence de la neige la nuit, et le ciel du Queyras, l''un des plus noirs de France.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.776, 44.668), 4326)::extensions.geography, 'Ceillac', INTERVAL '3 hours 30 minutes', 'Décembre à mars · mardi et vendredi 17h30',
     4, 12, 45, 'person',
     '["Raquettes et bâtons", "Frontale", "Fondue et boissons"]'::jsonb, '["Chaussures chaudes et imperméables", "Gants, bonnet", "Une bonne faim"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000001d', (SELECT id FROM public.sports WHERE key = 'trail-running'),
     'Trail découverte · crêtes de Guillestre', 'Quinze kilomètres et 600 m de dénivelé sur les crêtes au-dessus de Guillestre, en courant et en marchant. Conseils d''allure, de foulée en descente et d''alimentation. On regarde le paysage, on ne regarde pas la montre.', 'Intermédiaire',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.6493, 44.6603), 4326)::extensions.geography, 'Guillestre', INTERVAL '3 hours', 'Mai à octobre · samedi 8h',
     2, 8, 30, 'person',
     '["Ravitaillement"]'::jsonb, '["Chaussures de trail", "Sac ou ceinture avec 1 L d''eau", "Coupe-vent léger"]'::jsonb, true),
    ('b0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-00000000001d', (SELECT id FROM public.sports WHERE key = 'yoga'),
     'Rando-yoga au lac de Roue', 'Une petite marche jusqu''au lac de Roue, puis une heure de yoga doux au bord de l''eau et une méditation guidée face aux mélèzes. Retour tranquille. Aucune pratique du yoga requise, les tapis sont prêtés.', 'Tous niveaux',
     extensions.ST_SetSRID(extensions.ST_MakePoint(6.733, 44.713), 4326)::extensions.geography, 'Lac de Roue (Arvieux)', INTERVAL '5 hours', 'Juillet et août · mercredi 8h',
     3, 8, 48, 'person',
     '["Tapis de yoga", "Tisane"]'::jsonb, '["Tenue souple et chaussures de marche", "Petit-déjeuner pris", "Eau"]'::jsonb, true)
  ON CONFLICT (id) DO NOTHING;

  -- Sortie mise en avant (00554).
  UPDATE public.pro_profiles SET featured_offering_id = f.oid FROM (VALUES
    ('d0000000-0000-4000-a000-000000000019'::uuid, 'b0000000-0000-4000-a000-000000000005'::uuid),
    ('d0000000-0000-4000-a000-00000000001a'::uuid, 'b0000000-0000-4000-a000-000000000009'::uuid),
    ('d0000000-0000-4000-a000-00000000001b'::uuid, 'b0000000-0000-4000-a000-00000000000d'::uuid),
    ('d0000000-0000-4000-a000-00000000001c'::uuid, 'b0000000-0000-4000-a000-000000000011'::uuid),
    ('d0000000-0000-4000-a000-00000000001d'::uuid, 'b0000000-0000-4000-a000-000000000015'::uuid)
  ) AS f(uid, oid) WHERE user_id = f.uid;

  -- ---------- (4) Photos ----------
  INSERT INTO public.pro_profile_photos (pro_id, photo_url, order_index) VALUES
    ('d0000000-0000-4000-a000-000000000019', v_base || 'pros/lise-1.jpg', 0),
    ('d0000000-0000-4000-a000-000000000019', v_base || 'pros/lise-2.jpg', 1),
    ('d0000000-0000-4000-a000-000000000019', v_base || 'pros/lise-3.jpg', 2),
    ('d0000000-0000-4000-a000-000000000019', v_base || 'pros/lise-4.jpg', 3),
    ('d0000000-0000-4000-a000-000000000019', v_base || 'pros/lise-5.jpg', 4),
    ('d0000000-0000-4000-a000-000000000019', v_base || 'pros/lise-6.jpg', 5),
    ('d0000000-0000-4000-a000-00000000001a', v_base || 'pros/theo-1.jpg', 0),
    ('d0000000-0000-4000-a000-00000000001a', v_base || 'pros/theo-2.jpg', 1),
    ('d0000000-0000-4000-a000-00000000001a', v_base || 'pros/theo-3.jpg', 2),
    ('d0000000-0000-4000-a000-00000000001a', v_base || 'pros/theo-4.jpg', 3),
    ('d0000000-0000-4000-a000-00000000001a', v_base || 'pros/theo-5.jpg', 4),
    ('d0000000-0000-4000-a000-00000000001b', v_base || 'pros/ailes-1.jpg', 0),
    ('d0000000-0000-4000-a000-00000000001b', v_base || 'pros/ailes-2.jpg', 1),
    ('d0000000-0000-4000-a000-00000000001b', v_base || 'pros/ailes-3.jpg', 2),
    ('d0000000-0000-4000-a000-00000000001b', v_base || 'pros/ailes-4.jpg', 3),
    ('d0000000-0000-4000-a000-00000000001b', v_base || 'biplace-2.jpg', 4),
    ('d0000000-0000-4000-a000-00000000001c', v_base || 'pros/nicolas-1.jpg', 0),
    ('d0000000-0000-4000-a000-00000000001c', v_base || 'pros/nicolas-2.jpg', 1),
    ('d0000000-0000-4000-a000-00000000001c', v_base || 'pros/nicolas-3.jpg', 2),
    ('d0000000-0000-4000-a000-00000000001c', v_base || 'pros/nicolas-4.jpg', 3),
    ('d0000000-0000-4000-a000-00000000001c', v_base || 'pros/nicolas-5.jpg', 4),
    ('d0000000-0000-4000-a000-00000000001c', v_base || 'canyon-6.jpg', 5),
    ('d0000000-0000-4000-a000-00000000001d', v_base || 'pros/marion-1.jpg', 0),
    ('d0000000-0000-4000-a000-00000000001d', v_base || 'pros/marion-2.jpg', 1),
    ('d0000000-0000-4000-a000-00000000001d', v_base || 'pros/marion-3.jpg', 2),
    ('d0000000-0000-4000-a000-00000000001d', v_base || 'pros/marion-4.jpg', 3),
    ('d0000000-0000-4000-a000-00000000001d', v_base || 'pros/marion-5.jpg', 4),
    ('d0000000-0000-4000-a000-00000000001d', v_base || 'pros/marion-6.jpg', 5)
  ON CONFLICT (pro_id, order_index) DO NOTHING;

  INSERT INTO public.pro_offering_photos (offering_id, photo_url, order_index) VALUES
    ('b0000000-0000-4000-a000-000000000005', v_base || 'pros/lise-1.jpg', 0),
    ('b0000000-0000-4000-a000-000000000005', v_base || 'pros/lise-5.jpg', 1),
    ('b0000000-0000-4000-a000-000000000006', v_base || 'pros/lise-7.jpg', 0),
    ('b0000000-0000-4000-a000-000000000006', v_base || 'pros/lise-6.jpg', 1),
    ('b0000000-0000-4000-a000-000000000006', v_base || 'pros/lise-8.jpg', 2),
    ('b0000000-0000-4000-a000-000000000007', v_base || 'pros/lise-9.jpg', 0),
    ('b0000000-0000-4000-a000-000000000007', v_base || 'pros/lise-10.jpg', 1),
    ('b0000000-0000-4000-a000-000000000008', v_base || 'pros/lise-12.jpg', 0),
    ('b0000000-0000-4000-a000-000000000008', v_base || 'pros/lise-13.jpg', 1),
    ('b0000000-0000-4000-a000-000000000008', v_base || 'pros/lise-14.jpg', 2),
    ('b0000000-0000-4000-a000-000000000009', v_base || 'pros/theo-1.jpg', 0),
    ('b0000000-0000-4000-a000-000000000009', v_base || 'biplace-1.jpg', 1),
    ('b0000000-0000-4000-a000-00000000000a', v_base || 'pros/theo-6.jpg', 0),
    ('b0000000-0000-4000-a000-00000000000a', v_base || 'pros/theo-4.jpg', 1),
    ('b0000000-0000-4000-a000-00000000000b', v_base || 'pros/theo-3.jpg', 0),
    ('b0000000-0000-4000-a000-00000000000b', v_base || 'pros/theo-7.jpg', 1),
    ('b0000000-0000-4000-a000-00000000000c', v_base || 'pros/theo-2.jpg', 0),
    ('b0000000-0000-4000-a000-00000000000c', v_base || 'pros/theo-8.jpg', 1),
    ('b0000000-0000-4000-a000-00000000000d', v_base || 'pros/ailes-5.jpg', 0),
    ('b0000000-0000-4000-a000-00000000000d', v_base || 'pros/ailes-6.jpg', 1),
    ('b0000000-0000-4000-a000-00000000000e', v_base || 'pros/ailes-3.jpg', 0),
    ('b0000000-0000-4000-a000-00000000000e', v_base || 'pros/ailes-7.jpg', 1),
    ('b0000000-0000-4000-a000-00000000000f', v_base || 'biplace-3.jpg', 0),
    ('b0000000-0000-4000-a000-00000000000f', v_base || 'pros/ailes-4.jpg', 1),
    ('b0000000-0000-4000-a000-000000000010', v_base || 'pros/ailes-8.jpg', 0),
    ('b0000000-0000-4000-a000-000000000010', v_base || 'pros/ailes-2.jpg', 1),
    ('b0000000-0000-4000-a000-000000000011', v_base || 'pros/nicolas-1.jpg', 0),
    ('b0000000-0000-4000-a000-000000000011', v_base || 'pros/nicolas-3.jpg', 1),
    ('b0000000-0000-4000-a000-000000000011', v_base || 'pros/nicolas-6.jpg', 2),
    ('b0000000-0000-4000-a000-000000000012', v_base || 'pros/nicolas-2.jpg', 0),
    ('b0000000-0000-4000-a000-000000000012', v_base || 'pros/nicolas-4.jpg', 1),
    ('b0000000-0000-4000-a000-000000000013', v_base || 'pros/nicolas-7.jpg', 0),
    ('b0000000-0000-4000-a000-000000000013', v_base || 'pros/nicolas-8.jpg', 1),
    ('b0000000-0000-4000-a000-000000000013', v_base || 'pros/nicolas-9.jpg', 2),
    ('b0000000-0000-4000-a000-000000000014', v_base || 'canyon-2.jpg', 0),
    ('b0000000-0000-4000-a000-000000000014', v_base || 'canyon-3.jpg', 1),
    ('b0000000-0000-4000-a000-000000000015', v_base || 'pros/marion-1.jpg', 0),
    ('b0000000-0000-4000-a000-000000000015', v_base || 'pros/marion-6.jpg', 1),
    ('b0000000-0000-4000-a000-000000000015', v_base || 'pros/marion-7.jpg', 2),
    ('b0000000-0000-4000-a000-000000000016', v_base || 'pros/marion-3.jpg', 0),
    ('b0000000-0000-4000-a000-000000000016', v_base || 'pros/marion-8.jpg', 1),
    ('b0000000-0000-4000-a000-000000000016', v_base || 'pros/marion-9.jpg', 2),
    ('b0000000-0000-4000-a000-000000000017', v_base || 'pros/marion-4.jpg', 0),
    ('b0000000-0000-4000-a000-000000000017', v_base || 'pros/marion-10.jpg', 1),
    ('b0000000-0000-4000-a000-000000000017', v_base || 'pros/marion-11.jpg', 2),
    ('b0000000-0000-4000-a000-000000000018', v_base || 'pros/marion-5.jpg', 0),
    ('b0000000-0000-4000-a000-000000000018', v_base || 'pros/marion-12.jpg', 1),
    ('b0000000-0000-4000-a000-000000000018', v_base || 'pros/marion-2.jpg', 2)
  ON CONFLICT (offering_id, order_index) DO NOTHING;

  -- ---------- (5) Avis (membres démo, étalés sur douze mois) ----------
  INSERT INTO public.pro_reviews (pro_id, reviewer_id, rating, body, created_at, updated_at) VALUES
    ('d0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000002', 5, 'Première grande voie de ma vie avec Lise, je n''ai jamais eu peur. Elle explique chaque geste, et on grimpe vraiment.', now() - interval '28 days', now() - interval '28 days'),
    ('d0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000005', 5, 'Initiation en famille, les enfants ont adoré. Patiente, précise, rassurante.', now() - interval '89 days', now() - interval '89 days'),
    ('d0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-00000000000b', 4, 'Très bon stage ado pour mon fils, il est revenu avec les bases et l''envie de continuer. Un peu court, trois jours !', now() - interval '150 days', now() - interval '150 days'),
    ('d0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000012', 5, 'La via des Vigneaux encadrée, c''était parfait pour une première. Lise met tout le monde à l''aise.', now() - interval '211 days', now() - interval '211 days'),
    ('d0000000-0000-4000-a000-000000000019', 'd0000000-0000-4000-a000-000000000017', 5, 'Grimpeur depuis longtemps, j''ai pris une journée pour apprendre les relais proprement. Pédagogue et rigoureuse.', now() - interval '272 days', now() - interval '272 days'),
    ('d0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-000000000003', 5, 'Biplace thermique inoubliable. Théo lit le ciel comme un livre et explique tout pendant le vol.', now() - interval '29 days', now() - interval '29 days'),
    ('d0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-000000000009', 5, 'Stage initiation, cinq jours denses et très bien menés. Premier grand vol le jeudi, encore des frissons.', now() - interval '90 days', now() - interval '90 days'),
    ('d0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000c', 4, 'Vol découverte parfait pour une première fois. Attente un peu longue au décollage à cause du vent, mais sécurité d''abord.', now() - interval '151 days', now() - interval '151 days'),
    ('d0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-00000000000f', 5, 'J''ai offert un biplace à mon père de 68 ans : il en parle encore.', now() - interval '212 days', now() - interval '212 days'),
    ('d0000000-0000-4000-a000-00000000001a', 'd0000000-0000-4000-a000-000000000014', 5, 'Pente-école super progressive. On comprend l''aile avant de la subir.', now() - interval '273 days', now() - interval '273 days'),
    ('d0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000004', 5, 'École sérieuse, matériel récent, moniteurs patients. Mon stage initiation il y a deux ans, je vole toujours.', now() - interval '30 days', now() - interval '30 days'),
    ('d0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000007', 4, 'Bon stage perf, débriefs vidéo très utiles. Un groupe un peu hétérogène la première année.', now() - interval '91 days', now() - interval '91 days'),
    ('d0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-00000000000a', 5, 'Vol biplace réservé la veille, tout s''est enchaîné sans attente.', now() - interval '152 days', now() - interval '152 days'),
    ('d0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000010', 5, 'Le stage cross m''a fait franchir un cap. Encadrement à la hauteur du site.', now() - interval '213 days', now() - interval '213 days'),
    ('d0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000015', 4, 'Très bonne école, structure rodée. On est un peu un numéro en haute saison, mais le vol reste magique.', now() - interval '274 days', now() - interval '274 days'),
    ('d0000000-0000-4000-a000-00000000001b', 'd0000000-0000-4000-a000-000000000018', 5, 'Quatre moniteurs, tous excellents. J''ai fait mon initiation puis mon perf ici.', now() - interval '335 days', now() - interval '335 days'),
    ('d0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000006', 5, 'Le Dôme avec Nicolas : sérieux, calme, et une vraie attention à la cordée. Sommet au lever du soleil, je ne l''oublierai pas.', now() - interval '31 days', now() - interval '31 days'),
    ('d0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000008', 5, 'Initiation glacier parfaite, j''ai appris plus en une journée qu''en trois ans de lecture.', now() - interval '92 days', now() - interval '92 days'),
    ('d0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-00000000000d', 4, 'Belle journée de ski de rando, Nicolas choisit bien ses pentes. Rythme soutenu pour moi !', now() - interval '153 days', now() - interval '153 days'),
    ('d0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000011', 5, 'Canyon du Fournel en famille, les ados ont adoré les toboggans. Guide très pédagogue.', now() - interval '214 days', now() - interval '214 days'),
    ('d0000000-0000-4000-a000-00000000001c', 'd0000000-0000-4000-a000-000000000013', 5, 'Un guide qui explique pourquoi on fait demi-tour. C''est ça que je cherche.', now() - interval '275 days', now() - interval '275 days'),
    ('d0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000007', 5, 'Marion connaît chaque fleur et chaque hameau. Les lacs du Queyras à son rythme, c''est un cadeau.', now() - interval '32 days', now() - interval '32 days'),
    ('d0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-00000000000a', 5, 'La nocturne en raquettes avec la fondue au bout : notre meilleure soirée de la semaine.', now() - interval '93 days', now() - interval '93 days'),
    ('d0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-00000000000e', 4, 'Trail découverte très sympa, j''ai appris à descendre sans me casser les genoux. Un peu court.', now() - interval '154 days', now() - interval '154 days'),
    ('d0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000014', 5, 'Rando-yoga au lac de Roue, je n''avais jamais fait de yoga, j''y retourne cet été.', now() - interval '215 days', now() - interval '215 days'),
    ('d0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000016', 5, 'Accompagnatrice attentive, groupe soudé en une heure. Et les histoires du Queyras !', now() - interval '276 days', now() - interval '276 days'),
    ('d0000000-0000-4000-a000-00000000001d', 'd0000000-0000-4000-a000-000000000003', 3, 'Belle sortie mais allure vraiment lente pour moi. À réserver aux contemplatifs.', now() - interval '337 days', now() - interval '337 days')
  ON CONFLICT (pro_id, reviewer_id) DO NOTHING;

  INSERT INTO public.offering_reviews (offering_id, reviewer_id, rating, body, created_at, updated_at) VALUES
    ('b0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000005', 5, 'Les gamins ont grimpé toute la matinée, Lise gère un groupe comme personne.', now() - interval '17 days', now() - interval '17 days'),
    ('b0000000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-00000000000e', 4, 'Super découverte, le matériel est nickel.', now() - interval '64 days', now() - interval '64 days'),
    ('b0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000002', 5, 'Sommet à 14 h comme promis, et j''ai compris les relais pour de bon.', now() - interval '18 days', now() - interval '18 days'),
    ('b0000000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000017', 5, 'Une vraie journée de montagne, pas une promenade.', now() - interval '65 days', now() - interval '65 days'),
    ('b0000000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-00000000000b', 4, 'Mon fils a adoré, deux encadrants pour huit, on sent le sérieux.', now() - interval '19 days', now() - interval '19 days'),
    ('b0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000012', 5, 'Le pont de singe à la fin, quel moment ! Encadrement impeccable.', now() - interval '20 days', now() - interval '20 days'),
    ('b0000000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000008', 4, 'Belle via, un peu de monde le week-end mais Lise anticipe.', now() - interval '67 days', now() - interval '67 days'),
    ('b0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000000c', 4, 'Belle première, atterrissage tout doux.', now() - interval '21 days', now() - interval '21 days'),
    ('b0000000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-00000000000f', 5, 'Mon père a adoré, et moi aussi en le regardant.', now() - interval '68 days', now() - interval '68 days'),
    ('b0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000003', 5, 'Une heure dans les thermiques, on se prend pour un vautour.', now() - interval '22 days', now() - interval '22 days'),
    ('b0000000-0000-4000-a000-00000000000a', 'd0000000-0000-4000-a000-000000000006', 5, 'Le grand vol, c''est vraiment autre chose que la découverte.', now() - interval '69 days', now() - interval '69 days'),
    ('b0000000-0000-4000-a000-00000000000b', 'd0000000-0000-4000-a000-000000000014', 5, 'Enfin compris comment gonfler une aile sans courir partout.', now() - interval '23 days', now() - interval '23 days'),
    ('b0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-000000000009', 5, 'Cinq jours et un premier grand vol, encadrement radio rassurant.', now() - interval '24 days', now() - interval '24 days'),
    ('b0000000-0000-4000-a000-00000000000c', 'd0000000-0000-4000-a000-00000000000d', 4, 'Très bon stage, météo capricieuse le mardi mais rattrapée.', now() - interval '71 days', now() - interval '71 days'),
    ('b0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000004', 5, 'Le stage qui m''a fait aimer le parapente.', now() - interval '25 days', now() - interval '25 days'),
    ('b0000000-0000-4000-a000-00000000000d', 'd0000000-0000-4000-a000-000000000016', 4, 'Bien organisé, théorie claire, premiers vols magiques.', now() - interval '72 days', now() - interval '72 days'),
    ('b0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000007', 4, 'Les débriefs vidéo valent le stage à eux seuls.', now() - interval '26 days', now() - interval '26 days'),
    ('b0000000-0000-4000-a000-00000000000e', 'd0000000-0000-4000-a000-000000000018', 5, 'J''ai enfin compris les thermiques.', now() - interval '73 days', now() - interval '73 days'),
    ('b0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-00000000000a', 5, 'Aucune attente, un moniteur au top, vingt minutes de bonheur.', now() - interval '27 days', now() - interval '27 days'),
    ('b0000000-0000-4000-a000-00000000000f', 'd0000000-0000-4000-a000-000000000015', 4, 'Très bien, un peu rapide en pleine saison.', now() - interval '74 days', now() - interval '74 days'),
    ('b0000000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000010', 5, 'Mon premier 50 km, récupéré en navette au bout du Buëch.', now() - interval '28 days', now() - interval '28 days'),
    ('b0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-000000000006', 5, 'Deux jours parfaits, du refuge à l''arête. Niveau requis réel, ne pas tricher.', now() - interval '29 days', now() - interval '29 days'),
    ('b0000000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-000000000013', 4, 'Course magnifique, retour long. Prévoyez des jambes.', now() - interval '76 days', now() - interval '76 days'),
    ('b0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000008', 5, 'On marche en crampons avec confiance dès midi.', now() - interval '30 days', now() - interval '30 days'),
    ('b0000000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000002', 5, 'La Barre des Écrins au-dessus de la tête toute la journée.', now() - interval '77 days', now() - interval '77 days'),
    ('b0000000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-00000000000d', 4, 'Neige de rêve en Clarée, Nicolas connaît chaque combe.', now() - interval '31 days', now() - interval '31 days'),
    ('b0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000011', 5, 'Toboggans, rappel, fous rires : parfait.', now() - interval '32 days', now() - interval '32 days'),
    ('b0000000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000016', 4, 'Eau glacée mais combinaison efficace, encadrement serein.', now() - interval '79 days', now() - interval '79 days'),
    ('b0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000007', 5, 'Les lacs Sainte-Anne et Miroir, pause d''une heure au bord de l''eau. Parfait.', now() - interval '33 days', now() - interval '33 days'),
    ('b0000000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000003', 3, 'Très beau, mais le rythme tranquille m''a frustré.', now() - interval '80 days', now() - interval '80 days'),
    ('b0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-00000000000a', 5, 'Le ciel étoilé et la fondue, inoubliable.', now() - interval '34 days', now() - interval '34 days'),
    ('b0000000-0000-4000-a000-000000000016', 'd0000000-0000-4000-a000-000000000009', 5, 'Nos enfants de 9 et 11 ans ont tenu sans problème.', now() - interval '81 days', now() - interval '81 days'),
    ('b0000000-0000-4000-a000-000000000017', 'd0000000-0000-4000-a000-00000000000e', 4, 'Bons conseils de descente, groupe bienveillant.', now() - interval '12 days', now() - interval '12 days'),
    ('b0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-000000000014', 5, 'Yoga au bord du lac au lever du soleil. Rien à ajouter.', now() - interval '13 days', now() - interval '13 days'),
    ('b0000000-0000-4000-a000-000000000018', 'd0000000-0000-4000-a000-000000000005', 4, 'Doux et bien mené, marche un peu plus longue qu''annoncé.', now() - interval '60 days', now() - interval '60 days')
  ON CONFLICT (offering_id, reviewer_id) DO NOTHING;

  -- Quelques réponses du pro.
  UPDATE public.offering_reviews r SET pro_reply = x.reply, pro_reply_at = r.created_at + interval '2 days' FROM (VALUES
    ('b0000000-0000-4000-a000-000000000006'::uuid, 'd0000000-0000-4000-a000-000000000002'::uuid, 'Merci Marie ! La Tête de la Draye n''attend que ta prochaine longueur en tête.'),
    ('b0000000-0000-4000-a000-00000000000a'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'Merci Thomas, les vautours de Chabre te saluent.'),
    ('b0000000-0000-4000-a000-00000000000f'::uuid, 'd0000000-0000-4000-a000-000000000015'::uuid, 'Merci Antoine ! En haute saison on enchaîne, mais chaque vol compte. À bientôt en l''air.'),
    ('b0000000-0000-4000-a000-000000000011'::uuid, 'd0000000-0000-4000-a000-000000000013'::uuid, 'Merci Baptiste — le retour par le Glacier Blanc est long, c''est le prix du Dôme !'),
    ('b0000000-0000-4000-a000-000000000015'::uuid, 'd0000000-0000-4000-a000-000000000003'::uuid, 'Merci pour ton retour Thomas — pour une allure soutenue, le trail des crêtes te plaira davantage !')
  ) AS x(oid, rid, reply) WHERE r.offering_id = x.oid AND r.reviewer_id = x.rid;

  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
