-- Migration 00327: rework the peer-presence model (Scott 2026-07-13)
--
-- Old model deadlocked: a peer witness had to already be confirmed present, so
-- if nobody used QR/geo the whole group was stuck. New model:
--   * Peer testimony ONLY at 3+ accepted participants (at 2 it's QR/geo only —
--     one friend attesting for another is too easy to fake).
--   * A participant is confirmed present when >= 2 OTHER accepted participants
--     vouch for them. The voter must be an accepted participant but need NOT be
--     pre-verified present — the anti-fraud is that self-vote is blocked and the
--     honest attendees simply won't vouch for a no-show. Full-group collusion is
--     the only residual gap (low incentive, reportable).
-- Removed: the "voter must be present" gate AND the creator direct-flip at 2
-- participants (single-attester fraud vector). QR/geo (confirm_presence) is
-- unchanged and remains the fast, physical-proof path for any group size.

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
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
  v_accepted_count INTEGER;
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

  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.peer_review_no_presence';
  END IF;
  IF v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'junto.peer_review_not_completed';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.peer_review_window_not_open';
  END IF;
  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.peer_review_window_closed';
  END IF;

  -- Target must be an accepted participant and not already confirmed.
  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;

  IF v_voted_status IS NULL OR v_voted_status != 'accepted' THEN
    RAISE EXCEPTION 'junto.peer_review_target_not_in';
  END IF;
  IF v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.peer_already_validated';
  END IF;

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Peer testimony only from 3 participants up. At 2, QR/geo is the only path.
  IF v_accepted_count < 3 THEN
    RAISE EXCEPTION 'junto.peer_review_unavailable';
  END IF;

  -- Voter must be an accepted participant (need NOT be pre-verified present).
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  -- 2 distinct co-participants confirm presence.
  IF v_vote_count >= 2 THEN
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
