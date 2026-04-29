-- Migration 00154: per-sport level votes + final taxonomy.
--
-- Phase of the profile remodel that finalizes the peer-vote vocabulary:
--
--   GLOBAL POSITIVES (4): punctual, prepared, conciliant, prudent
--   GLOBAL NEGATIVES (3): unprepared, aggressive, reckless
--   PER-SPORT LEVEL (3, mutually exclusive per voter+activity+voted):
--                       level_over, level_right, level_under
--
-- Why this set:
--   - Lâcheur (late_canceller) was redundant with the reliability score —
--     dropped.
--   - level_overestimated graduates from a global negative to a per-sport
--     3-way vote (over / right / under) that lives in the sport popover,
--     not in the global warning row. Level honesty is naturally per-sport
--     and shouldn't surface as a blanket "this person lies about level".
--   - unprepared replaces level_overestimated as the global preparation
--     negative (showed up but not gear-ready / route-prepped).
--
-- Old votes (trustworthy / great_leader / good_vibes / difficult_attitude /
-- unreliable_field / level_overestimated / late_canceller) stay in
-- reputation_votes for history but never surface anywhere.

-- ============================================================================
-- 1. give_reputation_badge — new whitelist + level-vote mutual exclusion
-- ============================================================================
-- Level votes are 3-way: a voter must pick ONE of (over / right / under) per
-- (target, activity). Casting a different level vote replaces the previous
-- one. Same-key tap goes through revoke_reputation_badge from the client
-- (toggle-off semantics).

CREATE OR REPLACE FUNCTION give_reputation_badge(
  p_voted_id UUID,
  p_activity_id UUID,
  p_badge_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_valid_keys TEXT[] := ARRAY[
    -- Global positives
    'punctual', 'prepared', 'conciliant', 'prudent',
    -- Global negatives
    'unprepared', 'aggressive', 'reckless',
    -- Per-sport level votes (mutually exclusive)
    'level_over', 'level_right', 'level_under'
  ];
  v_level_keys TEXT[] := ARRAY['level_over', 'level_right', 'level_under'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_voted_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Level votes are mutually exclusive per (voter, voted, activity). Drop
  -- any existing level vote from this voter on this target before inserting
  -- the new one. If the same key is being re-cast, the existing row would
  -- otherwise collide with the UNIQUE constraint (and the client would have
  -- gone through revoke for a toggle-off anyway).
  IF p_badge_key = ANY(v_level_keys) THEN
    DELETE FROM reputation_votes
    WHERE voter_id = v_user_id
      AND voted_id = p_voted_id
      AND activity_id = p_activity_id
      AND badge_key = ANY(v_level_keys);
  END IF;

  INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, p_badge_key, now());
END;
$$;

REVOKE EXECUTE ON FUNCTION give_reputation_badge FROM anon;
GRANT EXECUTE ON FUNCTION give_reputation_badge TO authenticated;

-- ============================================================================
-- 2. get_user_reputation — exclude level_* from global rollup
-- ============================================================================
-- Level votes are surfaced per-sport via get_user_sport_level_votes; they
-- have no place in the global vouched / warning rows. Filter them out at
-- the source.

DROP FUNCTION IF EXISTS get_user_reputation(UUID);

CREATE OR REPLACE FUNCTION get_user_reputation(
  p_user_id UUID
)
RETURNS TABLE (
  badge_key TEXT,
  vote_count INTEGER,
  last_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_negative_keys TEXT[] := ARRAY[
    'unprepared', 'aggressive', 'reckless',
    -- Keep deprecated negatives in the decay branch so any historical rows
    -- still apply decay (not surfaced client-side, but math stays clean).
    'late_canceller', 'level_overestimated', 'unreliable_field', 'difficult_attitude'
  ];
BEGIN
  RETURN QUERY
  WITH grouped AS (
    SELECT
      rv.badge_key,
      count(*)::int AS total_count,
      max(rv.created_at) AS max_at
    FROM reputation_votes rv
    WHERE rv.voted_id = p_user_id
      -- Per-sport level votes are surfaced through get_user_sport_level_votes
      AND rv.badge_key NOT IN ('level_over', 'level_right', 'level_under')
    GROUP BY rv.badge_key
  )
  SELECT
    g.badge_key,
    CASE
      WHEN g.badge_key = ANY(v_negative_keys)
        THEN get_active_negative_count(p_user_id, g.badge_key)
      ELSE g.total_count
    END AS vote_count,
    g.max_at AS last_at
  FROM grouped g
  WHERE
    NOT (
      g.badge_key = ANY(v_negative_keys)
      AND get_active_negative_count(p_user_id, g.badge_key) = 0
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_reputation FROM anon;
GRANT EXECUTE ON FUNCTION get_user_reputation TO authenticated;

-- ============================================================================
-- 3. get_user_sport_level_votes — per-sport tally of the 3-way level vote
-- ============================================================================
-- Returns one row per sport the user has any level vote on, with the three
-- counts. Client renders these inside the sport popover only.

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
  GROUP BY s.key
  HAVING count(*) > 0;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_level_votes FROM anon;
GRANT EXECUTE ON FUNCTION get_user_sport_level_votes TO authenticated;
