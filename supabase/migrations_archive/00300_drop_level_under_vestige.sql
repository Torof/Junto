-- Migration 00300: drop the `level_under` vestige from the sport-level tally.
--
-- The current peer model has exactly TWO votes: juste (`level_right`, ▲) and
-- surestimé (`level_over`, ▼). `level_under` ("sous-estimé") was a third vote
-- from an earlier design — no UI casts it (client LEVEL_VOTE_KEYS = over/right)
-- and mig 00159 already blocks any NEW `level_under` from being written. Only
-- historical rows could still carry it, and get_user_sport_level_votes still
-- returned it (folded into the client's "fiable" count). Scott (2026-07-08):
-- remove it everywhere so the verdict is strictly juste vs surestimé.
--
-- Return-type change (dropping a TABLE column) => must DROP then CREATE; a bare
-- CREATE OR REPLACE would error "cannot change return type". Grants are
-- re-issued because DROP discards them. Body otherwise identical to 00289
-- (12-month sliding window preserved).
--
-- The `NOT IN (..., 'level_under')` guards in migs 00154/00236 are left as-is:
-- they only EXCLUDE the key, so they stay harmless with or without it.

DROP FUNCTION IF EXISTS get_user_sport_level_votes(UUID);

CREATE FUNCTION get_user_sport_level_votes(p_user_id UUID)
RETURNS TABLE (
  sport_key TEXT,
  level_over INTEGER,
  level_right INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.key AS sport_key,
    count(*) FILTER (WHERE rv.badge_key = 'level_over')::int AS level_over,
    count(*) FILTER (WHERE rv.badge_key = 'level_right')::int AS level_right
  FROM reputation_votes rv
  JOIN activities a ON a.id = rv.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE rv.voted_id = p_user_id
    AND rv.badge_key IN ('level_over', 'level_right')
    AND rv.created_at >= now() - INTERVAL '12 months'   -- sliding freshness window
  GROUP BY s.key
  HAVING count(*) > 0;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_level_votes FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_sport_level_votes TO authenticated;
