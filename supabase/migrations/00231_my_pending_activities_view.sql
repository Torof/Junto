-- Migration 00231: my_pending_activities view — activities the
-- caller has requested but hasn't been accepted to yet.
--
-- Powers the new 'En attente' tab on the my-activities screen.
-- Mirrors the shape of my_joined_activities (00096) exactly, with
-- two differences:
--   1. par.status = 'pending' (instead of 'accepted').
--   2. We don't filter out activities where the caller is the
--      creator because creators can't have a pending participation
--      row on their own activity (create_activity auto-inserts
--      with status='accepted'), so the row is irrelevant — but
--      keeping it consistent with my_joined_activities for symmetry.
--
-- No new auth/RLS surface: participations RLS still applies, the
-- view runs as authenticated (default invoker rights), and the
-- WHERE clause filters by auth.uid() inside the join.

DROP VIEW IF EXISTS my_pending_activities;
CREATE VIEW my_pending_activities AS
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
JOIN participations par ON par.activity_id = a.id
  AND par.user_id = auth.uid()
  AND par.status = 'pending'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id <> auth.uid()
  AND a.deleted_at IS NULL;

GRANT SELECT ON my_pending_activities TO authenticated;
