-- Migration 00107: align all peer-review windows to 24h post-activity.
-- Was 48h for badges + peer presence (heritage from migration 00034) and
-- 12h for the no-show auto-capture. 24h gives peers one night + morning to
-- act while keeping memory fresh and closing the loop quickly.

-- ----------------------------------------------------------------------------
-- 1. close_presence_window_for: 12h → 24h
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION close_presence_window_for(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  FOR v_target IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status = 'accepted'
      AND confirmed_present IS NULL
  LOOP
    UPDATE participations
    SET confirmed_present = FALSE
    WHERE activity_id = p_activity_id
      AND user_id = v_target.user_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target.user_id);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION close_presence_window_for FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. close_due_presence_windows: 12h → 24h (sweeper)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION close_due_presence_windows()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.starts_at + a.duration + INTERVAL '24 hours' < now()
      AND a.deleted_at IS NULL
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id
          AND p.status = 'accepted'
          AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION close_due_presence_windows FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. peer_validate_presence: 48h → 24h
-- ----------------------------------------------------------------------------
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
  v_is_creator BOOLEAN;
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

  SELECT id, creator_id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_creator := (v_user_id = v_activity.creator_id);

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_is_creator THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    PERFORM recalculate_reliability_score(p_voted_id);
    RETURN;
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

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

-- ----------------------------------------------------------------------------
-- 4. revoke_reputation_badge: 48h → 24h
-- ----------------------------------------------------------------------------
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

  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
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

-- ----------------------------------------------------------------------------
-- 5. give_reputation_badge: 48h → 24h (legacy from migration 00034)
-- ----------------------------------------------------------------------------
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
