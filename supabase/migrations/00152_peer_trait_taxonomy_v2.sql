-- Migration 00152: peer trait taxonomy v2.
--
-- Phase 2 of the profile remodel — swap the peer-vote vocabulary to a
-- tighter, behavior-focused set:
--
--   POSITIVES (4): punctual · prepared · conciliant · prudent
--   NEGATIVES (4): late_canceller · level_overestimated · aggressive · reckless
--
-- Kept from the previous set:
--   punctual, level_overestimated, aggressive
-- Renamed (semantically) — old key is dropped from the whitelist; old rows
-- stay in `reputation_votes` for history but no longer surface (the client
-- no longer reads them and `get_user_reputation` only returns counts for
-- keys that have at least one vote — old rows still group by their old key
-- but the client filter doesn't include them).
--   trustworthy → dropped
--   great_leader → dropped
--   good_vibes → dropped
--   difficult_attitude → dropped
--   unreliable_field → late_canceller (more specific: late cancel)
-- New:
--   prepared, conciliant, prudent, late_canceller, reckless
--
-- Only `give_reputation_badge` enforces the whitelist; `revoke_reputation_badge`
-- accepts any key by design (so users can still revoke a vote on a
-- now-deprecated key if they ever need to roll back history).

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
    -- Positives
    'punctual', 'prepared', 'conciliant', 'prudent',
    -- Negatives
    'late_canceller', 'level_overestimated', 'aggressive', 'reckless'
  ];
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

  INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, p_badge_key, now());
END;
$$;

REVOKE EXECUTE ON FUNCTION give_reputation_badge FROM anon;
GRANT EXECUTE ON FUNCTION give_reputation_badge TO authenticated;

-- Update the negative-keys list inside get_user_reputation so the active
-- count + decay logic still applies to the right set after the rename.
-- Migration 00151 hard-coded the old negative keys; bump them here.
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
    'late_canceller', 'level_overestimated', 'aggressive', 'reckless',
    -- Keep deprecated negatives in the decay branch too so any historical
    -- rows still apply decay (they won't surface client-side, but
    -- keeping the math consistent costs nothing).
    'unreliable_field', 'difficult_attitude'
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
