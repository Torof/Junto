-- Migration 00069: profile enrichment for Discovery-era profiles
-- Adds organizer/joiner split to get_user_public_stats and a new
-- get_user_sport_breakdown RPC returning per-sport level + completed count.

-- ============================================================================
-- REPLACE: get_user_public_stats with created/joined split
-- ============================================================================
DROP FUNCTION IF EXISTS get_user_public_stats(UUID);

CREATE OR REPLACE FUNCTION get_user_public_stats(
  p_user_id UUID
)
RETURNS TABLE (
  total_activities INTEGER,
  completed_activities INTEGER,
  created_activities INTEGER,
  joined_activities INTEGER,
  sports_count INTEGER,
  reliability_score FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    -- total: everything the user has participated in (accepted), creator included
    (SELECT count(*)::int FROM participations
     WHERE user_id = p_user_id AND status = 'accepted') AS total_activities,
    -- completed: participations on activities that reached completed status
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id AND par.status = 'accepted' AND a.status = 'completed') AS completed_activities,
    -- created: distinct activities where user is creator (regardless of final status)
    (SELECT count(*)::int FROM activities
     WHERE creator_id = p_user_id AND deleted_at IS NULL) AS created_activities,
    -- joined: accepted participations on activities the user did NOT create
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL) AS joined_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    (SELECT u.reliability_score FROM users u WHERE u.id = p_user_id) AS reliability_score;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_public_stats FROM anon;
GRANT EXECUTE ON FUNCTION get_user_public_stats TO authenticated;

-- ============================================================================
-- NEW: get_user_sport_breakdown
-- Returns one row per sport the user practices, with their level and how many
-- completed activities they've done in that sport.
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_sport_breakdown(
  p_user_id UUID
)
RETURNS TABLE (
  sport_key TEXT,
  sport_icon TEXT,
  level TEXT,
  completed_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.key::TEXT AS sport_key,
    s.icon::TEXT AS sport_icon,
    COALESCE((u.levels_per_sport ->> s.key::text), NULL)::TEXT AS level,
    COALESCE((
      SELECT count(*)::int
      FROM participations par
      JOIN activities a ON a.id = par.activity_id
      WHERE par.user_id = p_user_id
        AND par.status = 'accepted'
        AND a.status = 'completed'
        AND a.sport_id = s.id
        AND a.deleted_at IS NULL
    ), 0) AS completed_count
  FROM users u
  CROSS JOIN LATERAL jsonb_array_elements_text(u.sports) AS user_sport_key
  JOIN sports s ON s.key = user_sport_key
  WHERE u.id = p_user_id
  ORDER BY completed_count DESC, s.display_order ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_breakdown FROM anon;
GRANT EXECUTE ON FUNCTION get_user_sport_breakdown TO authenticated;
