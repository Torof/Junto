-- ============================================================================
-- 00475 — Audit octobre 2026, L9 (décision Scott 2026-10-21 : « ça me va ») :
-- remplacer ou retirer la trace d'une sortie notifie les participants acceptés
-- (type activity_updated, variante `trace`, push comme un changement d'heure).
-- Base = update_activity_trace 00474 et push_notification_to_device 00472.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_old_trace JSONB;
  v_title TEXT;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND creator_id = v_user_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): same gate as create_activity.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  SELECT trace_geojson, title INTO v_old_trace, v_title FROM activities WHERE id = p_activity_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson,
      distance_km = CASE
        WHEN p_trace_geojson IS NOT NULL AND distance_km IS NULL
          THEN (SELECT CASE WHEN round(d, 1) > 0 AND d <= 9999 THEN d END FROM (SELECT trace_distance_km(p_trace_geojson) AS d) x)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN (SELECT CASE WHEN g > 0 AND g <= 99999 THEN g END FROM (SELECT trace_elevation_gain_m(p_trace_geojson) AS g) x)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  -- 00475 (audit L9, Scott 2026-10-21): the route is part of what people
  -- signed up for — a changed trace notifies the accepted participants, like
  -- an hour or meeting-point change does in update_activity.
  IF v_old_trace IS DISTINCT FROM p_trace_geojson THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_updated',
        'Itinéraire modifié',
        '« ' || v_title || ' » a un nouvel itinéraire — jette un œil à la trace.',
        jsonb_build_object('activity_id', p_activity_id,
          'changes', jsonb_build_object('trace', true),
          'variant', 'trace',
          'params', jsonb_build_object('title', v_title))
      );
    END LOOP;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.push_notification_to_device()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
    'from_user_id',
    -- 00472 (audit M7): send-push composes the text in the recipient's
    -- language from these (lots A-F, 00447-00450). Display names, titles,
    -- dates only — the same facts the French body already carries.
    'params',
    'variant'
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
        OR v_changes ? 'location_meeting'
        OR v_changes ? 'max_participants' OR v_changes ? 'level'
        OR v_changes ? 'trace'  -- 00475: route changed after sign-up
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
$function$;
