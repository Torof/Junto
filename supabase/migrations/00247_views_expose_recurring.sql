-- Migration 00247: expose is_recurring + recurrence_days on the four
-- activity views so the map and lists can branch on recurrence.
--
-- The pin renderer needs is_recurring to pick the lozenge variant; the
-- detail screen wants recurrence_days to show the cadence. Both come
-- from activities (added in 00240). Every view drops + recreates with
-- identical shape, only the two new columns appended.
--
-- No auth/RLS changes: the views inherit RLS from activities and
-- participations; visibility filter on activities_with_coords stays
-- 'public' | 'approval'.

DROP VIEW IF EXISTS activities_with_coords;
CREATE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.start_name,
  a.trace_geojson,
  a.is_recurring, a.recurrence_days,
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
  AND a.visibility IN ('public', 'approval');

GRANT SELECT ON activities_with_coords TO anon, authenticated;

DROP VIEW IF EXISTS my_activities;
CREATE VIEW my_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.start_name,
  a.trace_geojson,
  a.is_recurring, a.recurrence_days,
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
WHERE a.creator_id = auth.uid();

GRANT SELECT ON my_activities TO authenticated;

DROP VIEW IF EXISTS my_joined_activities;
CREATE VIEW my_joined_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.start_name,
  a.trace_geojson,
  a.is_recurring, a.recurrence_days,
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
  AND par.status = 'accepted'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id != auth.uid()
  AND a.deleted_at IS NULL;

GRANT SELECT ON my_joined_activities TO authenticated;

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
  a.is_recurring, a.recurrence_days,
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
