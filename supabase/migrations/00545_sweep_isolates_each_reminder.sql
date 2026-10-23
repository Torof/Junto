-- The minute sweep no longer loses every status transition when one reminder
-- breaks (lot B2 of the 2026-10-23 sweep): each notify_* call and the presence
-- finalisation are isolated, like check_activity_transitions already isolates
-- its three steps.

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
