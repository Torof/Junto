-- 00315: private activities appear on the map — for their members only
--
-- Scott (2026-07-10): a private outing was invisible on the map even for
-- its own participants — hard to find. The map view now includes
-- private_link / private_link_approval activities when the caller is the
-- CREATOR or an ACCEPTED participant. Pending requesters don't see the
-- pin (not vetted yet — they follow their request via the invite link).
-- Anon (the website reads this view): auth.uid() IS NULL -> no private
-- row ever leaks. All other filters (deleted, status, suspended creator,
-- blocked) unchanged. CREATE OR REPLACE VIEW preserves the grants
-- (anon + authenticated, deliberate since 00287 for the web).

CREATE OR REPLACE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.meeting_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
  a.level_max
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress')
  AND (
    a.visibility IN ('public', 'approval')
    OR (
      a.visibility IN ('private_link', 'private_link_approval')
      AND (
        a.creator_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM participations p2
          WHERE p2.activity_id = a.id
            AND p2.user_id = auth.uid()
            AND p2.status = 'accepted'
        )
      )
    )
  )
  AND NOT private.user_is_suspended(a.creator_id)
  AND a.creator_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );
