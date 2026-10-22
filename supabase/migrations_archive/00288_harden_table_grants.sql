-- Migration 00288: defense-in-depth grant hardening. Pure hardening — no
-- functional change. RLS already contains anon on every table except
-- spatial_ref_sys; this removes the redundant anon write/read surface so RLS
-- is no longer the SOLE line of defense.
--
-- Non-breaking — verified before writing:
--   * No code path writes any table directly as anon (all writes go through
--     SECURITY DEFINER RPCs). Revoking anon INSERT/UPDATE/DELETE touches nothing.
--   * `users` is never read as anon (web reads views; app reads it only when
--     authenticated) — revoking ALL from anon is safe; authenticated untouched.
--   * `authenticated` grants are LEFT INTACT (e.g. the activity_alerts direct
--     DELETE policy Scott chose to keep keeps working).
--   * postgres has BYPASSRLS (verified), so FORCE on activity_gear does not
--     block the SECURITY DEFINER writers (they run as postgres).
--
-- Deferred to a future pass (LOW severity, non-zero regression risk, NOT here):
--   - security_invoker on the definer views (would flip anon on the web views
--     to 0 rows — must be done per-view with care).
--   - suspended-pro filter on pro_offering_photos / pro_community_photos.
--
-- ROLLBACK: scratchpad 00288_rollback.sql.

-- ============================================================================
-- 1. Revoke anon write privileges on every app table (keep anon SELECT — RLS
--    contains it, and some tables are legitimately public-read). `users` and
--    `spatial_ref_sys` handled separately below.
-- ============================================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS tbl
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
      AND c.relname NOT IN ('users', 'spatial_ref_sys')
  LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON %s FROM anon, PUBLIC;', r.tbl);
  END LOOP;
END $$;

-- ============================================================================
-- 2. users — no anon grant at all (CLAUDE.md rule). RLS already returns 0 rows
--    to anon; this closes the redundant surface. authenticated keeps its
--    own-row access.
-- ============================================================================
REVOKE ALL ON public.users FROM anon;

-- ============================================================================
-- 3. spatial_ref_sys — RLS is OFF and anon holds column-level write grants.
--    ACCEPTED PLATFORM LIMITATION: this table is owned by `supabase_admin`, not
--    `postgres` (our migration role), so these grants are NOT revocable from a
--    migration (the REVOKE below is a no-op — verified). Residual risk is very
--    low: it's the PostGIS coordinate-system reference table; the app uses a
--    fixed SRID (4326), so bogus rows don't affect user data or auth. Every
--    Supabase+PostGIS project ships it this way. Left here as a documented
--    intent; if Supabase ever exposes a way to harden it, revisit.
-- ============================================================================
REVOKE INSERT, UPDATE, DELETE ON public.spatial_ref_sys FROM anon, authenticated, PUBLIC;

-- ============================================================================
-- 4. activity_gear — enforce the project's ENABLE + FORCE standard (every other
--    table is forced). Safe: SECURITY DEFINER writers run as postgres (BYPASSRLS).
-- ============================================================================
ALTER TABLE public.activity_gear FORCE ROW LEVEL SECURITY;
