-- Migration 00138: get_activity_peer_review_state returns jsonb (not TABLE).
-- The TABLE-returning form had OUT parameters whose names clashed with
-- columns in the FROM clause (user_id, display_name, etc.), which Postgres
-- flagged as ambiguous at runtime in some configurations. Rewriting as
-- RETURNS jsonb sidesteps the OUT-param scope entirely — the SELECT just
-- builds an array of objects with the right keys.

DROP FUNCTION IF EXISTS get_activity_peer_review_state(UUID);

CREATE OR REPLACE FUNCTION get_activity_peer_review_state(
  p_activity_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_result jsonb;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id',                p.user_id,
      'display_name',           pp.display_name,
      'avatar_url',             pp.avatar_url,
      'confirmed_present',      p.confirmed_present,
      'peer_validation_count',  coalesce(pv_counts.cnt, 0),
      'i_voted_presence',       EXISTS (
        SELECT 1 FROM peer_validations
        WHERE voter_id = v_user_id
          AND voted_id = p.user_id
          AND activity_id = p_activity_id
      ),
      'my_badge_votes',         coalesce(my_votes.keys, ARRAY[]::TEXT[])
    )
  ) INTO v_result
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  LEFT JOIN (
    SELECT voted_id, count(*)::int AS cnt
    FROM peer_validations
    WHERE activity_id = p_activity_id
    GROUP BY voted_id
  ) pv_counts ON pv_counts.voted_id = p.user_id
  LEFT JOIN (
    SELECT voted_id, array_agg(badge_key) AS keys
    FROM reputation_votes
    WHERE activity_id = p_activity_id AND voter_id = v_user_id
    GROUP BY voted_id
  ) my_votes ON my_votes.voted_id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id != v_user_id;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_peer_review_state FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_peer_review_state TO authenticated;
