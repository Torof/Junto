-- Migration 00136: emit 'rate_participants' from the activity-completion trigger.
-- The cron sweep (transition_statuses_only) flips activities to 'completed'
-- via a bulk UPDATE without firing any per-row notifications. The lazy
-- transition_single_activity path emitted 'rate_participants' itself, but
-- only ran when a user opened the activity — so cron-completed activities
-- never produced the notification, and the peer-review window started
-- silently.
--
-- This migration moves the emission into the trigger that already runs
-- on every status flip to 'completed' (the badge-award trigger from 00135),
-- and removes the duplicate emission from transition_single_activity to
-- avoid double-firing.

-- ============================================================================
-- 1. Extend the on-completed trigger function: badges + rate_participants
-- ============================================================================
CREATE OR REPLACE FUNCTION on_activity_completed_award_badges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_participant RECORD;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted'
    LOOP
      -- Badge progression (joined / created / sport tiers + level-up notif)
      PERFORM award_badge_progression(v_participant.user_id, FALSE);

      -- Peer review prompt — opens the rating window for everyone present
      PERFORM create_notification(
        v_participant.user_id,
        'rate_participants',
        'Évalue tes co-participants',
        'Comment s''est passé ' || NEW.title || ' ?',
        jsonb_build_object('activity_id', NEW.id)
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION on_activity_completed_award_badges FROM anon, authenticated;

-- ============================================================================
-- 2. transition_single_activity — drop the duplicate emission; trigger covers it
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress', 'completed') THEN
    RETURN v_activity.status;
  END IF;

  IF v_activity.status = 'published'
     AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id
          AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      PERFORM notify_presence_reminders(p_activity_id);
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_presence_reminders(p_activity_id);
    PERFORM notify_creator_qr_reminder(p_activity_id);
  END IF;

  -- in_progress → completed: just flip the status. The AFTER UPDATE
  -- trigger on activities (on_activity_completed_award_badges) handles
  -- badge progression and rate_participants notifications.
  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';
    IF FOUND THEN
      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;
