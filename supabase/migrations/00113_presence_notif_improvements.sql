-- Migration 00113: presence notification improvements
--
-- (#1) New presence_pre_warning notification — fires 30min before activity
--     start. Heads-up so users prepare to validate.
-- (#2) New qr_create_reminder notification — fires at activity start, sent
--     ONLY to the creator. Pushes them to generate the QR so participants
--     have something to scan.
-- (#5) Better body text on existing presence_reminder + presence_last_call
--     (more parlant on the lockscreen).
--
-- Both new types are added to the partial unique dedup index.

-- ----------------------------------------------------------------------------
-- Extend the partial UNIQUE dedup index to cover the new types.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_notif_presence_dedup;
CREATE UNIQUE INDEX idx_notif_presence_dedup
ON notifications (user_id, type, ((data->>'activity_id')))
WHERE type IN (
  'presence_pre_warning',
  'presence_reminder',
  'presence_last_call',
  'qr_create_reminder'
);

-- ----------------------------------------------------------------------------
-- (#1) notify_presence_pre_warning(p_activity_id)
--     For published activities whose start is within 30min, ping every
--     accepted participant (creator included) with a heads-up.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_presence_pre_warning(
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
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'published' THEN RETURN; END IF;
  -- Only fire inside the 30min window before start
  IF now() < v_activity.starts_at - INTERVAL '30 minutes' OR now() >= v_activity.starts_at THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning',
        v_activity.title,
        'Démarre dans 30 min — prépare-toi à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_pre_warning FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- (#2) notify_creator_qr_reminder(p_activity_id)
--     At activity start, push the creator to generate the presence QR.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_creator_qr_reminder(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
BEGIN
  SELECT id, creator_id, title, status, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'in_progress' THEN RETURN; END IF;

  -- Already sent for this activity?
  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = 'qr_create_reminder'
      AND (data->>'activity_id')::uuid = p_activity_id
  ) THEN RETURN; END IF;

  BEGIN
    PERFORM create_notification(
      v_activity.creator_id,
      'qr_create_reminder',
      v_activity.title,
      'Génère le QR de présence pour tes participants',
      jsonb_build_object('activity_id', p_activity_id)
    );
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_creator_qr_reminder FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- (#5) Improve presence_reminder body — more explicit CTA on the lockscreen
-- ----------------------------------------------------------------------------
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
  SELECT id, title, status, requires_presence
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
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_reminder'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_reminder',
        v_activity.title,
        'Tu y es ? Tape ici pour valider ta présence (géo ou QR)',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_reminders FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- Wire the new helpers into transition_single_activity (lazy path).
-- ----------------------------------------------------------------------------
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

  IF v_activity.status = 'published' AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  -- Fire pre-warning while still published, in the 30min window before start
  IF v_activity.status = 'published' THEN
    PERFORM notify_presence_pre_warning(p_activity_id);
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

  IF v_activity.status = 'completed' THEN
    PERFORM notify_presence_last_call(p_activity_id);
    PERFORM close_presence_window_for(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;

-- ----------------------------------------------------------------------------
-- Wire into transition_statuses_only (global sweep)
-- ----------------------------------------------------------------------------
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

  -- Pre-warning sweep — published activities in the 30min window before start
  FOR v_activity_id IN
    SELECT id FROM activities
    WHERE status = 'published'
      AND requires_presence = TRUE
      AND deleted_at IS NULL
      AND starts_at - INTERVAL '30 minutes' <= now()
      AND starts_at > now()
  LOOP
    PERFORM notify_presence_pre_warning(v_activity_id);
  END LOOP;

  -- Presence reminder + creator QR reminder for in_progress activities
  FOR v_activity_id IN
    SELECT id FROM activities
    WHERE status = 'in_progress' AND requires_presence = TRUE AND deleted_at IS NULL
  LOOP
    PERFORM notify_presence_reminders(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  -- Last-call sweep for completed activities still inside the QR window
  FOR v_activity_id IN
    SELECT id FROM activities a
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND now() <= a.starts_at + a.duration + INTERVAL '1 hour'
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.status = 'accepted' AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM notify_presence_last_call(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
