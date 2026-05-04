-- Migration 00174: batch-fetch top positive peer-vouch per user.
--
-- The Organisation tab's GroupCard puts the trust pillar's peer-vouch
-- signal at the actual decision point: each driver row shows their
-- highest-count positive peer-vouch ("Punctuel", "Préparé", etc.) next
-- to their name, so a passenger weighing "should I ride with this
-- stranger?" gets the social proof inline.
--
-- N drivers per activity → without a batch RPC we'd issue N round-
-- trips (or read the full reputation per user). This function takes
-- an array of user_ids and returns one row per user — the highest-
-- vouched positive trait that's crossed the 5-vote visibility floor.
-- Users with no positive trait above threshold simply don't appear
-- in the result (handled client-side as "no chip").
--
-- Auth posture: same as get_voters_for_badge (00169). Reputation
-- aggregates are deliberately public — the trust pillar's whole
-- premise is that vouches are visible to others — so we just gate
-- on authenticated and rely on RLS / SECURITY DEFINER for the rest.
-- No further chain since we read aggregated counts only, no PII.

CREATE OR REPLACE FUNCTION get_top_vouched_badges(p_user_ids UUID[])
RETURNS TABLE (
  user_id UUID,
  badge_key TEXT,
  vote_count INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION get_top_vouched_badges FROM anon;
GRANT EXECUTE ON FUNCTION get_top_vouched_badges TO authenticated;
