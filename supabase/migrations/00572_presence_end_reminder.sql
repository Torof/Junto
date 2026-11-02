-- Multi-day outings between enthusiasts (Scott 2026-11-02): the organiser's
-- QR already works from T-15 min to end + 3 h, so it can be scanned at the
-- start, during the outing (a hut with signal) or after it. For a long outing
-- (>= 12 h) a reminder now goes out in the last hour, if presence is still
-- not validated:
--   - each accepted participant without a validated presence (creator
--     excluded, Rule B) — « valide ta présence » ;
--   - the organiser, when at least one participant still needs it —
--     « affiche ton QR ».
-- Same gates as the other presence emitters (requires_presence, >= 2
-- accepted); one notification per person and outing.

CREATE OR REPLACE FUNCTION public.notify_presence_end_reminder(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_missing INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity.id IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status <> 'in_progress' THEN RETURN; END IF;
  IF v_activity.duration < INTERVAL '12 hours' THEN RETURN; END IF;
  IF now() < v_activity.starts_at + v_activity.duration - INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_missing
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
    AND p.confirmed_present IS NULL AND p.user_id <> v_activity.creator_id;
  IF v_missing = 0 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id FROM participations p
    WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
      AND p.confirmed_present IS NULL AND p.user_id <> v_activity.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id AND n.type = 'presence_end_reminder'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_end_reminder',
        'Fin de sortie : valide ta présence',
        'Scanne le QR de l''organisateur — valable jusqu''à 3 h après la fin de « ' || v_activity.title || ' ».',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.user_id = v_activity.creator_id AND n.type = 'presence_end_reminder'
      AND (n.data->>'activity_id')::uuid = p_activity_id
  ) THEN
    BEGIN
      PERFORM create_notification(
        v_activity.creator_id,
        'presence_end_reminder',
        'Fin de sortie : affiche ton QR',
        v_missing || CASE WHEN v_missing > 1 THEN ' participants n''ont' ELSE ' participant n''a' END
          || ' pas encore validé sa présence sur « ' || v_activity.title || ' ».',
        jsonb_build_object('activity_id', p_activity_id, 'variant', 'creator',
          'params', jsonb_build_object('title', v_activity.title, 'count', v_missing))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_presence_end_reminder(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.transition_statuses_only()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_activity_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  -- 00545: each reminder and the presence finalisation run in their own
  -- sub-block — a runtime break in one of them (renamed column, dropped
  -- function: the 00419 class) no longer rolls back every status transition
  -- while the scheduled job still reports success.

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();

  -- Solo end-of-window: nobody (besides the creator) ever joined → the
  -- outing didn't happen. Must run BEFORE the completed update.
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

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

  -- Pre-event sweep: published activities approaching start. All three
  -- emitters gate internally on their respective time windows (pre_warning
  -- T-2h..T0, pre_warning_10min T-10..T0, qr_reminder T-10..T0 creator-only).
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
    BEGIN PERFORM notify_presence_pre_warning(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_presence_pre_warning: %', SQLERRM; END;
    BEGIN PERFORM notify_presence_pre_warning_10min(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_presence_pre_warning_10min: %', SQLERRM; END;
    BEGIN PERFORM notify_creator_qr_reminder(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_creator_qr_reminder: %', SQLERRM; END;
  END LOOP;

  -- During-event sweep: in_progress activities. validate_warning gates on
  -- T+duration/2 internally. (qr_create_reminder no longer called here —
  -- moved to the published sweep at T-10min.)
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    BEGIN PERFORM notify_presence_validate_warning(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_presence_validate_warning: %', SQLERRM; END;
    -- 00572: long outings (>= 12 h) — reminder around the end.
    BEGIN PERFORM notify_presence_end_reminder(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_presence_end_reminder: %', SQLERRM; END;
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
    BEGIN PERFORM notify_presence_validate_overdue(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_presence_validate_overdue: %', SQLERRM; END;
  END LOOP;

  -- 00427: rate_participants only once the vote window is actually OPEN
  -- (end+15min) — the completion trigger no longer emits it at the flip,
  -- where tapping the notification guaranteed a "too early" refusal.
  -- No requires_presence gate: trait/level votes apply to every outing
  -- with >=2 accepted participants. notify_* gates + dedups internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '15 minutes'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    BEGIN PERFORM notify_rate_participants(v_activity_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_rate_participants: %', SQLERRM; END;
  END LOOP;

  BEGIN PERFORM close_due_presence_windows();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close_due_presence_windows: %', SQLERRM; END;
END;
$function$;
