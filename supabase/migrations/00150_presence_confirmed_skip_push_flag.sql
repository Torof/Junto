-- Migration 00150: skip-push flag for presence_confirmed when client owns the
-- visible signal.
--
-- Context: the BG geofence task and the offline replay flusher both pose a
-- local Expo notification ("Présence confirmée") on RPC success. The
-- server-side notify_presence_confirmed also creates a row that pushes via
-- FCM (added in mig 00146). On Android these end up in two distinct OS
-- notification slots — Expo's identifier maps to NotificationCompat id, FCM
-- collapse_key maps to the tag, so (id, tag) tuples differ and the slots
-- coexist. Result: the user sees two "Présence confirmée" notifs for the
-- same validation event.
--
-- Fix: the client paths that already fire a local notif pass a new
-- p_skip_push flag through confirm_presence_via_geo, which is forwarded to
-- notify_presence_confirmed and embedded in the notification's data
-- payload as `skip_push: true`. The push_notification_to_device trigger
-- checks this flag and skips the FCM dispatch for that specific row.
--
-- Paths that DON'T have a local notif (FG watcher, activity-detail page
-- poll, app-open initial check, manual button, QR scan, peer validation,
-- creator auto-validation via QR) leave skip_push at its FALSE default →
-- FCM push fires normally.
--
-- Net result: exactly one OS notification slot per validation event,
-- regardless of which path produced it.

-- ============================================================================
-- 1. notify_presence_confirmed — accept p_skip_push, embed in data
-- ============================================================================
-- The old 2-arg signature must be dropped explicitly; CREATE OR REPLACE on a
-- different signature creates a new overload alongside the old one.
DROP FUNCTION IF EXISTS notify_presence_confirmed(UUID, UUID);

CREATE OR REPLACE FUNCTION notify_presence_confirmed(
  p_user_id UUID,
  p_activity_id UUID,
  p_skip_push BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title TEXT;
  v_data JSONB;
BEGIN
  SELECT title INTO v_title FROM activities WHERE id = p_activity_id;
  IF v_title IS NULL THEN RETURN; END IF;

  v_data := jsonb_build_object('activity_id', p_activity_id);
  IF p_skip_push THEN
    v_data := v_data || jsonb_build_object('skip_push', TRUE);
  END IF;

  BEGIN
    PERFORM create_notification(
      p_user_id,
      'presence_confirmed',
      'Présence confirmée',
      'Ta présence est validée pour ' || v_title,
      v_data
    );
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_confirmed FROM anon, authenticated;

-- ============================================================================
-- 2. confirm_presence_via_geo — accept p_skip_push, forward to notify
-- ============================================================================
CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT,
  p_captured_at TIMESTAMPTZ DEFAULT NULL,
  p_skip_push BOOLEAN DEFAULT FALSE
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
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_window_anchor TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    IF now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
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
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start,   999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id, p_skip_push);
END;
$$;

-- The 4-arg overload (without p_skip_push) is replaced because adding a
-- default parameter creates a different signature. Drop it explicitly so
-- PostgREST has only one matching function.
DROP FUNCTION IF EXISTS confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ);

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ, BOOLEAN) TO authenticated;

-- ============================================================================
-- 3. push_notification_to_device — honor skip_push flag in data payload
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
  -- Client-driven mute: if a notif row carries skip_push=true in its data
  -- payload, the visible signal has already been fired locally on-device
  -- (BG geofence task or offline flusher). Skip the FCM push to avoid the
  -- two-OS-slots leak.
  IF (NEW.data ? 'skip_push') AND ((NEW.data->>'skip_push')::boolean IS TRUE) THEN
    RETURN NEW;
  END IF;

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
