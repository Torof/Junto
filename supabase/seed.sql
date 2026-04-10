-- Junto seed data — TEST DATA ONLY
-- Run AFTER creating a test user via Supabase Auth
-- Replace TEST_USER_ID with the actual user ID from auth.users

-- Step 1: Create a test user via Supabase dashboard (Authentication > Users > Add user)
-- Step 2: Copy the user UUID
-- Step 3: Replace 'TEST_USER_ID' below with that UUID
-- Step 4: Run this script in the SQL Editor

-- Guard: refuse to run if activities already exist
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM activities LIMIT 1) THEN
    RAISE EXCEPTION 'Seed data already exists. Aborting.';
  END IF;
END $$;

-- Replace this with the actual test user ID
DO $$
DECLARE
  test_user_id UUID;
  sport_hiking UUID;
  sport_climbing UUID;
  sport_ski UUID;
  sport_trail UUID;
  sport_cycling UUID;
  activity_id UUID;
BEGIN
  -- Get first user (test user)
  SELECT id INTO test_user_id FROM users LIMIT 1;
  IF test_user_id IS NULL THEN
    RAISE EXCEPTION 'No users found. Create a test user via Supabase Auth first.';
  END IF;

  -- Get sport IDs
  SELECT id INTO sport_hiking FROM sports WHERE key = 'hiking';
  SELECT id INTO sport_climbing FROM sports WHERE key = 'climbing';
  SELECT id INTO sport_ski FROM sports WHERE key = 'ski-touring';
  SELECT id INTO sport_trail FROM sports WHERE key = 'trail-running';
  SELECT id INTO sport_cycling FROM sports WHERE key = 'cycling';

  -- Activities near Briançon, France (44.8967° N, 6.6323° E)

  -- 1. Hiking in Serre Chevalier
  INSERT INTO activities (creator_id, sport_id, title, description, level, max_participants, location_start, starts_at, duration, status)
  VALUES (test_user_id, sport_hiking, 'Randonnée Serre Chevalier', 'Belle randonnée avec vue sur les Écrins', 'intermédiaire', 6,
    ST_MakePoint(6.5569, 44.9479)::geography, now() + INTERVAL '2 days', INTERVAL '4 hours', 'published')
  RETURNING id INTO activity_id;
  INSERT INTO participations (activity_id, user_id, status) VALUES (activity_id, test_user_id, 'accepted');

  -- 2. Climbing at Ailefroide
  INSERT INTO activities (creator_id, sport_id, title, description, level, max_participants, location_start, starts_at, duration, status)
  VALUES (test_user_id, sport_climbing, 'Escalade Ailefroide', 'Grandes voies en 6a-6c, matériel requis', 'avancé', 4,
    ST_MakePoint(6.4432, 44.8846)::geography, now() + INTERVAL '3 days', INTERVAL '6 hours', 'published')
  RETURNING id INTO activity_id;
  INSERT INTO participations (activity_id, user_id, status) VALUES (activity_id, test_user_id, 'accepted');

  -- 3. Ski touring Col du Lautaret
  INSERT INTO activities (creator_id, sport_id, title, description, level, max_participants, location_start, starts_at, duration, status)
  VALUES (test_user_id, sport_ski, 'Ski de rando Col du Lautaret', 'Sortie ski de randonnée, DVA obligatoire', 'avancé', 3,
    ST_MakePoint(6.4058, 45.0342)::geography, now() + INTERVAL '1 day', INTERVAL '5 hours', 'published')
  RETURNING id INTO activity_id;
  INSERT INTO participations (activity_id, user_id, status) VALUES (activity_id, test_user_id, 'accepted');

  -- 4. Trail running Parc des Écrins
  INSERT INTO activities (creator_id, sport_id, title, description, level, max_participants, location_start, starts_at, duration, status)
  VALUES (test_user_id, sport_trail, 'Trail Parc des Écrins', 'Trail 15km, dénivelé 800m', 'intermédiaire', 8,
    ST_MakePoint(6.3500, 44.9200)::geography, now() + INTERVAL '4 days', INTERVAL '3 hours', 'published')
  RETURNING id INTO activity_id;
  INSERT INTO participations (activity_id, user_id, status) VALUES (activity_id, test_user_id, 'accepted');

  -- 5. Cycling Route des Grandes Alpes
  INSERT INTO activities (creator_id, sport_id, title, description, level, max_participants, location_start, starts_at, duration, status)
  VALUES (test_user_id, sport_cycling, 'Vélo Col du Galibier', 'Montée du Galibier depuis Briançon', 'avancé', 5,
    ST_MakePoint(6.6323, 44.8967)::geography, now() + INTERVAL '5 days', INTERVAL '4 hours', 'published')
  RETURNING id INTO activity_id;
  INSERT INTO participations (activity_id, user_id, status) VALUES (activity_id, test_user_id, 'accepted');

END $$;
