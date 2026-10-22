-- Migration 00169: expose voter avatars per badge for the Vouched popup.
--
-- The trust-pillar popup remodel surfaces real peer profile pictures in
-- the Vouched card's avatar stack (no nav click-through). The data lives
-- in reputation_votes (voter_id, voted_id, badge_key); this RPC joins
-- those to public_profiles to return up to 8 most-recent voter avatars
-- for a given (target user, badge) pair.
--
-- Privacy posture: this intentionally exposes voter identity visually
-- (avatar + display_name). The peer-voting UI doesn't promise
-- anonymity in the spec; the previous popup variant was anonymous-by-
-- default but Scott opted to surface real avatars to strengthen the
-- "people you might know vouched" trust signal. Click-through is NOT
-- offered in the popup — visual only.
--
-- Auth: anyone authenticated may call. The data set is bounded to
-- avatars + display names that are already visible via public_profiles
-- elsewhere in the app, so this isn't a privacy escalation per se;
-- it's a re-exposure of data already accessible.

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
  SELECT
    pp.id           AS voter_id,
    pp.display_name AS display_name,
    pp.avatar_url   AS avatar_url,
    rv.created_at   AS voted_at
  FROM reputation_votes rv
  JOIN public_profiles pp ON pp.id = rv.voter_id
  WHERE rv.voted_id  = p_user_id
    AND rv.badge_key = p_badge_key
  ORDER BY rv.created_at DESC
  LIMIT 8;
$$;

REVOKE EXECUTE ON FUNCTION get_voters_for_badge FROM anon;
GRANT EXECUTE ON FUNCTION get_voters_for_badge TO authenticated;
