-- Migration 00097: per-sport level endorsements
-- Replaces the generic `level_accurate` reputation badge with a granular
-- per-sport vote system. Co-participants of an activity can confirm or
-- contest a target's self-declared level in that activity's sport.

CREATE TABLE sport_level_endorsements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  voter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  sport_key TEXT NOT NULL,
  is_confirmation BOOLEAN NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (voter_id != target_id),
  UNIQUE (voter_id, target_id, activity_id, sport_key)
);

CREATE INDEX idx_sport_level_endorsements_target ON sport_level_endorsements(target_id);
CREATE INDEX idx_sport_level_endorsements_target_sport ON sport_level_endorsements(target_id, sport_key);

ALTER TABLE sport_level_endorsements ENABLE ROW LEVEL SECURITY;
ALTER TABLE sport_level_endorsements FORCE ROW LEVEL SECURITY;

-- Authenticated users can read all rows (needed to aggregate on any profile).
CREATE POLICY "sport_level_endorsements_select"
  ON sport_level_endorsements FOR SELECT
  TO authenticated
  USING (true);

-- No direct INSERT/UPDATE/DELETE. Writes go through RPC.

-- ============================================================================
-- RPC: submit_sport_level_endorsement
-- Authorization chain:
--   1. auth.uid() IS NOT NULL
--   2. voter not suspended
--   3. voter != target
--   4. voter was accepted + confirmed_present in the activity
--   5. target was accepted participant of the activity
--   6. activity's sport equals p_sport_key
--   7. target has a declared level for p_sport_key in users.levels_per_sport
-- ============================================================================
CREATE OR REPLACE FUNCTION submit_sport_level_endorsement(
  p_target_id UUID,
  p_activity_id UUID,
  p_sport_key TEXT,
  p_is_confirmation BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity_sport_id UUID;
  v_activity_sport_key TEXT;
  v_target_levels JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_target_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id
      AND user_id = v_user_id
      AND status = 'accepted'
      AND confirmed_present = true
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id
      AND user_id = p_target_id
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.sport_id, s.key
  INTO v_activity_sport_id, v_activity_sport_key
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  IF v_activity_sport_key IS NULL OR v_activity_sport_key != p_sport_key THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT levels_per_sport INTO v_target_levels FROM users WHERE id = p_target_id;
  IF v_target_levels IS NULL OR NOT (v_target_levels ? p_sport_key) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO sport_level_endorsements
    (voter_id, target_id, activity_id, sport_key, is_confirmation)
  VALUES
    (v_user_id, p_target_id, p_activity_id, p_sport_key, p_is_confirmation)
  ON CONFLICT (voter_id, target_id, activity_id, sport_key)
    DO UPDATE SET
      is_confirmation = EXCLUDED.is_confirmation,
      created_at = now();
END;
$$;

REVOKE EXECUTE ON FUNCTION submit_sport_level_endorsement FROM anon;
GRANT EXECUTE ON FUNCTION submit_sport_level_endorsement TO authenticated;

-- ============================================================================
-- RPC: get_user_sport_endorsements — returns net count per sport
-- (confirmations - contestations). Positive = level confirmed, negative =
-- level contested, zero or missing = no signal.
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_sport_endorsements(p_user_id UUID)
RETURNS TABLE (sport_key TEXT, net_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT
      sle.sport_key,
      (SUM(CASE WHEN sle.is_confirmation THEN 1 ELSE -1 END))::INTEGER AS net_count
    FROM sport_level_endorsements sle
    WHERE sle.target_id = p_user_id
    GROUP BY sle.sport_key;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_endorsements FROM anon;
GRANT EXECUTE ON FUNCTION get_user_sport_endorsements TO authenticated;
