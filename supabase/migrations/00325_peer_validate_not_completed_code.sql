-- Migration 00325: precise "activity not completed yet" error in peer validation
--
-- peer_validate_presence bundled three conditions into one generic "Operation
-- not permitted": activity missing, requires_presence false, and status !=
-- 'completed'. The status case is a benign TIMING issue (the lazy transition to
-- 'completed' hasn't run yet) — not sensitive — so surface it as a coded error
-- the client maps to "the activity isn't marked finished yet, try again". The
-- client also now forces the transition on the peer-review screen, so this
-- should rarely fire. Everything else in the function is unchanged (00272).

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
  v_accepted_count INTEGER;
  v_threshold INTEGER;
  v_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext('peer_validate:' || p_activity_id::text || ':' || p_voted_id::text)
  );

  SELECT id, creator_id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Benign timing: the lazy transition to 'completed' hasn't run yet.
  IF v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'junto.peer_review_not_completed';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.peer_review_window_not_open';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.peer_review_window_closed';
  END IF;

  v_is_creator := (v_user_id = v_activity.creator_id);

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;

  IF v_voted_status IS NULL OR v_voted_status != 'accepted' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.peer_already_validated';
  END IF;

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_is_creator AND v_accepted_count = 2 THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_flipped = ROW_COUNT;
    IF v_flipped > 0 THEN
      PERFORM recalculate_reliability_score(p_voted_id);
      PERFORM notify_presence_confirmed(p_voted_id, p_activity_id);
    END IF;
    RETURN;
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.peer_voter_not_present';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  v_threshold := CASE WHEN v_accepted_count = 2 THEN 1 ELSE 2 END;

  IF v_vote_count >= v_threshold THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_flipped = ROW_COUNT;
    IF v_flipped > 0 THEN
      PERFORM recalculate_reliability_score(p_voted_id);
      PERFORM notify_presence_confirmed(p_voted_id, p_activity_id);
    END IF;
  END IF;
END;
$$;
