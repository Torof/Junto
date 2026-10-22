-- ============================================================================
-- 00334 — Demo mode, PHASE 2 (rich content: pros + offerings + social life)
--
-- Phase 1 (00333) proved the curtain mechanism on ACTIVITIES. Phase 2:
--   1. Extends the same mechanism to pro_profiles + pro_offerings (is_demo
--      column, whitelist protection, demo gate in the offerings view WHERE +
--      the pro_profiles_select RLS policy — the pro map reads the table direct).
--   2. Seeds dedicated DEMO USER ACCOUNTS (auth.users → public.users), so the
--      content has creators, participants and review authors (real names on
--      cards, not the admin's).
--   3. Replaces the 2 placeholder activities with 4 geographically-accurate
--      peer outings + 1 pro page "Air & water" with 3 offerings, all with
--      photos and reviews.
--
-- Coordinates: Rocher Baron falaise + Combes parking are exact (climbingaway /
-- altituderando). The rest are best-estimate — Scott validates each pin on the
-- device with demo mode ON and corrects any that are off.
--
-- Everything is is_demo=true → admin-only visibility (00333 demo_content_visible).
-- Reviews/participations are seeded via direct INSERT (rate-limit + one-per-target
-- live only in the RPCs, not in table triggers) — safe in a migration.
-- ============================================================================

-- ============================================================================
-- 1) MECHANISM — extend is_demo to the pro tables
-- ============================================================================
ALTER TABLE pro_profiles  ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;
ALTER TABLE pro_offerings ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;

-- Whitelist protection: is_demo forced to OLD on any non-bypass UPDATE
-- (reproduced from 00240 / 00249 + one line each).
CREATE OR REPLACE FUNCTION pro_profiles_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.user_id := OLD.user_id;
  NEW.created_at := OLD.created_at;
  NEW.last_location_change_at := OLD.last_location_change_at;
  NEW.is_demo := OLD.is_demo;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION pro_offerings_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.created_at := OLD.created_at;
  NEW.is_demo := OLD.is_demo;
  RETURN NEW;
END;
$$;

-- Offerings map/list view gains the demo gate (reproduced from 00285 + one AND).
CREATE OR REPLACE VIEW pro_offerings_with_coords AS
SELECT
  o.id,
  o.pro_id,
  o.sport_id,
  o.title,
  o.description,
  o.level,
  o.location_name,
  o.duration,
  o.max_participants,
  o.schedule_text,
  o.distance_km,
  o.elevation_gain_m,
  (
    SELECT photo_url
    FROM pro_offering_photos p
    WHERE p.offering_id = o.id
    ORDER BY order_index ASC
    LIMIT 1
  ) AS image_url,
  o.created_at,
  o.updated_at,
  ST_X(o.location::geometry) AS lng,
  ST_Y(o.location::geometry) AS lat,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  pp.display_name AS pro_name,
  o.price_eur,
  o.price_unit,
  o.min_participants
FROM pro_offerings o
JOIN sports s ON o.sport_id = s.id
JOIN pro_profiles pp ON o.pro_id = pp.user_id
WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.id = o.pro_id AND u.suspended_at IS NOT NULL
)
AND (o.is_demo = false OR demo_content_visible());

-- Pro profile map/list is read from the table directly (no coords view), so the
-- demo gate goes in the SELECT policy (reproduced from 00277 + one AND clause).
DROP POLICY IF EXISTS pro_profiles_select ON pro_profiles;
CREATE POLICY "pro_profiles_select"
  ON pro_profiles FOR SELECT
  TO authenticated
  USING (
    NOT EXISTS (SELECT 1 FROM users u WHERE u.id = pro_profiles.user_id AND u.suspended_at IS NOT NULL)
    AND (pro_profiles.is_demo = false OR demo_content_visible())
    AND (
      pro_profiles.status = 'approved'
      OR pro_profiles.user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true)
    )
  );

