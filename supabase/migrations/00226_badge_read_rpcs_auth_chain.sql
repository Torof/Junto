-- Migration 00226: get_voters_for_badge + get_top_vouched_badges get
-- the standard auth + suspension chain. From the parallel security
-- audit MINOR list.
--
-- Both functions are SECURITY DEFINER but only block anon via
-- REVOKE EXECUTE — once an authenticated caller is in, no
-- auth.uid() check, no suspension check. A suspended user could
-- keep browsing vouched-badge data on other users despite their
-- account being out of commission.
--
-- Reputation aggregates are deliberately public-to-authenticated
-- (the trust pillar premise: vouches are visible to others), so the
-- chain stops at suspension — no membership / target-visibility gate
-- needed. Returning empty (RETURN, not RAISE) on fail keeps these
-- read-only RPCs quiet for the client.
--
-- Both rewritten in plpgsql so the chain can short-circuit before
-- the SQL body. Bodies otherwise identical to 00171 / 00174.

-- ============================================================================
-- 1. get_voters_for_badge
-- ============================================================================

CREATE OR REPLACE FUNCTION get_voters_for_badge(
  p_user_id UUID,
  p_badge_key TEXT
)
RETURNS TABLE (
  voter_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  voted_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM (
    SELECT DISTINCT ON (rv.voter_id)
      pp.id           AS voter_id,
      pp.display_name AS display_name,
      pp.avatar_url   AS avatar_url,
      rv.created_at   AS voted_at
    FROM reputation_votes rv
    JOIN public_profiles pp ON pp.id = rv.voter_id
    WHERE rv.voted_id  = p_user_id
      AND rv.badge_key = p_badge_key
    ORDER BY rv.voter_id, rv.created_at DESC
  ) deduped
  ORDER BY deduped.voted_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_voters_for_badge FROM anon;
GRANT EXECUTE ON FUNCTION get_voters_for_badge TO authenticated;

-- ============================================================================
-- 2. get_top_vouched_badges
-- ============================================================================

CREATE OR REPLACE FUNCTION get_top_vouched_badges(p_user_ids UUID[])
RETURNS TABLE (
  user_id UUID,
  badge_key TEXT,
  vote_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH counts AS (
    SELECT
      rv.voted_id,
      rv.badge_key,
      COUNT(*)::INTEGER AS vote_count
    FROM reputation_votes rv
    WHERE rv.voted_id = ANY(p_user_ids)
      AND rv.badge_key IN ('punctual', 'prepared', 'conciliant', 'prudent')
    GROUP BY rv.voted_id, rv.badge_key
    HAVING COUNT(*) >= 5
  )
  SELECT DISTINCT ON (counts.voted_id)
    counts.voted_id   AS user_id,
    counts.badge_key  AS badge_key,
    counts.vote_count AS vote_count
  FROM counts
  ORDER BY counts.voted_id, counts.vote_count DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_top_vouched_badges FROM anon;
GRANT EXECUTE ON FUNCTION get_top_vouched_badges TO authenticated;
