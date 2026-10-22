-- Migration 00153: per-sport level derived from completed activities.
--
-- Phase 3 of the profile remodel. The 4-dot level on each sport chip is
-- earned, never claimed:
--
--   Dot 1 (Beginner)     — ≥1 completed activity in this sport, any level.
--   Dot 2 (Intermediate) — ≥3 completed activities at intermediate level or above.
--   Dot 3 (Advanced)     — ≥5 completed activities at advanced level or above.
--   Dot 4 (Expert)       — ≥3 completed activities at expert level.
--
-- The displayed dot count is the highest threshold the user has crossed.
-- Activity.level is stored verbatim from the creation form, which can be
-- French (`débutant` / `intermédiaire` / `avancé` / `expert`) or English
-- (`beginner` / `intermediate` / `advanced` / `expert`); we match both.

CREATE OR REPLACE FUNCTION get_user_sport_levels(p_user_id UUID)
RETURNS TABLE (
  sport_key TEXT,
  dots SMALLINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH completed AS (
    SELECT s.key AS sport_key, a.level AS level
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND a.status = 'completed'
  ),
  agg AS (
    SELECT
      sport_key,
      count(*) AS total,
      count(*) FILTER (
        WHERE level IN ('intermédiaire', 'intermediate', 'avancé', 'advanced', 'expert')
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE level IN ('avancé', 'advanced', 'expert')
      ) AS at_advanced,
      count(*) FILTER (WHERE level = 'expert') AS at_expert
    FROM completed
    GROUP BY sport_key
  )
  SELECT
    sport_key,
    (CASE
      WHEN at_expert >= 3 THEN 4
      WHEN at_advanced >= 5 THEN 3
      WHEN at_intermediate >= 3 THEN 2
      WHEN total >= 1 THEN 1
      ELSE 0
    END)::SMALLINT AS dots
  FROM agg
  WHERE total > 0;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_levels FROM anon;
GRANT EXECUTE ON FUNCTION get_user_sport_levels TO authenticated;