-- ============================================================================
-- 2) RESET — drop the Phase 1 placeholder activities (cascades participations)
-- ============================================================================
DELETE FROM activities WHERE is_demo = true;

-- ============================================================================
-- 3) DEMO USERS — auth.users row (trigger auto-creates public.users), then
--    UPDATE under bypass_lock to set the real identity + tier + is_demo.
--    Fixed UUIDs = idempotent + referenceable below. Never log in (empty pw).
-- ============================================================================
INSERT INTO auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000001', 'authenticated', 'authenticated', 'demo.airwater@junto.demo', '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000002', 'authenticated', 'authenticated', 'demo.marie@junto.demo',    '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000003', 'authenticated', 'authenticated', 'demo.thomas@junto.demo',   '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000004', 'authenticated', 'authenticated', 'demo.julie@junto.demo',    '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000005', 'authenticated', 'authenticated', 'demo.karim@junto.demo',    '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000006', 'authenticated', 'authenticated', 'demo.lea@junto.demo',      '', now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}')
ON CONFLICT (id) DO NOTHING;

-- Set identity/tier/is_demo (privileged cols → bypass_lock, scoped in a DO
-- block so the set_config + UPDATEs are guaranteed to share one transaction).
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE public.users u SET
    display_name = d.display_name,
    avatar_url   = d.avatar_url,
    bio          = d.bio,
    is_demo      = true
  FROM (VALUES
    ('d0000000-0000-4000-a000-000000000001'::uuid, 'Air & Water', 'https://ui-avatars.com/api/?name=Air+Water&background=2FA46A&color=fff&size=256', 'Bureau de moniteurs — canyoning & parapente dans le Briançonnais.'),
    ('d0000000-0000-4000-a000-000000000002'::uuid, 'Marie L.',    'https://ui-avatars.com/api/?name=Marie+L&background=3F7A56&color=fff&size=256',    'Rando & trail dans les Écrins.'),
    ('d0000000-0000-4000-a000-000000000003'::uuid, 'Thomas B.',   'https://ui-avatars.com/api/?name=Thomas+B&background=2F6FA4&color=fff&size=256',   'Grimpeur, toujours partant pour une couenne.'),
    ('d0000000-0000-4000-a000-000000000004'::uuid, 'Julie R.',    'https://ui-avatars.com/api/?name=Julie+R&background=A4632F&color=fff&size=256',    'Escalade & montagne autour de Briançon.'),
    ('d0000000-0000-4000-a000-000000000005'::uuid, 'Karim D.',    'https://ui-avatars.com/api/?name=Karim+D&background=6F4EA4&color=fff&size=256',    'Parapente & marche-vol.'),
    ('d0000000-0000-4000-a000-000000000006'::uuid, 'Léa M.',      'https://ui-avatars.com/api/?name=Lea+M&background=A42F6B&color=fff&size=256',      'Multi-activités outdoor.')
  ) AS d(id, display_name, avatar_url, bio)
  WHERE u.id = d.id;

  -- The pro owner is tier 'pro'.
  UPDATE public.users SET tier = 'pro' WHERE id = 'd0000000-0000-4000-a000-000000000001';
END $$;

-- ============================================================================
-- 4) PEER ACTIVITIES (is_demo). Creators = demo users. starts_at is refreshed
--    to upcoming by admin_set_demo_mode on every enable — the seed values are
--    just placeholders.
-- ============================================================================
INSERT INTO activities
  (id, creator_id, sport_id, title, description, level, level_max,
   max_participants, location_meeting, meeting_name,
   location_objective, objective_name,
   starts_at, duration, visibility, requires_presence, status,
   distance_km, elevation_gain_m, is_demo)
