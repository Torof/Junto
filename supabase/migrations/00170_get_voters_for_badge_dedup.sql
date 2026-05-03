-- Migration 00170: dedup voters in get_voters_for_badge.
--
-- 00169 returned one row per reputation_votes record, so a voter who
-- vouched the same trait across multiple activities appeared multiple
-- times in the Vouched popup avatar stack. Scott's call: each voter
-- should appear at most once, no matter how many times they voted.
--
-- Fix: DISTINCT ON (voter_id) keeps the most recent vote per voter,
-- then re-orders the deduped set by recency for the LIMIT.
--
-- Auth chain unchanged from 00169 — same SECURITY DEFINER posture,
-- same anon REVOKE, same authenticated GRANT.

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
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
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
  ORDER BY deduped.voted_at DESC
  LIMIT 8;
$$;

REVOKE EXECUTE ON FUNCTION get_voters_for_badge FROM anon;
GRANT EXECUTE ON FUNCTION get_voters_for_badge TO authenticated;
