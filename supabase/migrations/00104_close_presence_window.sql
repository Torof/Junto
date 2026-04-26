-- Migration 00104: capture no-show + presence-validation reminder
--
-- Two gaps found in the reliability chain:
--   1. A "true no-show" (joined → never validated → never withdrew → creator
--      never overrode) leaves confirmed_present = NULL. The Bayesian formula
--      ignores NULLs, so the score is unaffected. We add an automatic flip
--      to FALSE once the presence window has fully closed.
--   2. Participants are never told to validate their own presence. Only the
--      creator gets a "confirm_presence" prompt at completion. We add a
--      "presence_reminder" notification when the activity transitions to
--      in_progress, sent to every accepted participant who hasn't validated.
--
-- Both functions are internal — wired into the existing transition functions.

-- ============================================================================
-- close_presence_window_for(p_activity_id)
--   Idempotent. Flips uncomfirmed accepted participations to FALSE on a
--   single completed+presence-required activity whose 12h grace window has
--   elapsed. Recalculates each affected user's score.
-- ============================================================================
CREATE OR REPLACE FUNCTION close_presence_window_for(
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
  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '12 hours' THEN RETURN; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  FOR v_target IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status = 'accepted'
      AND confirmed_present IS NULL
  LOOP
    UPDATE participations
    SET confirmed_present = FALSE
    WHERE activity_id = p_activity_id
      AND user_id = v_target.user_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target.user_id);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION close_presence_window_for FROM anon, authenticated;


-- ============================================================================
-- close_due_presence_windows()
--   Sweeps every completed activity whose presence window has closed and has
--   any unconfirmed accepted participations. Used by the global lazy
--   transition fallback so the no-show capture happens even when nobody
--   opens the activity detail.
-- ============================================================================
CREATE OR REPLACE FUNCTION close_due_presence_windows()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.starts_at + a.duration + INTERVAL '12 hours' < now()
      AND a.deleted_at IS NULL
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id
          AND p.status = 'accepted'
          AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION close_due_presence_windows FROM anon, authenticated;


-- ============================================================================
-- notify_presence_reminders(p_activity_id)
--   Idempotent helper: send a "validate your presence" notification to every
--   accepted participant (excluding the creator) of an in_progress activity
--   that requires presence, when they haven't validated yet AND haven't
--   already received the reminder for this activity.
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_reminders(
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
  SELECT id, creator_id, title, status, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'in_progress' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.user_id != v_activity.creator_id
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_reminder'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    PERFORM create_notification(
      v_target.user_id,
      'presence_reminder',
      'Pense à valider ta présence',
      v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_reminders FROM anon, authenticated;


-- ============================================================================
-- Wire the helpers into the existing transition functions.
-- ============================================================================
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, creator_id, title, status, starts_at, duration INTO v_activity
  FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_activity IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_user_id != v_activity.creator_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- published → expired (no participants, 2h past)
  IF v_activity.status = 'published' AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  -- published → in_progress (now also fires presence reminders)
  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      PERFORM notify_presence_reminders(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    -- Idempotent: if we're already in_progress, still try to send reminders
    -- for anyone who hasn't received one yet. The function dedupes itself.
    PERFORM notify_presence_reminders(p_activity_id);
  END IF;

  -- in_progress → completed (with notifications + close presence window when due)
  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';

    IF FOUND THEN
      PERFORM create_notification(
        v_activity.creator_id,
        'confirm_presence',
        'Activité terminée',
        'Confirme qui était présent à ' || v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );

      FOR v_participant IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
      LOOP
        PERFORM create_notification(
          v_participant.user_id,
          'rate_participants',
          'Évalue tes co-participants',
          'Comment s''est passé ' || v_activity.title || ' ?',
          jsonb_build_object('activity_id', p_activity_id)
        );
      END LOOP;

      v_activity.status := 'completed';
    END IF;
  END IF;

  -- Whether we just flipped or were already completed, attempt to close the
  -- presence window. The helper is a no-op if the 12h grace hasn't elapsed.
  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;


CREATE OR REPLACE FUNCTION transition_statuses_only()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published'
    AND starts_at <= now();

  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress'
    AND starts_at + duration <= now();

  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  -- Sweep no-show captures for any activity whose presence window has closed.
  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
