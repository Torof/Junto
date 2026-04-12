-- Migration 00034: Reputation badges (peer-given) + Trophy badges (automatic)

-- ============================================================================
-- TABLE: reputation_votes
-- ============================================================================
CREATE TABLE reputation_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  voter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  voted_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  badge_key TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  CHECK (voter_id != voted_id),
  UNIQUE (voter_id, voted_id, activity_id, badge_key)
);

CREATE INDEX idx_reputation_votes_voted ON reputation_votes(voted_id);

ALTER TABLE reputation_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE reputation_votes FORCE ROW LEVEL SECURITY;

-- SELECT: own votes + votes about you (for display)
CREATE POLICY "reputation_votes_select"
  ON reputation_votes FOR SELECT
  TO authenticated
  USING (auth.uid() = voter_id OR auth.uid() = voted_id);

-- INSERT/UPDATE/DELETE: via function only

-- ============================================================================
-- FUNCTION: give_reputation_badge
-- ============================================================================
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
    'trustworthy', 'level_accurate', 'great_leader', 'good_vibes', 'punctual',
    'level_overestimated', 'difficult_attitude', 'unreliable_field', 'aggressive'
  ];
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Can't vote for yourself
  IF v_user_id = p_voted_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Valid badge key
  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Activity must be completed
  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Within 48h window
  IF v_activity.starts_at + v_activity.duration + INTERVAL '48 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Both users must be accepted participants of this activity
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

  -- 8. Insert vote (UNIQUE constraint prevents duplicates)
  INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, p_badge_key, now());
END;
$$;

REVOKE EXECUTE ON FUNCTION give_reputation_badge FROM anon;
GRANT EXECUTE ON FUNCTION give_reputation_badge TO authenticated;

-- ============================================================================
-- FUNCTION: get_user_reputation (returns badge counts for a user)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_reputation(
  p_user_id UUID
)
RETURNS TABLE (
  badge_key TEXT,
  vote_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT rv.badge_key, count(*)::int AS vote_count
  FROM reputation_votes rv
  WHERE rv.voted_id = p_user_id
  GROUP BY rv.badge_key;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_reputation FROM anon;
GRANT EXECUTE ON FUNCTION get_user_reputation TO authenticated;

-- ============================================================================
-- FUNCTION: get_user_trophies (returns trophy badges for a user)
-- Computed from participation + activity data, no separate table needed
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_trophies(
  p_user_id UUID
)
RETURNS TABLE (
  trophy_key TEXT,
  trophy_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_completed INTEGER;
BEGIN
  -- Total completed activities
  SELECT count(*)::int INTO v_total_completed
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND a.status = 'completed';

  -- Progression trophies
  RETURN QUERY SELECT 'progression'::text, v_total_completed;

  -- Sport-specific trophies (count per sport)
  RETURN QUERY
  SELECT
    s.key::text AS trophy_key,
    count(*)::int AS trophy_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND a.status = 'completed'
  GROUP BY s.key;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_trophies FROM anon;
GRANT EXECUTE ON FUNCTION get_user_trophies TO authenticated;
