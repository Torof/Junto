-- Migration 00105: peer review unified system
--
-- Adds the peer-presence verification layer alongside the existing reputation
-- badges (migration 00034). One UI page covers both:
--   - reputation badge votes (toggle on/off)
--   - peer presence validation (one-way; flips confirmed_present once 2 votes)
--
-- The creator gets the same UI but their presence vote bypasses the threshold
-- and uses creator_override_presence directly (handled client-side).

-- ============================================================================
-- TABLE: peer_validations — votes that a co-participant was present
-- ============================================================================
CREATE TABLE peer_validations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  voter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  voted_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  CHECK (voter_id != voted_id),
  UNIQUE (voter_id, voted_id, activity_id)
);

CREATE INDEX idx_peer_validations_activity_voted ON peer_validations(activity_id, voted_id);

ALTER TABLE peer_validations ENABLE ROW LEVEL SECURITY;
ALTER TABLE peer_validations FORCE ROW LEVEL SECURITY;

CREATE POLICY "peer_validations_select"
  ON peer_validations FOR SELECT
  TO authenticated
  USING (auth.uid() = voter_id OR auth.uid() = voted_id);

-- INSERT/DELETE via RPC only.

-- ============================================================================
-- FUNCTION: peer_validate_presence
--   Vote that a co-participant was present. Once a target has ≥2 votes from
--   distinct *confirmed_present* peers, their confirmed_present flips to TRUE
--   and their reliability score is recalculated.
-- ============================================================================
CREATE OR REPLACE FUNCTION peer_validate_presence(
  p_voted_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_voter_present BOOLEAN;
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 48h window post-activity (matches reputation badges window)
  IF v_activity.starts_at + v_activity.duration + INTERVAL '48 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Voter must be a confirmed-present participant of this activity
  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Voted must be an accepted participant whose presence is still unvalidated
  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Insert vote (UNIQUE handles double-vote attempts)
  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  -- Threshold check: if voted now has ≥2 votes, flip their presence
  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  IF v_vote_count >= 2 THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    PERFORM recalculate_reliability_score(p_voted_id);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION peer_validate_presence FROM anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence TO authenticated;


-- ============================================================================
-- FUNCTION: revoke_reputation_badge — toggle off a badge vote
-- ============================================================================
CREATE OR REPLACE FUNCTION revoke_reputation_badge(
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Window check (matches give_reputation_badge — only revoke during the same 48h window)
  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '48 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM reputation_votes
  WHERE voter_id = v_user_id
    AND voted_id = p_voted_id
    AND activity_id = p_activity_id
    AND badge_key = p_badge_key;
END;
$$;

REVOKE EXECUTE ON FUNCTION revoke_reputation_badge FROM anon;
GRANT EXECUTE ON FUNCTION revoke_reputation_badge TO authenticated;


-- ============================================================================
-- FUNCTION: get_activity_peer_review_state
--   Returns one row per *other* accepted participant of the activity, with:
--   - their identity (display_name, avatar_url)
--   - confirmed_present (true/false/null)
--   - peer_validation_count (how many peers vouched for their presence)
--   - i_voted_presence (have I already vouched for them)
--   - my_badge_votes (TEXT[] — badges I've voted for them on this activity)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_activity_peer_review_state(
  p_activity_id UUID
)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  confirmed_present BOOLEAN,
  peer_validation_count INTEGER,
  i_voted_presence BOOLEAN,
  my_badge_votes TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Caller must be an accepted participant of the activity
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    p.user_id,
    pp.display_name,
    pp.avatar_url,
    p.confirmed_present,
    coalesce(pv_counts.cnt, 0)::int AS peer_validation_count,
    EXISTS (
      SELECT 1 FROM peer_validations
      WHERE voter_id = v_user_id AND voted_id = p.user_id AND activity_id = p_activity_id
    ) AS i_voted_presence,
    coalesce(my_votes.keys, ARRAY[]::TEXT[]) AS my_badge_votes
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  LEFT JOIN (
    SELECT voted_id, count(*)::int AS cnt
    FROM peer_validations
    WHERE activity_id = p_activity_id
    GROUP BY voted_id
  ) pv_counts ON pv_counts.voted_id = p.user_id
  LEFT JOIN (
    SELECT voted_id, array_agg(badge_key) AS keys
    FROM reputation_votes
    WHERE activity_id = p_activity_id AND voter_id = v_user_id
    GROUP BY voted_id
  ) my_votes ON my_votes.voted_id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id != v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_peer_review_state FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_peer_review_state TO authenticated;
