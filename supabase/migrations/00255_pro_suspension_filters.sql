-- Migration 00255: hide suspended pros' offerings in the catalog view.
--
-- Audit finding: pro_offerings_with_coords (00250) has no suspension
-- filter. The parent pro_profiles SELECT policy (00240) was meant to
-- hide suspended pros, but the view runs with owner privileges (no
-- security_invoker, owner = postgres with BYPASSRLS) so no table RLS
-- applies through it — same failure mode as the 00214
-- public_participants fix. Since every client read of offerings goes
-- through this view (pro-offering-service), the filter must live in
-- the view body, where the users subquery runs in owner context and
-- is not subject to users_select_own.
--
-- We deliberately do NOT flip security_invoker: pro_profiles'
-- SELECT policy is authenticated-only, so invoker semantics would
-- empty the view for anon instead of filtering it.
--
-- NOTE: the USING (true) SELECT policies on pro_offerings,
-- pro_profile_photos and pro_offering_photos (00249 / 00252) still
-- expose suspended pros' rows to direct PostgREST table reads. A
-- plain policy subquery on users cannot fix that (users_select_own
-- hides other users' rows inside policy expressions — the suspension
-- subqueries in existing policies are silent no-ops). Pending fix: a
-- non-exposed SECURITY DEFINER predicate usable from policies — see
-- follow-up migration once the approach is validated.

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
  o.image_url,
  o.created_at,
  o.updated_at,
  ST_X(o.location::geometry) AS lng,
  ST_Y(o.location::geometry) AS lat,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  pp.display_name AS pro_name
FROM pro_offerings o
JOIN sports s ON o.sport_id = s.id
JOIN pro_profiles pp ON o.pro_id = pp.user_id
WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.id = o.pro_id AND u.suspended_at IS NOT NULL
);
