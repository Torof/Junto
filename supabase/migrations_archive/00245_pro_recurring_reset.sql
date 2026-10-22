-- Migration 00245: Pro feature Phase 3a — recurring-activity reset cron
-- + peer-validation / reputation-vote gates.
--
-- Scott's model for recurring activities: a single activities row that
-- persists across occurrences. When the activity ends and the
-- peer-review window closes (T+duration+24h), the row "resets":
--   - participations / wall_messages / seat_requests / activity_gear
--     for this activity are deleted (per-occurrence ephemera)
--   - starts_at advances by recurrence_days
--   - status flips 'completed' → 'published'
-- Photos and reviews live in separate tables and persist across
-- resets — they accumulate over the life of the recurring activity.
--
-- Per Scott's design: recurring pro activities don't participate in
-- peer-validation or reputation-voting. Reviews on the pro page +
-- per-activity reviews (Phase 4) replace both. peer_validate_presence
-- and give_reputation_badge gain an explicit refusal when the target
-- activity is is_recurring=TRUE.

-- ============================================================================
-- reset_completed_recurring_activities — hourly cron.
-- Returns the count of activities reset for observability.
-- ============================================================================
CREATE OR REPLACE FUNCTION reset_completed_recurring_activities()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_count INTEGER := 0;
BEGIN
  -- Loop over recurring activities whose peer-review window has
  -- closed (T+duration+24h). The peer-review window is moot here
  -- since recurring activities are gated out of peer_validate anyway,
  -- but the 24h grace gives time for any late presence / display
  -- queries to settle before we wipe the ephemera.
  FOR v_activity IN
    SELECT id, recurrence_days, starts_at, duration
    FROM activities
    WHERE is_recurring = TRUE
      AND status = 'completed'
      AND deleted_at IS NULL
      AND starts_at + duration + INTERVAL '24 hours' < NOW()
      AND recurrence_days IS NOT NULL
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Clear per-occurrence ephemera. Reviews + photos live in
    -- separate tables and are NOT touched here.
    DELETE FROM participations WHERE activity_id = v_activity.id;
    DELETE FROM wall_messages WHERE activity_id = v_activity.id;
    DELETE FROM seat_requests WHERE activity_id = v_activity.id;
    DELETE FROM activity_gear WHERE activity_id = v_activity.id;

    -- Advance the date by one recurrence_days unit. If the new
    -- starts_at is still in the past (cron missed multiple
    -- occurrences), the next cron iteration catches it.
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE activities
    SET starts_at = starts_at + (v_activity.recurrence_days * INTERVAL '1 day'),
        status = 'published'
    WHERE id = v_activity.id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Cron-only: no anon / authenticated grant. Scheduled invocation uses
-- the supabase_admin / postgres role per pg_cron.
REVOKE EXECUTE ON FUNCTION reset_completed_recurring_activities FROM anon, authenticated;

-- ============================================================================
-- Schedule — hourly. Mirrors the 00016 transition_activity_status pattern:
-- only register the job when pg_cron is available on this plan.
-- ============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('reset-recurring-activities')
      WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'reset-recurring-activities'
      );
    PERFORM cron.schedule(
      'reset-recurring-activities',
      '0 * * * *',
      'SELECT reset_completed_recurring_activities()'
    );
  END IF;
END $$;

-- ============================================================================
-- peer_validate_presence — refuse when the activity is recurring.
-- Reviews replace peer-validation for recurring activities.
-- Body otherwise identical to 00237.
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

  SELECT id, creator_id, status, starts_at, duration, requires_presence, is_recurring
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL
     OR v_activity.status != 'completed'
     OR v_activity.requires_presence IS NOT TRUE
     OR v_activity.is_recurring = TRUE THEN
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
    RAISE EXCEPTION 'peer_voter_not_present';
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

REVOKE EXECUTE ON FUNCTION peer_validate_presence FROM anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence TO authenticated;

-- ============================================================================
-- give_reputation_badge — refuse when the activity is recurring.
-- Body otherwise identical to 00237.
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
  v_recent_count INTEGER;
  v_valid_keys TEXT[] := ARRAY[
    'punctual', 'prepared', 'conciliant', 'prudent',
    'unprepared', 'aggressive', 'reckless',
    'level_over', 'level_right'
  ];
  v_level_keys TEXT[] := ARRAY['level_over', 'level_right'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_voted_id)
       OR (blocker_id = p_voted_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('reputation_vote:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM reputation_votes
  WHERE voter_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_recent_count >= 20 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, duration, is_recurring INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL
     OR v_activity.status != 'completed'
     OR v_activity.is_recurring = TRUE THEN
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
