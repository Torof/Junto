-- Migration 00287: close the anon PUBLIC-grant leaks (functions + public_profiles
-- raw reliability_score + accidentally-anon views) and lock the avatars bucket.
--
-- Root cause: Postgres grants EXECUTE to PUBLIC by default, so `REVOKE ... FROM
-- anon` on functions was a no-op (anon inherits PUBLIC). 113 app functions were
-- anon-executable (46 with no auth check at all — create_notification, notify_*,
-- recalculate_reliability_score, get_user_*), and the public_profiles view
-- exposed every user's raw reliability_score to anon.
--
-- Non-breaking — verified before writing:
--   * All 90 client-called RPCs (app + web) hold an EXPLICIT authenticated/
--     service_role grant, so they survive the PUBLIC revoke (checked live).
--   * The two web-facing views (activities_with_coords, pro_offerings_with_coords)
--     KEEP anon — the public site reads exactly these two.
--   * No client and no dependent view reads public_profiles.reliability_score
--     (activity_participants reads users.reliability_score directly); 8 views
--     depend on public_profiles so it is REPLACED, never dropped.
--   * cron runs as postgres (owner, implicit EXECUTE) — unaffected.
--
-- ROLLBACK: scratchpad 00287_rollback.sql restores every grant + the raw column.
-- Nothing here drops data or a schema object.

-- ============================================================================
-- 1. Systemic guard — future postgres-created functions no longer auto-grant
--    EXECUTE to PUBLIC, so a new migration can't silently reopen the hole.
--    (Preventive only; step 2 fixes the existing functions.)
-- ============================================================================
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ============================================================================
-- 2. Strip PUBLIC EXECUTE from every anon-reachable non-extension function in
--    public. anon loses access everywhere; authenticated/service_role keep
--    their explicit grants (client RPCs unaffected); internal-only functions
--    (only service_role) also drop authenticated. Owner postgres keeps implicit
--    EXECUTE (cron intact). Extension funcs (PostGIS/pgcrypto) skipped.
-- ============================================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC;', r.sig);
  END LOOP;
END $$;

-- ============================================================================
-- 3. public_profiles — neuter the raw reliability_score leak. CREATE OR REPLACE
--    (8 views depend on it, incl. the web's activities_with_coords — never
--    DROP). Shape preserved (same columns/order/types); reliability_score
--    forced to NULL (unused by clients and dependents), and reliability_tier
--    added as a trailing column (the intended public trust signal) for future
--    use. Then revoke anon — the web does not read this view.
-- ============================================================================
CREATE OR REPLACE VIEW public_profiles AS
  SELECT id,
         display_name,
         avatar_url,
         bio,
         sports,
         levels_per_sport,
         created_at,
         NULL::double precision AS reliability_score,   -- was: raw % (anon leak)
         reliability_tier(reliability_score) AS reliability_tier
  FROM users
  WHERE suspended_at IS NULL;

REVOKE SELECT ON public_profiles FROM anon;

-- ============================================================================
-- 4. Revoke anon on the accidentally-anon views (anon-useless, not read by the
--    web). KEEP anon on activities_with_coords + pro_offerings_with_coords (the
--    public site depends on them). authenticated is untouched, so the mobile
--    app (always authenticated on these paths) keeps full access.
-- ============================================================================
REVOKE SELECT ON activity_participants        FROM anon;
REVOKE SELECT ON my_activities                FROM anon;
REVOKE SELECT ON my_joined_activities         FROM anon;
REVOKE SELECT ON my_pending_activities        FROM anon;
REVOKE SELECT ON offering_review_stats        FROM anon;
REVOKE SELECT ON offering_reviews_with_profiles FROM anon;
REVOKE SELECT ON pro_review_stats             FROM anon;
REVOKE SELECT ON pro_reviews_with_profiles    FROM anon;
REVOKE SELECT ON public_participants          FROM anon;

-- ============================================================================
-- 5. avatars bucket — enforce mime allowlist + size limit at the storage layer
--    (client-side validation in avatar-upload.ts is bypassable). Mirrors the
--    pro-photos bucket (mig 00241). Existing objects are unaffected.
-- ============================================================================
UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'],
    file_size_limit = 5242880
WHERE id = 'avatars';