VALUES
  -- 1 · Randonnée — Croix d'Aquila (obj estimate) / RDV Puy-Chalvin (estimate)
  ('a0000000-0000-4000-a000-000000000001',
   'd0000000-0000-4000-a000-000000000002',
   (SELECT id FROM sports WHERE key = 'hiking'),
   'Rando à la Croix d''Aquila',
   'Boucle par le col de la Trancoulette jusqu''à la Croix d''Aquila (2466 m), au cœur de la réserve des Partias. Panorama sur le Briançonnais et les Écrins. Rythme tranquille, on prend le temps. Eau et pique-nique au sommet.',
   'intermédiaire', NULL, 8,
   ST_SetSRID(ST_MakePoint(6.5780, 44.8845), 4326)::geography, 'Puy-Chalvin',
   ST_SetSRID(ST_MakePoint(6.5540, 44.8770), 4326)::geography, 'Croix d''Aquila',
   now() + INTERVAL '2 days', INTERVAL '5 hours', 'public', false, 'published',
   11.0, 600, true),

  -- 2 · Escalade — Rocher Baron (obj EXACT) / RDV Villar-Saint-Pancrace (estimate)
  ('a0000000-0000-4000-a000-000000000002',
   'd0000000-0000-4000-a000-000000000003',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Grimpe au Rocher Baron',
   'Session couennes au Rocher Baron, beau rocher quartzite orienté sud, voies de la 4 à la 7a — de quoi contenter tout le monde. Départ groupé depuis Villar-Saint-Pancrace. Perso : baudrier, chaussons, dégaines ; cordes en commun.',
   'intermédiaire', 'avancé', 4,
   ST_SetSRID(ST_MakePoint(6.6288, 44.8758), 4326)::geography, 'Villar-Saint-Pancrace',
   ST_SetSRID(ST_MakePoint(6.589243, 44.84538), 4326)::geography, 'Rocher Baron',
   now() + INTERVAL '4 days', INTERVAL '4 hours', 'public', false, 'published',
   NULL, NULL, true),

  -- 3 · Escalade — Falaise de Puy-Chalvin (estimate) / RDV parking avant la ferme
  ('a0000000-0000-4000-a000-000000000003',
   'd0000000-0000-4000-a000-000000000004',
   (SELECT id FROM sports WHERE key = 'climbing-sport'),
   'Escalade à la falaise de Puy-Chalvin',
   'Petite falaise au-dessus de Puy-Chalvin, idéale pour une demi-journée. Voies faciles à moyennes, ambiance conviviale. On se retrouve au parking juste avant la ferme. Baudrier + chaussons perso.',
   'débutant', 'intermédiaire', 6,
   ST_SetSRID(ST_MakePoint(6.5770, 44.8850), 4326)::geography, 'Parking de Puy-Chalvin (avant la ferme)',
   ST_SetSRID(ST_MakePoint(6.5745, 44.8835), 4326)::geography, 'Falaise de Puy-Chalvin',
   now() + INTERVAL '6 days', INTERVAL '3 hours', 'public', false, 'published',
   NULL, NULL, true),

  -- 4 · Parapente — Cime de la Condamine (obj estimate) / RDV Combes (EXACT)
  ('a0000000-0000-4000-a000-000000000004',
   'd0000000-0000-4000-a000-000000000005',
   (SELECT id FROM sports WHERE key = 'paragliding'),
   'Vol depuis la cime de la Condamine',
   'Marche-et-vol : montée à la cime de la Condamine (2940 m) puis déco face à la vallée pour un grand vol jusqu''à Vallouise. Environ 1000 m de dénivelé à pied depuis les Combes. Réservé aux pilotes autonomes, aile de rando conseillée. On surveille la météo la veille.',
   'avancé', NULL, 4,
   ST_SetSRID(ST_MakePoint(6.57061, 44.89252), 4326)::geography, 'Hameau des Combes',
   ST_SetSRID(ST_MakePoint(6.5199, 44.8925), 4326)::geography, 'Cime de la Condamine',
   now() + INTERVAL '8 days', INTERVAL '5 hours', 'public', false, 'published',
   6.0, 1000, true)
