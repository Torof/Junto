-- Migration 00256: private.user_is_suspended predicate + policy sweep.
--
-- Root cause (audit follow-up to 00255): RLS policy expressions execute
-- with the rights of the querying user, and the RLS of any table they
-- reference applies recursively. Since users_select_own (00001) only
-- exposes the caller's own row, every cross-user suspension subquery
-- of the form
--
--   NOT EXISTS (SELECT 1 FROM users WHERE id = <other> AND suspended_at IS NOT NULL)
--
-- inside a policy sees zero rows and evaluates to TRUE — a silent
-- no-op. (Own-row checks like id = auth.uid() are unaffected.)
--
-- Affected live policies: activities_select_authenticated (00044,
-- creator branch) and pro_profiles_select (00240). All other
-- occurrences of the pattern live inside SECURITY DEFINER functions,
-- which run as owner and are fine.
--
-- Fix: a SECURITY DEFINER predicate in a `private` schema. PostgREST
-- only exposes configured schemas (public), so the function is callable
-- from policy expressions but NOT via /rest/v1/rpc — it leaks nothing.
-- This is the canonical pattern for cross-table checks in policies;
-- use it for any future policy that needs to read `users`.

-- ============================================================================
-- 1. Schema + predicate
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.user_is_suspended(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NOT NULL
  );
$$;

REVOKE ALL ON FUNCTION private.user_is_suspended(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.user_is_suspended(UUID) TO authenticated;

-- ============================================================================
-- 2. activities — same policy structure as 00044, dead subqueries
--    replaced by the predicate. Branch order preserved:
--    (discoverable AND creator-not-suspended AND creator-not-blocked)
--    OR own OR participant.
-- ============================================================================
DROP POLICY IF EXISTS "activities_select_authenticated" ON activities;

CREATE POLICY "activities_select_authenticated"
  ON activities FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(auth.uid())
    AND (
      (
        status IN ('published', 'in_progress')
        AND deleted_at IS NULL
        AND NOT private.user_is_suspended(activities.creator_id)
        AND creator_id NOT IN (
          SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
        )
      )
      OR auth.uid() = creator_id
      OR EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = activities.id AND user_id = auth.uid()
      )
    )
  );

-- ============================================================================
-- 3. pro_profiles — suspension check that actually executes
-- ============================================================================
DROP POLICY IF EXISTS "pro_profiles_select" ON pro_profiles;

CREATE POLICY "pro_profiles_select"
  ON pro_profiles FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(pro_profiles.user_id)
  );

-- ============================================================================
-- 4. Pro child tables — replace USING (true). anon is dropped: every
--    client read goes through pro_offerings_with_coords (anon-granted,
--    filtered at view level since 00255) or auth-only screens.
-- ============================================================================
DROP POLICY IF EXISTS pro_offerings_public_read ON pro_offerings;

CREATE POLICY pro_offerings_select ON pro_offerings
  FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(pro_offerings.pro_id)
  );

DROP POLICY IF EXISTS pro_profile_photos_public_read ON pro_profile_photos;

CREATE POLICY pro_profile_photos_select ON pro_profile_photos
  FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(pro_profile_photos.pro_id)
  );

-- Gated on parent visibility: pro_offerings RLS applies inside the
-- subquery (recursive RLS, same mechanism as the root cause above —
-- here it works FOR us), so photos inherit the suspension gate. A
-- NOT EXISTS (...suspended...) shape would invert under recursion:
-- once the parent row is RLS-hidden, the photos would reappear.
DROP POLICY IF EXISTS pro_offering_photos_public_read ON pro_offering_photos;

CREATE POLICY pro_offering_photos_select ON pro_offering_photos
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM pro_offerings o
      WHERE o.id = pro_offering_photos.offering_id
    )
  );

-- ============================================================================
-- 5. activities_with_coords — view-body filters (the view runs with
--    owner privileges, so the table policy above never applies through
--    it; same failure mode as 00214/00255).
--
--    Suspension: the INNER JOIN on public_profiles (WHERE suspended_at
--    IS NULL) already drops suspended creators' rows, but only as a
--    side effect of the join — made explicit so it survives a future
--    LEFT JOIN or public_profiles rewrite.
--
--    Blocks: the policy's blocked-creator filter was bypassed by owner
--    semantics — blocked creators' pins showed on the map. Restored
--    here. auth.uid() IS NULL (anon) matches no blocks, so visitors
--    are unaffected.
-- ============================================================================
CREATE OR REPLACE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.start_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_start, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_start, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  ST_X(a.location_start::geometry) AS start_lng,
  ST_Y(a.location_start::geometry) AS start_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress')
  AND a.visibility IN ('public', 'approval')
  AND NOT private.user_is_suspended(a.creator_id)
  AND a.creator_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );
