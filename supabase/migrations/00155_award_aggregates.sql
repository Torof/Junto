-- Migration 00155: aggregate stats for the Junto award system.
--
-- Replaces piecemeal "joined / created tier" reads with a single RPC that
-- returns the aggregates the client uses to evaluate a flexible, data-driven
-- list of awards. The award definitions themselves live in the client
-- (src/components/badge-display.tsx) — adding / removing / tuning a badge
-- is a code change, not a schema change.
--
-- Returns one JSONB:
--   {
--     joined:           number — completed activities the user joined (not creator)
--     created:          number — completed activities the user created
--     distinct_sports:  number — distinct sports the user has any completion in
--     multi_day_count:  number — completed activities with duration > 1 day
--     by_category:      { [sport_category]: { outings, distinct_sports } }
--   }

CREATE OR REPLACE FUNCTION get_user_award_aggregates(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH completed AS (
    SELECT
      a.id,
      a.creator_id,
      a.duration,
      s.key AS sport_key,
      s.category
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND a.status = 'completed'
  ),
  per_category AS (
    SELECT
      category,
      count(*)::int AS outings,
      count(DISTINCT sport_key)::int AS distinct_sports
    FROM completed
    GROUP BY category
  )
  SELECT jsonb_build_object(
    'joined', (SELECT count(*)::int FROM completed WHERE creator_id IS DISTINCT FROM p_user_id),
    'created', (SELECT count(*)::int FROM completed WHERE creator_id = p_user_id),
    'distinct_sports', (SELECT count(DISTINCT sport_key)::int FROM completed),
    'multi_day_count', (SELECT count(*)::int FROM completed WHERE duration > INTERVAL '1 day'),
    'by_category', COALESCE((
      SELECT jsonb_object_agg(category, jsonb_build_object(
        'outings', outings,
        'distinct_sports', distinct_sports
      )) FROM per_category
    ), '{}'::jsonb)
  );
$$;

REVOKE EXECUTE ON FUNCTION get_user_award_aggregates FROM anon;
GRANT EXECUTE ON FUNCTION get_user_award_aggregates TO authenticated;