ON CONFLICT (id) DO NOTHING;

-- Participants (accepted). Creators are never their own participant.
INSERT INTO participations (activity_id, user_id, status)
VALUES
  -- Rando (creator Marie)
  ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000003', 'accepted'),
  ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000006', 'accepted'),
  ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000005', 'accepted'),
  ('a0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000004', 'accepted'),
  -- Rocher Baron (creator Thomas)
  ('a0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000005', 'accepted'),
  ('a0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000004', 'accepted'),
  -- Falaise Puy-Chalvin (creator Julie)
  ('a0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000002', 'accepted'),
  ('a0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000006', 'accepted'),
  -- Condamine (creator Karim)
  ('a0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000003', 'accepted'),
  ('a0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000006', 'accepted')
ON CONFLICT (user_id, activity_id) DO NOTHING;

-- ============================================================================
-- 5) PRO PAGE "Air & water" (approved + is_demo). Base pin at Briançon.
-- ============================================================================
INSERT INTO pro_profiles
  (user_id, display_name, company_name, real_name, status, tagline, description,
   phone, email, instagram,
   primary_lng, primary_lat, primary_location, primary_location_name,
   pin_icon, pin_image_url, is_demo)
VALUES
  ('d0000000-0000-4000-a000-000000000001',
   'Air & water', 'Air & Water', 'Compte démo', 'approved',
   'Canyoning & parapente dans le Briançonnais',
   'Bureau de moniteurs diplômés d''État. Canyoning dans les plus beaux torrents du Briançonnais et vols biplace en parapente au-dessus de Serre Chevalier. Du frisson pour tous les niveaux, encadrement pro, matériel fourni.',
   '+33 6 12 34 56 78', 'contact@airandwater.fr', 'airandwater.brianconnais',
   6.6353, 44.8955,
   ST_SetSRID(ST_MakePoint(6.6353, 44.8955), 4326)::geography, 'Briançon',
   'water', 'https://picsum.photos/seed/airwaterpin/400/400', true)
ON CONFLICT (user_id) DO NOTHING;

-- Pro page gallery
INSERT INTO pro_profile_photos (pro_id, photo_url, order_index)
VALUES
  ('d0000000-0000-4000-a000-000000000001', 'https://picsum.photos/seed/airwater1/1200/800', 0),
  ('d0000000-0000-4000-a000-000000000001', 'https://picsum.photos/seed/airwater2/1200/800', 1),
  ('d0000000-0000-4000-a000-000000000001', 'https://picsum.photos/seed/airwater3/1200/800', 2)
ON CONFLICT (pro_id, order_index) DO NOTHING;

-- ============================================================================
-- 6) OFFERINGS (3). is_demo; parent is approved so the require_approved trigger
--    passes.
-- ============================================================================
INSERT INTO pro_offerings
  (id, pro_id, sport_id, title, description, level,
   location, location_name, duration,
   min_participants, max_participants, price_eur, price_unit, is_demo)
