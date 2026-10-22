-- Migration 00289: window the per-sport level-vote tally to the last 12 months.
--
-- Profile rework (Scott 2026-07-07): the "Sports pratiqués" chips show a small
-- ▲/▼ triangle for a declared level clearly confirmed / clearly contested by
-- peers. A user who declared "intermédiaire" as a beginner and got ▼ votes,
-- then genuinely improved, must not carry those old ▼ forever — so votes older
-- than 12 months stop counting. A sliding window is the no-machinery fix Scott
-- chose (no per-vote snapshots): progression naturally sheds stale votes, an
-- inactive sport goes neutral (no triangle).
--
-- Body copied VERBATIM from 00154 plus one predicate. reputation_votes.created_at
-- verified present. Same signature → grants preserved by CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION get_user_sport_level_votes(p_user_id UUID)
RETURNS TABLE (
  sport_key TEXT,
  level_over INTEGER,
  level_right INTEGER,
  level_under INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.key AS sport_key,
    count(*) FILTER (WHERE rv.badge_key = 'level_over')::int AS level_over,
    count(*) FILTER (WHERE rv.badge_key = 'level_right')::int AS level_right,
    count(*) FILTER (WHERE rv.badge_key = 'level_under')::int AS level_under
  FROM reputation_votes rv
  JOIN activities a ON a.id = rv.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE rv.voted_id = p_user_id
    AND rv.badge_key IN ('level_over', 'level_right', 'level_under')
    AND rv.created_at >= now() - INTERVAL '12 months'   -- sliding freshness window
  GROUP BY s.key
  HAVING count(*) > 0;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_level_votes FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_sport_level_votes TO authenticated;
