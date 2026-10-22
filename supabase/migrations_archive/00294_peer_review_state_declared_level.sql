-- ============================================================================
-- 00294 — Peer-review state exposes each participant's declared level
--
-- So the peer-review UI can HIDE the level-vote section for a participant who
-- hasn't declared a level for the activity's sport (complements the 00293 server
-- guard). Read-only function; authorization chain UNCHANGED (auth + caller is an
-- accepted participant). Adds one PUBLIC field, `declared_level`, sourced from
-- the public_profiles view (never the users table) — the level is already public.
--
-- Reproduced verbatim from 00138 + three edits: v_sport_key declare, the sport
-- lookup, and the `declared_level` field in the built object.
-- ============================================================================
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
  v_sport_key TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

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
      'my_badge_votes',         coalesce(my_votes.keys, ARRAY[]::TEXT[]),
      'declared_level',         NULLIF(pp.levels_per_sport ->> v_sport_key, '')
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
