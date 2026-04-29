-- Migration 00156: extend get_user_sport_levels with recency + activity span.
--
-- Per-sport popover wants to surface "are they still active?" and "how
-- regularly?" — both derived from the same JOIN we already do for level.
-- Adding last_at (most recent completion) and first_at (earliest
-- completion) lets the client compute frequency = count / months_active.

DROP FUNCTION IF EXISTS get_user_sport_levels(UUID);

CREATE OR REPLACE FUNCTION get_user_sport_levels(p_user_id UUID)
RETURNS TABLE (
  sport_key TEXT,
  dots SMALLINT,
  last_at TIMESTAMPTZ,
  first_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH completed AS (
    SELECT s.key AS sport_key, a.level AS level, a.starts_at AS at
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
      count(*) FILTER (WHERE level = 'expert') AS at_expert,
      max(at) AS last_at,
      min(at) AS first_at
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
    END)::SMALLINT AS dots,
    last_at,
    first_at
  FROM agg
  WHERE total > 0;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_levels FROM anon;
GRANT EXECUTE ON FUNCTION get_user_sport_levels TO authenticated;
