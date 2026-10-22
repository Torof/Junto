-- ============================================================================
-- 00339 — Demo mode: add a 4th offering to "Air & water" — rafting.
--
-- Rafting descent on the Durance near L'Argentière-la-Bessée (Scott's coords).
-- Photos already uploaded to pro-photos/demo/ (rafting-1..5). Generic level
-- ("Tous niveaux") per the pro-offering model — precise grades are a peer-user
-- concern, not a pro one. Adds 3 offering photos + 1 to the pro gallery + 2
-- reviews, matching the other demo offerings.
-- ============================================================================

INSERT INTO pro_offerings
  (id, pro_id, sport_id, title, description, level,
   location, location_name, duration, schedule_text,
   min_participants, max_participants, price_eur, price_unit, is_demo)
VALUES
  ('b0000000-0000-4000-a000-000000000004',
   'd0000000-0000-4000-a000-000000000001',
   (SELECT id FROM sports WHERE key = 'rafting'),
   'Rafting sur la Durance',
   'Descente en rafting sur la Durance, autour de L''Argentière-la-Bessée. Rapides ludiques dans un décor de haute montagne, encadrés par un moniteur diplômé d''État. Accessible à tous dès 10 ans, aucune expérience requise. Combinaison, casque et gilet fournis.',
   'Tous niveaux',
   ST_SetSRID(ST_MakePoint(6.559765, 44.780913), 4326)::geography, 'La Durance (L''Argentière-la-Bessée)',
   INTERVAL '2 hours', 'Mai à septembre · départs 10h et 15h',
   4, 8, 45, 'person', true)
ON CONFLICT (id) DO NOTHING;

-- Offering gallery
INSERT INTO pro_offering_photos (offering_id, photo_url, order_index) VALUES
  ('b0000000-0000-4000-a000-000000000004', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/rafting-1.jpg', 0),
  ('b0000000-0000-4000-a000-000000000004', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/rafting-2.jpg', 1),
  ('b0000000-0000-4000-a000-000000000004', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/rafting-3.jpg', 2)
ON CONFLICT (offering_id, order_index) DO NOTHING;

-- Add one rafting shot to the pro page gallery (next free slot).
INSERT INTO pro_profile_photos (pro_id, photo_url, order_index) VALUES
  ('d0000000-0000-4000-a000-000000000001', 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/pro-photos/demo/rafting-4.jpg', 5)
ON CONFLICT (pro_id, order_index) DO NOTHING;

-- Reviews (distinct reviewers).
INSERT INTO offering_reviews (offering_id, reviewer_id, rating, body) VALUES
  ('b0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000004', 5, 'Super descente, franchement fun même pour une première fois. Moniteur au top.'),
  ('b0000000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000005', 4, 'Bonne rigolade dans les rapides, eau un peu fraîche mais on se réchauffe vite !')
ON CONFLICT (offering_id, reviewer_id) DO NOTHING;
