-- Migration 00236: Medium-tier audit fixes (M1, M2, M5).
--
-- M1: give_reputation_badge (00159) had no bidirectional blocked-users
--     guard — blocked users could still vote on each other for completed
--     activities. Add the standard pattern from request_seat (00215).
--
-- M2: get_user_reputation (00154) and get_user_trophies (00134) are
--     SECURITY DEFINER read-only RPCs with NO auth.uid() check and NO
--     suspension check. A suspended user can still query reputation
--     data — inconsistent with the documented auth-chain baseline.
--     Add the auth + suspension prelude (matching 00226's pattern).
--
-- M5: push_notification_to_device (00162) forwards COALESCE(NEW.data,
--     '{}'::jsonb) raw to the send-push edge function. Today's payloads
--     carry only IDs, but a future migration that adds lat/lng or
--     message snippets to a notification's `data` would surface them
--     on the device lock screen. Constrain to an allow-list of known
--     ID-only keys before forwarding; everything else stays in the
--     `notifications` row for in-app rendering.

-- ============================================================================
-- M1 — give_reputation_badge with bidirectional block guard
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

  -- Bidirectional block guard. Mirrors the pattern from request_seat
  -- (00215) / send_contact_request (00072). Blocked pairs can't vote
  -- on each other regardless of which side blocked the other.
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_voted_id)
       OR (blocker_id = p_voted_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
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

-- ============================================================================
-- M2 — get_user_reputation: auth + suspension prelude
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_reputation(
  p_user_id UUID
)
RETURNS TABLE (
  badge_key TEXT,
  vote_count INTEGER,
  last_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_negative_keys TEXT[] := ARRAY[
    'unprepared', 'aggressive', 'reckless',
    'late_canceller', 'level_overestimated', 'unreliable_field', 'difficult_attitude'
  ];
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH grouped AS (
    SELECT
      rv.badge_key,
      count(*)::int AS total_count,
      max(rv.created_at) AS max_at
    FROM reputation_votes rv
    WHERE rv.voted_id = p_user_id
      AND rv.badge_key NOT IN ('level_over', 'level_right', 'level_under')
    GROUP BY rv.badge_key
  )
  SELECT
    g.badge_key,
    CASE
      WHEN g.badge_key = ANY(v_negative_keys)
        THEN get_active_negative_count(p_user_id, g.badge_key)
      ELSE g.total_count
    END AS vote_count,
    g.max_at AS last_at
  FROM grouped g
  WHERE
    NOT (
      g.badge_key = ANY(v_negative_keys)
      AND get_active_negative_count(p_user_id, g.badge_key) = 0
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_reputation FROM anon;
GRANT EXECUTE ON FUNCTION get_user_reputation TO authenticated;

-- ============================================================================
-- M2 — get_user_trophies: auth + suspension prelude
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_trophies(
  p_user_id UUID
)
RETURNS TABLE (
  category TEXT,
  sport_key TEXT,
  count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 'joined'::text, NULL::text,
    (SELECT count(*)::int
     FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND a.status = 'completed'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL)
  UNION ALL
  SELECT 'created'::text, NULL::text,
    (SELECT count(*)::int
     FROM activities
     WHERE creator_id = p_user_id
       AND status = 'completed'
       AND deleted_at IS NULL)
  UNION ALL
  SELECT 'sport'::text, s.key::text, count(*)::int
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND a.status = 'completed'
    AND a.deleted_at IS NULL
  GROUP BY s.key
  HAVING count(*) > 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_trophies FROM anon;
GRANT EXECUTE ON FUNCTION get_user_trophies TO authenticated;

-- ============================================================================
-- M5 — push_notification_to_device: allow-list on forwarded data payload
-- ============================================================================
-- Same body as 00162 but the `data` field passed to send-push is now
-- explicitly limited to known ID-only routing keys. Any value present
-- in `NEW.data` but not in the allow-list stays in the notifications
-- row (for in-app rendering) and never reaches the device push payload.
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
  v_activity_id TEXT;
  v_presence_count INT;
  v_title TEXT := NEW.title;
  v_forwarded_data JSONB;
  v_allowed_keys TEXT[] := ARRAY[
    'activity_id',
    'conversation_id',
    'seat_request_id',
    'driver_id',
    'requester_id',
    'from_user_id'
  ];
BEGIN
  IF (NEW.data ? 'skip_push') AND ((NEW.data->>'skip_push')::boolean IS TRUE) THEN
    RETURN NEW;
  END IF;

  CASE NEW.type
    WHEN 'rate_participants', 'request_refused' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

    WHEN 'badge_unlocked' THEN
      v_collapse_id := 'badge-' || NEW.user_id::text
                       || '-' || to_char(NEW.created_at, 'YYYY-MM-DD');

    WHEN 'presence_pre_warning', 'presence_validate_now', 'presence_validate_warning' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
        SELECT count(*) INTO v_presence_count
        FROM notifications
        WHERE user_id = NEW.user_id
          AND type IN ('presence_pre_warning', 'presence_validate_now', 'presence_validate_warning')
          AND (data->>'activity_id') = v_activity_id
          AND created_at > NOW() - INTERVAL '24 hours';
        IF v_presence_count > 1 THEN
          v_title := v_title || ' (×' || v_presence_count || ')';
        END IF;
      END IF;

    WHEN 'presence_confirmed' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
      END IF;

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
        OR v_changes ? 'max_participants' OR v_changes ? 'level'
      );

    ELSE
      v_should_push := TRUE;
  END CASE;

  IF NOT v_should_push THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;

  -- Strict allow-list — anything not in v_allowed_keys is dropped
  -- before the payload leaves the DB. `type` is always added (the
  -- client routes on it).
  SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb)
    INTO v_forwarded_data
  FROM jsonb_each(COALESCE(NEW.data, '{}'::jsonb))
  WHERE key = ANY(v_allowed_keys);

  v_forwarded_data := v_forwarded_data || jsonb_build_object('type', NEW.type);

  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', v_title,
      'body', NEW.body,
      'data', v_forwarded_data,
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
END;
$$;
