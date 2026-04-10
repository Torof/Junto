-- Migration 00010: activities view with extracted coordinates
-- PostGIS returns geography as WKB hex — this view exposes lng/lat as numbers

CREATE VIEW activities_with_coords AS
SELECT
  id, creator_id, sport_id, title, description, level,
  max_participants, starts_at, duration, visibility,
  invite_token, status, deleted_at, created_at, updated_at,
  ST_X(location_start::geometry) AS lng,
  ST_Y(location_start::geometry) AS lat,
  ST_X(location_meeting::geometry) AS meeting_lng,
  ST_Y(location_meeting::geometry) AS meeting_lat
FROM activities;

GRANT SELECT ON activities_with_coords TO anon, authenticated;