VALUES
  ('b0000000-0000-4000-a000-000000000001',
   'd0000000-0000-4000-a000-000000000001',
   (SELECT id FROM sports WHERE key = 'canyoning'),
   'Canyoning au Fournel',
   'Canyon ludique et rafraîchissant dans la vallée du Fournel, près de L''Argentière-la-Bessée. Sauts, toboggans et rappels dans un cadre sauvage. Accessible aux débutants dès 12 ans. Combinaison et matériel fournis.',
   'Tous niveaux',
   ST_SetSRID(ST_MakePoint(6.5200, 44.8010), 4326)::geography, 'Vallée du Fournel',
   INTERVAL '4 hours', 4, 8, 55, 'person', true),

  ('b0000000-0000-4000-a000-000000000002',
   'd0000000-0000-4000-a000-000000000001',
   (SELECT id FROM sports WHERE key = 'canyoning'),
   'Canyoning au torrent des Acles',
   'Descente sportive du torrent des Acles, au-dessus de Plampinet dans la vallée de la Clarée. Beaux enchaînements de rappels et de sauts, eau claire. Pour des personnes à l''aise dans l''eau. Combinaison néoprène 5 mm fournie.',
   'Intermédiaire',
   ST_SetSRID(ST_MakePoint(6.7650, 44.9950), 4326)::geography, 'Torrent des Acles (Plampinet)',
   INTERVAL '5 hours', 4, 8, 65, 'person', true),

  ('b0000000-0000-4000-a000-000000000003',
   'd0000000-0000-4000-a000-000000000001',
   (SELECT id FROM sports WHERE key = 'paragliding'),
   'Vol biplace au Prorel',
   'Baptême ou vol biplace au départ du sommet du Prorel (2566 m), au-dessus de Briançon et Serre Chevalier. Décollage tranquille et grand panorama sur les Écrins. Vidéo du vol en option. Accessible à tous, aucune expérience requise.',
   'Tous niveaux',
   ST_SetSRID(ST_MakePoint(6.6075, 44.9145), 4326)::geography, 'Sommet du Prorel',
   INTERVAL '1 hour', 1, 1, 90, 'person', true)
ON CONFLICT (id) DO NOTHING;

-- Offering galleries
INSERT INTO pro_offering_photos (offering_id, photo_url, order_index)
VALUES
  ('b0000000-0000-4000-a000-000000000001', 'https://picsum.photos/seed/fournel1/1200/800', 0),
  ('b0000000-0000-4000-a000-000000000001', 'https://picsum.photos/seed/fournel2/1200/800', 1),
  ('b0000000-0000-4000-a000-000000000002', 'https://picsum.photos/seed/acles1/1200/800', 0),
  ('b0000000-0000-4000-a000-000000000002', 'https://picsum.photos/seed/acles2/1200/800', 1),
  ('b0000000-0000-4000-a000-000000000003', 'https://picsum.photos/seed/prorel1/1200/800', 0),
  ('b0000000-0000-4000-a000-000000000003', 'https://picsum.photos/seed/prorel2/1200/800', 1)
ON CONFLICT (offering_id, order_index) DO NOTHING;

-- ============================================================================
-- 7) REVIEWS — distinct reviewers per target (UNIQUE constraint). Direct INSERT
--    bypasses the RPC rate-limit (checks live only in the RPCs).
-- ============================================================================
INSERT INTO pro_reviews (pro_id, reviewer_id, rating, body)
VALUES
  ('d0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000002', 5, 'Super moniteurs, très pros et rassurants. Canyon au top, on a adoré !'),
  ('d0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000003', 5, 'Encadrement impeccable, matériel nickel. Je recommande les yeux fermés.'),
  ('d0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000006', 4, 'Très bonne demi-journée, ambiance sympa. Juste un peu d''attente au départ.'),
  ('d0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000005', 5, 'Vol biplace magnifique au-dessus de Serre Che. Pilote génial !')
ON CONFLICT (pro_id, reviewer_id) DO NOTHING;

INSERT INTO offering_reviews (offering_id, reviewer_id, rating, body)
VALUES
  -- Fournel
  ('b0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000002', 5, 'Canyon parfait pour débuter, sauts et toboggans géniaux.'),
  ('b0000000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000004', 4, 'Belle sortie, eau un peu fraîche mais quel cadre.'),
  -- Acles
  ('b0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000003', 5, 'Canyon engagé et superbe, les rappels valent le détour.'),
  ('b0000000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000006', 5, 'Une tuerie, la vallée de la Clarée est magnifique.'),
  -- Prorel
  ('b0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000005', 5, 'Décollage tranquille, vue incroyable. Merci !'),
  ('b0000000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000002', 5, 'Premier vol biplace, sensations au rendez-vous.')
ON CONFLICT (offering_id, reviewer_id) DO NOTHING;
