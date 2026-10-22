-- ============================================================================
-- PRE-LAUNCH TEST-DATA WIPE — DRAFT, DO NOT APPLY YET
-- ============================================================================
-- Scott's call (2026-07-10): every existing account is one of his test
-- accounts — full reset before the closed-test invitations go out, so the
-- very first real signups (his own included) go through the fresh
-- Play-install onboarding.
--
-- HOW TO FIRE (D-day, when the 12th tester address is in):
--   1. mv supabase/wipe-test-data.draft.sql \
--        supabase/migrations/00XXX_wipe_test_data.sql   (next number)
--   2. printf 'Y\n' | npx supabase db push
--   3. REQUIRED — empty the 'avatars' and 'pro-photos' buckets from the
--      Supabase dashboard (Storage). SQL cannot touch storage.objects
--      (Supabase blocks direct deletion — use the Storage API/dashboard),
--      so the files + object rows are cleared there, not here.
--
-- WHAT IT DELETES: all auth accounts. public.users cascades from
-- auth.users (00001), and every content table cascades from users and/or
-- activities per the per-table deletion strategy (SECURITY.md) — this
-- includes gpx_traces (ON DELETE CASCADE, mig 00320). Storage files are NOT
-- touched here — Supabase forbids direct DELETE on storage.objects, so both
-- buckets must be emptied from the dashboard (step 3). admin_actions does NOT cascade (admin_id is
-- ON DELETE SET NULL by design so the audit log survives an admin deletion,
-- mig 00321) — it is therefore wiped EXPLICITLY here: every current row is a
-- test admin action and this is a full pre-launch reset (Scott 2026-07-16).
-- WHAT SURVIVES: the sports catalog, gear_catalog, app_config, the
-- buckets themselves,
-- and the whole schema (tables, functions, policies, triggers).
-- The trailing DO block FAILS LOUDLY if any user-content table still has
-- rows after the cascade — nothing is silently left behind.
-- ============================================================================

DELETE FROM auth.users;

-- Storage files are emptied from the dashboard (Supabase blocks direct SQL
-- deletion of storage.objects). See step 3 in the header.

-- Audit log does not cascade (admin_id ON DELETE SET NULL) — wipe explicitly.
DELETE FROM admin_actions;

DO $$
DECLARE
  v_table TEXT;
  v_count BIGINT;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'users', 'activities', 'participations', 'conversations',
    'private_messages', 'wall_messages', 'notifications',
    'reputation_votes', 'peer_validations', 'presence_tokens',
    'push_tokens', 'seat_requests', 'activity_alerts',
    'activity_gear', 'activity_gear_missing',
    'reports', 'user_badge_progression', 'blocked_users',
    'gpx_traces', 'admin_actions',
    'pro_profiles', 'pro_offerings', 'pro_reviews', 'offering_reviews',
    'pro_profile_photos', 'pro_offering_photos', 'pro_community_photos'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM %I', v_table) INTO v_count;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'wipe incomplete: % rows left in %', v_count, v_table;
    END IF;
  END LOOP;
END $$;
