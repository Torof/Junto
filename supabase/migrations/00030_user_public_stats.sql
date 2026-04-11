-- Migration 00030: get_user_public_stats function
-- Returns aggregate activity stats for any user (no location/date details exposed)

CREATE OR REPLACE FUNCTION get_user_public_stats(
  p_user_id UUID
)
RETURNS TABLE (
  total_activities INTEGER,
  completed_activities INTEGER,
  sports_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT count(*)::int FROM participations
     WHERE user_id = p_user_id AND status = 'accepted') AS total_activities,
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id AND par.status = 'accepted' AND a.status = 'completed') AS completed_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_public_stats FROM anon;
GRANT EXECUTE ON FUNCTION get_user_public_stats TO authenticated;
