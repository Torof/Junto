-- Migration 00146: drop the stale confirm_presence_via_geo overload + push
-- presence_confirmed for all sources.
--
-- Background:
-- 00141 added confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ) for
-- offline replay, but never dropped the original (UUID, FLOAT, FLOAT) from
-- 00131. CREATE OR REPLACE FUNCTION only replaces an exact-signature match,
-- so both overloads coexisted in the catalog. PostgREST sees ambiguity when
-- the 3-arg body arrives from the live callers (foreground watcher,
-- background geofence task, the on-app-open initial-state check, and
-- reliabilityService.confirmPresenceViaGeo) and the call started failing —
-- which is why auto-validation worked yesterday and stopped today.
--
-- Fix: drop the stale 3-arg overload. Only the 4-arg form (with optional
-- p_captured_at) remains — the live callers continue to work because the
-- new param has DEFAULT NULL.
--
-- Also: presence_confirmed now pushes for all sources, with the same
-- collapse_id 'presence-{activity_id}' as the time-based trio so it folds
-- into the same OS slot. Closes the silent-confirmation gaps for creator
-- auto-validation (when a participant scans creator's QR) and peer
-- threshold flips. The BG geofence path retains its local "Présence
-- confirmée" notif on top — minor duplicate is acceptable; the FCM push
-- and the local notif live in different OS slots either way.

DROP FUNCTION IF EXISTS confirm_presence_via_geo(UUID, FLOAT, FLOAT);

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

    WHEN 'presence_pre_warning', 'presence_reminder', 'presence_last_call' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
        SELECT count(*) INTO v_presence_count
        FROM notifications
        WHERE user_id = NEW.user_id
          AND type IN ('presence_pre_warning', 'presence_reminder', 'presence_last_call')
          AND (data->>'activity_id') = v_activity_id
          AND created_at > NOW() - INTERVAL '24 hours';
        IF v_presence_count > 1 THEN
          v_title := v_title || ' (×' || v_presence_count || ')';
        END IF;
      END IF;

    WHEN 'presence_confirmed' THEN
      -- Same OS slot as the time-based trio — confirmation replaces any
      -- prior reminder. Single-shot per user/activity (DB unique index)
      -- so no count needed.
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
