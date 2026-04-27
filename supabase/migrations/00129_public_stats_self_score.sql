-- Migration 00129: get_user_public_stats also returns the raw
-- reliability_score, but only when the caller is the user being queried.
-- Other-user views still get NULL for the score; tier remains the public
-- surface for everyone. Lets the user's own public profile show their
-- precise percentage on the same screen used by other users.

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
  reliability_score FLOAT,
  reliability_tier TEXT
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
    (SELECT count(*)::int FROM activities
     WHERE creator_id = p_user_id AND deleted_at IS NULL) AS created_activities,
    (SELECT count(*)::int FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL) AS joined_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    (SELECT CASE WHEN auth.uid() = p_user_id THEN u.reliability_score ELSE NULL END
     FROM users u WHERE u.id = p_user_id) AS reliability_score,
    (SELECT public.reliability_tier(u.reliability_score)
     FROM users u WHERE u.id = p_user_id) AS reliability_tier;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_public_stats FROM anon;
GRANT EXECUTE ON FUNCTION get_user_public_stats TO authenticated;
