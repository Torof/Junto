-- Migration 00108: tighten presence model — remove creator override entirely.
-- Trust is now binary:
--   1. Self-validation (geo OR QR) within tight windows = sure / anti-fraud.
--   2. Peer review (24h post-end, threshold 2) = subjective fallback.
--   3. Auto-FALSE at +24h for everyone still NULL.
--
-- Creator no longer has any unilateral override path. Creator votes in peer
-- review like every other accepted participant.
--
-- Geo window:  T-2h → T+duration  (was T+duration+12h — geo only makes sense
--                                  while the activity is happening)
-- QR window:   T-2h → T+duration+1h (1h grace post-end so the creator can
--                                    show the QR for stragglers checking out)

-- ----------------------------------------------------------------------------
-- 1. Drop creator_override_presence — no replacement.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS creator_override_presence(UUID, UUID[]);

-- ----------------------------------------------------------------------------
-- 2. confirm_presence_via_geo — tighter window: T-2h → T+duration only
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_start FLOAT;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Geo window: 2h before start until end of activity.
  IF now() < v_starts_at - INTERVAL '2 hours' OR now() > v_starts_at + v_duration THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    ST_Distance(location_start, v_user_point),
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start, 999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end, 999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations
  SET confirmed_present = TRUE
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. confirm_presence_via_token — window T-2h → T+duration+1h
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION confirm_presence_via_token(
  p_token TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_token_record RECORD;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_activity_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_token_record
  FROM presence_tokens
  WHERE token = p_token;

  IF v_token_record IS NULL OR v_token_record.expires_at < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_activity_id := v_token_record.activity_id;

  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- QR window: 2h before start until 1h after end.
  IF now() < v_starts_at - INTERVAL '2 hours' OR now() > v_starts_at + v_duration + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations
  SET confirmed_present = TRUE
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. peer_validate_presence — remove creator branch, creator = 1 vote like peers
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

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Voter must be confirmed_present (no special creator branch — creator
  -- votes like everyone else).
  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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
-- 5. transition_single_activity — drop the creator-only confirm_presence
--    notification at completion. Creator gets rate_participants like everyone.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, creator_id, title, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_activity IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_user_id != v_activity.creator_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  IF v_activity.status = 'published' AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      PERFORM notify_presence_reminders(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_presence_reminders(p_activity_id);
  END IF;

  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';

    IF FOUND THEN
      -- Single notification path: rate_participants for every accepted user
      -- (creator included). The peer-review page is the single entry point
      -- for both badge votes and peer presence validation.
      FOR v_participant IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
      LOOP
        PERFORM create_notification(
          v_participant.user_id,
          'rate_participants',
          'Évalue tes co-participants',
          'Comment s''est passé ' || v_activity.title || ' ?',
          jsonb_build_object('activity_id', p_activity_id)
        );
      END LOOP;

      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;
