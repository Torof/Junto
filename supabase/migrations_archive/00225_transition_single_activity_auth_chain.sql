-- Migration 00225: transition_single_activity gets the standard auth +
-- suspension chain. From the parallel security audit MINOR list.
--
-- The function is called from the activity-detail screen as a passive
-- time-cleanup (lazy "roll status forward if the wall clock has passed
-- the boundary"). Before this migration it had no auth.uid() / suspension
-- check at all — a suspended user opening any activity URL still
-- triggered transitions (and therefore notify_presence_reminders +
-- notify_creator_qr_reminder fan-outs to other participants).
--
-- The downstream notify functions are already idempotent (NOT EXISTS
-- guards on the notifications table) and REVOKE EXECUTE from
-- authenticated, so the spam ceiling is bounded — but a suspended user
-- shouldn't be the one driving them.
--
-- Note: NO membership-or-creator gate. The function is intentionally
-- callable by any non-suspended authenticated user opening an activity,
-- because public activities are visible from the map to non-members and
-- the lazy-transition flow needs to fire on those views too. The audit
-- agent's "membership/creator gate" suggestion would break that.
--
-- Returns NULL on auth/suspension fail (silent no-op) to match the
-- existing "RETURN NULL on bad inputs" shape of this function.
--
-- Body otherwise identical to 00136.

CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN NULL;
  END IF;

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
