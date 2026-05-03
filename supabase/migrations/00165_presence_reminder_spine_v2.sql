-- Migration 00165: presence reminder spine v2.
--
-- Pivot to a simpler, escalating spine:
--
--   T-2h                       presence_pre_warning           (informational, all participants)
--   T-10min                    presence_pre_warning_10min     (CTA, only unconfirmed)  [NEW]
--   T + duration/2             presence_validate_warning      (CTA, only unconfirmed)  (existing)
--   T + duration + 1h          presence_validate_overdue      (CTA, only unconfirmed)  [NEW]
--
-- Drops the call to notify_presence_validate_now (T0). The new T-10min
-- reminder lands close enough that the immediate-after-start nudge was
-- noise. Function definition stays for backward compat with existing
-- notification rows; no caller emits new ones going forward.
--
-- Auto-validation (geofence task, foreground service when app open,
-- foreground watcher, initial-state check, QR scan) and peer review are
-- unchanged — Scott confirmed they're strong enough as the validation
-- mechanism. This spine is purely the user-facing reminder ladder.

-- ============================================================================
-- 1. NEW: notify_presence_pre_warning_10min (T-10min..T-0)
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_pre_warning_10min(
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
  SELECT id, title, status, starts_at, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  -- Fire only inside the 10-minute pre-window. After T0 the existing
  -- in_progress emitters take over.
  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning_10min'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning_10min',
        v_activity.title,
        'Démarre dans 10 min — pense à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_pre_warning_10min FROM anon, authenticated;

-- ============================================================================
-- 2. NEW: notify_presence_validate_overdue (T + duration + 1h .. + 1h30)
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_validate_overdue(
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
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  -- Fire 1h after the activity ended, with a 30-min cron-sweep cushion.
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_overdue'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_overdue',
        v_activity.title,
        'Tu es enregistré comme absent. Demande à tes co-participants de te valider si tu étais bien là.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_validate_overdue FROM anon, authenticated;

-- ============================================================================
-- 3. transition_statuses_only — call new emitters, drop validate_now call
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

  -- Pre-event sweep: published activities approaching start. Both pre-warning
  -- emitters gate internally on their respective time windows.
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
    PERFORM notify_presence_pre_warning_10min(v_activity_id);
  END LOOP;

  -- During-event sweep: in_progress activities. validate_warning gates on
  -- T+duration/2 internally. validate_now (T0) is no longer called — the
  -- T-10min reminder + the T+duration/2 warning cover the same need with
  -- less noise.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    PERFORM notify_presence_validate_warning(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  -- Post-event sweep: completed activities. validate_overdue at T+1h after
  -- end, peer_review_closing at T+22h. Each gates internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '1 hour'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_presence_validate_overdue(v_activity_id);
    PERFORM notify_peer_review_closing(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_statuses_only TO postgres;

-- ============================================================================
-- 4. push_notification_to_device — fold new types into the presence collapse
-- ============================================================================
-- Recreated verbatim from mig 00162 with two type strings added to the
-- presence collapse arm and the count subquery's IN list.
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

    WHEN 'presence_pre_warning', 'presence_pre_warning_10min',
         'presence_validate_now', 'presence_validate_warning',
         'presence_validate_overdue' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
        SELECT count(*) INTO v_presence_count
        FROM notifications
        WHERE user_id = NEW.user_id
          AND type IN ('presence_pre_warning', 'presence_pre_warning_10min',
                       'presence_validate_now', 'presence_validate_warning',
                       'presence_validate_overdue')
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
