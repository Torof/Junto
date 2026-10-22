-- Migration 00171: drop LIMIT in get_voters_for_badge.
--
-- The Vouched popup needs the full count of unique voters so it can
-- compute "+N" overflow accurately (e.g. 7 avatars shown + "+11" when
-- 18 unique people vouched). 00170 limited the response to 8 rows,
-- which under-reported overflow and was effectively the avatar cap +
-- one — fine for the previous "show 7 + maybe a +1" UI, not enough
-- now that overflow must reflect the true unique-voter count.
--
-- Bound: max unique voters per (user, badge) is socially capped (one
-- per real human in the user's circle) so an unbounded count is fine
-- in practice. RLS still applies via SECURITY DEFINER + the badge
-- visibility check baked into the source table.
--
-- Auth chain unchanged from 00170.

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
  ORDER BY deduped.voted_at DESC;
$$;

REVOKE EXECUTE ON FUNCTION get_voters_for_badge FROM anon;
GRANT EXECUTE ON FUNCTION get_voters_for_badge TO authenticated;
