-- Migration 00139: peer_validate_presence — restore creator branch + differentiated errors.
--
-- Migration 00131 rewrote peer_validate_presence to emit presence_confirmed
-- notifications but accidentally dropped the creator-bypass branch from
-- migration 00106. Effect: a creator who forgot to scan/geo-validate
-- themselves cannot validate other participants either, even though that
-- branch was specifically introduced to break the chicken-and-egg.
--
-- This migration:
--   1. Restores the creator branch (direct flip, no self-presence
--      requirement, no threshold) — windows still apply.
--   2. Differentiates the constraints the peer-review UI can act on, so the
--      client can show a useful reason instead of a generic message:
--        - peer_review_window_not_open   (before T+15min)
--        - peer_review_window_closed     (after T+24h)
--        - peer_voter_not_present        (peer path — voter isn't confirmed)
--        - peer_already_validated        (target already has presence set)
--      Security-sensitive checks (auth, suspended, self-vote, target
--      not-in-activity, activity not eligible) keep "Operation not permitted".

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

  SELECT id, creator_id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'peer_review_window_not_open';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'peer_review_window_closed';
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
    RAISE EXCEPTION 'peer_already_validated';
  END IF;

  IF v_is_creator THEN
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
    RAISE EXCEPTION 'peer_voter_not_present';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  v_threshold := CASE WHEN v_accepted_count <= 3 THEN 1 ELSE 2 END;

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

REVOKE EXECUTE ON FUNCTION peer_validate_presence FROM anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence TO authenticated;
