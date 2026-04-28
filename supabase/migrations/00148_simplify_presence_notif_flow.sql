-- Migration 00148: simplify the presence notification flow.
--
-- The agreed-on participant-facing notifications for an activity that
-- requires presence are:
--
--   T-2h                 presence_pre_warning      "starts in less than 2h"
--   T0  (in_progress)    presence_validate_now     "Valide ta présence"
--   T + duration/2       presence_validate_warning "Attention — valide ta présence
--                                                   sinon tu seras enregistré comme absent"
--   on validation        presence_confirmed        (server-side; pushes after 00146)
--   activity end         rate_participants
--   T+22h after end      peer_review_closing
--
-- Plus the OS-local "Présence détectée" → "Présence confirmée" notif owned
-- by the background geofence task, and qr_create_reminder fired only to the
-- creator at activity start.
--
-- This migration:
--   1. Drops notify_presence_reminders and notify_presence_last_call —
--      both are replaced by the two new notifs below. The reminder fired
--      during in_progress (no specific time anchor) and last_call fired
--      after the activity completed; both were intermediate signals between
--      pre_warning and peer_review and don't fit the tightened flow.
--   2. Adds notify_presence_validate_now (T0) and
--      notify_presence_validate_warning (T + duration/2). Both are
--      idempotent — single-shot per user+activity via NOT EXISTS dedup, and
--      filter on confirmed_present IS NULL so a validated user gets
--      nothing further.
--   3. Updates transition_statuses_only so the cron sweep emits the new
--      notifs and stops emitting the old ones.
--   4. Extends push_notification_to_device so the new types share the
--      'presence-{activity_id}' collapse slot and the (×N) count
--      progression with presence_pre_warning and presence_confirmed.

-- ============================================================================
-- 1. Drop the deprecated reminder + last_call functions
-- ============================================================================
DROP FUNCTION IF EXISTS notify_presence_reminders(UUID);
DROP FUNCTION IF EXISTS notify_presence_last_call(UUID);

-- ============================================================================
-- 2. New: notify_presence_validate_now (T0 — activity just started)
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_validate_now(
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
  SELECT id, title, status, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_now'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_now',
        'Valide ta présence',
        v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_validate_now FROM anon, authenticated;

-- ============================================================================
-- 3. New: notify_presence_validate_warning (T + duration/2)
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_validate_warning(
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
  SELECT id, title, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  -- Fire only once we're past the midpoint and still before activity end.
  IF now() < v_activity.starts_at + (v_activity.duration / 2) THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_warning',
        'Attention — valide ta présence',
        'Sinon tu seras enregistré comme absent à ' || v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_validate_warning FROM anon, authenticated;

-- ============================================================================
-- 4. transition_statuses_only — emit the two new notifs, drop old ones
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_statuses_only()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();

  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now();

  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  -- Pre-warning sweep: published activities with start within the next 2h.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'published'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND a.starts_at - INTERVAL '2 hours' <= now()
      AND a.starts_at > now()
  LOOP
    PERFORM notify_presence_pre_warning(v_activity_id);
  END LOOP;

  -- Validate-now + warning sweep: in_progress activities. The functions
  -- themselves enforce the timing relative to starts_at and duration.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    PERFORM notify_presence_validate_now(v_activity_id);
    PERFORM notify_presence_validate_warning(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  -- Peer-review-closing sweep at T+22h..T+24h after end.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '22 hours'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_peer_review_closing(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_statuses_only TO postgres;

-- ============================================================================
-- 5. push_notification_to_device — fold new types into the presence slot
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
  v_activity_id TEXT;
  v_presence_count INT;
  v_title TEXT := NEW.title;
BEGIN
  CASE NEW.type
    WHEN 'rate_participants', 'request_refused', 'participant_left_late' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

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
      'title', v_title,
      'body', NEW.body,
      'data', COALESCE(NEW.data, '{}'::jsonb) || jsonb_build_object('type', NEW.type),
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
END;
$$;
