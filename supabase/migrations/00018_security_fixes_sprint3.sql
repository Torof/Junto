-- Migration 00018: Sprint 3 security fixes

-- ============================================================================
-- FIX 1: transition_activity_status callable by anon (REVOKE didn't stick)
-- Must revoke from public role which is the default grant target
-- ============================================================================
REVOKE EXECUTE ON FUNCTION transition_activity_status() FROM anon;
REVOKE EXECUTE ON FUNCTION transition_activity_status() FROM authenticated;
REVOKE EXECUTE ON FUNCTION transition_activity_status() FROM public;

-- ============================================================================
-- FIX 2: activities_with_coords view should filter to visible statuses only
-- Anon/public shouldn't see cancelled, expired, or deleted activities
-- ============================================================================
DROP VIEW IF EXISTS activities_with_coords;

CREATE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  ST_X(a.location_start::geometry) AS lng,
  ST_Y(a.location_start::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
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
  AND a.status IN ('published', 'in_progress');

GRANT SELECT ON activities_with_coords TO anon, authenticated;

-- ============================================================================
-- FIX 3: Create a separate view for "my activities" (all statuses for creator)
-- Authenticated users need to see their own cancelled/completed/expired activities
-- ============================================================================
CREATE VIEW my_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  ST_X(a.location_start::geometry) AS lng,
  ST_Y(a.location_start::geometry) AS lat,
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

-- ============================================================================
-- FIX 4: Revoke all existing default grants on functions (catch-all)
-- ============================================================================
REVOKE EXECUTE ON FUNCTION generate_random_name() FROM public;
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM public;
REVOKE EXECUTE ON FUNCTION handle_user_update() FROM public;
REVOKE EXECUTE ON FUNCTION handle_activity_update() FROM public;
REVOKE EXECUTE ON FUNCTION strip_html_tags() FROM public;
REVOKE EXECUTE ON FUNCTION strip_html_users() FROM public;
REVOKE EXECUTE ON FUNCTION strip_html_wall_messages() FROM public;
REVOKE EXECUTE ON FUNCTION strip_html_private_messages() FROM public;
