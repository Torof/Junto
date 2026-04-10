-- Junto seed data — TEST DATA ONLY
-- DO NOT RUN IN PRODUCTION
-- This script creates fake activities for development and testing

-- Guard: refuse to run if activities already exist (prevents double seeding)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM activities LIMIT 1) THEN
    RAISE EXCEPTION 'Seed data already exists. Aborting to prevent duplicates.';
  END IF;
END $$;

-- We need test users first. These are created via auth.users trigger,
-- so seed data for activities will be added after we have the auth flow working.
-- For now, this file is a placeholder that will be populated in Sprint 1 Phase E
-- when we can create test users through Supabase Auth.

-- Test activities will reference:
-- - Real sport IDs from the sports migration
-- - Real user IDs from auth-created test accounts
-- - Geolocated near Briançon, France (44.8967° N, 6.6323° E) — the founding use case
