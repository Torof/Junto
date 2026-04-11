-- Migration 00012: fix security gaps found during Sprint 1 audit

-- ============================================================================
-- FIX 1: Remove invite_token from activities_with_coords view
-- invite_token must NEVER be exposed in public queries
-- ============================================================================
DROP VIEW IF EXISTS activities_with_coords;

CREATE VIEW activities_with_coords AS
SELECT
  id, creator_id, sport_id, title, description, level,
  max_participants, starts_at, duration, visibility,
  status, deleted_at, created_at, updated_at,
  ST_X(location_start::geometry) AS lng,
  ST_Y(location_start::geometry) AS lat,
  ST_X(location_meeting::geometry) AS meeting_lng,
  ST_Y(location_meeting::geometry) AS meeting_lat
FROM activities;

GRANT SELECT ON activities_with_coords TO anon, authenticated;

-- ============================================================================
-- FIX 2: Add date_of_birth age constraint at DB level (belt and suspenders)
-- Function already validates, but constraint catches any bypass
-- ============================================================================
-- Cannot add CHECK with NOW() on existing column (CHECK must be immutable)
-- The function enforcement is sufficient — this is documented as a known limitation

-- ============================================================================
-- FIX 3: starts_at > NOW() constraint
-- Cannot use CHECK with NOW() (not immutable). Enforced in creation function (Sprint 3).
-- Documented as known limitation — the constraint is in the function, not the table.
-- ============================================================================
