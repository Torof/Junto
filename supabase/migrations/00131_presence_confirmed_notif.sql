-- Migration 00131: in-app notification on every presence validation event.
-- Emits a 'presence_confirmed' row whenever a user's confirmed_present
-- transitions NULL → TRUE through any of the four paths:
--   1. confirm_presence_via_geo (self, geo)
--   2. confirm_presence_via_token (self, QR scan)
--   3. confirm_presence_via_token (creator auto-validated by a participant's scan)
--   4. peer_validate_presence (voted user reaches the threshold)
--
-- Push routing keeps this DB-only for now (the user is foreground in the
-- self paths and sees the toast; the auto/peer paths happen quickly enough
-- that a push isn't urgent yet). When background geofencing ships, remove
-- 'presence_confirmed' from the DB-only branch in push_notification_to_device.

-- ============================================================================
-- 1. Trigger routing — keep presence_confirmed off push for now
-- ============================================================================
CREATE OR REPLACE FUNCTION push_notification_to_device()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_should_push BOOLEAN := TRUE;
  v_collapse_id TEXT;
  v_activity_starts TIMESTAMPTZ;
  v_changes JSONB;
  v_secret TEXT;
BEGIN
  CASE NEW.type
    WHEN 'rate_participants', 'request_refused', 'participant_left_late', 'presence_confirmed' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

    WHEN 'activity_cancelled' THEN
      SELECT starts_at INTO v_activity_starts
      FROM activities WHERE id = (NEW.data->>'activity_id')::uuid;
      v_should_push := v_activity_starts IS NULL
                       OR (v_activity_starts - now() < INTERVAL '48 hours');

    WHEN 'activity_updated' THEN
      v_changes := NEW.data->'changes';
      v_should_push := v_changes IS NOT NULL AND (
        v_changes ? 'starts_at' OR v_changes ? 'duration'
        OR v_changes ? 'location_meeting' OR v_changes ? 'location_start'
      );

    ELSE
      v_should_push := TRUE;
  END CASE;

  IF NOT v_should_push THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;

  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body,
      'data', COALESCE(NEW.data, '{}'::jsonb) || jsonb_build_object('type', NEW.type),
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. Helper: emit a presence_confirmed notif (idempotent — partial unique
--    index dedupes if the same path fires twice in quick succession).
-- ============================================================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_notif_presence_confirmed_dedup
ON notifications (user_id, type, ((data->>'activity_id')))
WHERE type = 'presence_confirmed';

CREATE OR REPLACE FUNCTION notify_presence_confirmed(
  p_user_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title TEXT;
BEGIN
  SELECT title INTO v_title FROM activities WHERE id = p_activity_id;
  IF v_title IS NULL THEN RETURN; END IF;

  BEGIN
    PERFORM create_notification(
      p_user_id,
      'presence_confirmed',
      'Présence confirmée',
      'Ta présence est validée pour ' || v_title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_confirmed FROM anon, authenticated;

-- ============================================================================
-- 3. confirm_presence_via_geo — emit on successful flip
-- ============================================================================
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at INTO v_starts_at
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '10 minutes' OR now() > v_starts_at + INTERVAL '30 minutes' THEN
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

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;

-- ============================================================================
-- 4. confirm_presence_via_token — emit for self + for creator (auto-validate)
-- ============================================================================
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
  v_creator_id UUID;
  v_creator_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_token_record
  FROM presence_tokens WHERE token = p_token;
  IF v_token_record IS NULL OR v_token_record.expires_at < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_activity_id := v_token_record.activity_id;

  SELECT starts_at, duration, creator_id INTO v_starts_at, v_duration, v_creator_id
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '30 minutes' OR now() > v_starts_at + v_duration + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, v_activity_id);

  -- Non-creator scanning the QR proves the creator is on-site.
  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = v_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, v_activity_id);
    END IF;
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;

-- ============================================================================
-- 5. peer_validate_presence — emit when threshold flips voted user
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

  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
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
