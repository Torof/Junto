-- Migration 00143: collapse the presence notification trio + append count.
--
-- A single activity can produce six or more push notifications between
-- the T-2h pre-warning and the geofence arrival event:
--   - presence_pre_warning   (T-2h)
--   - presence_reminder      (T-30min)
--   - presence_last_call     (T-15min)
--   - presence_confirmed     (after validation, currently muted from push)
--   - background geofence local heartbeat
--   - foreground watcher local arrival notif
--
-- Each push currently spawns its own OS-level alert modal — too noisy.
--
-- This migration collapses the three time-based pushes (pre_warning,
-- reminder, last_call) into a single OS notification slot per activity
-- via collapse_id = 'presence-<activity_id>'. Each new push REPLACES the
-- prior one in the OS tray (Android FCM collapse_key + iOS
-- apns-collapse-id) — user sees one item that updates, with a buzz/sound
-- on each refresh, but no new modal alert.
--
-- The title is also augmented with a count suffix when more than one
-- notif of the trio has fired in the last 24h for that user+activity:
--   "Rappel de présence" → "Rappel de présence (×3)"
-- giving the user a visible signal that this is a recurring update, not
-- a fresh event.
--
-- presence_confirmed stays muted from push (in-app history only — the
-- foreground in-app toast and the background geofence local notif cover
-- the user-facing side already).

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
    WHEN 'rate_participants', 'request_refused', 'participant_left_late',
         'presence_confirmed' THEN
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
