-- Migration 00110: presence reminder fixes
--
-- (1) notify_presence_reminders no longer excludes the creator. With the
--     strict model (no creator override), the creator must self-validate too.
-- (2) transition_statuses_only now calls notify_presence_reminders so the
--     fire doesn't depend on someone opening the activity detail (lazy path).
-- (3) New notify_presence_last_call: at completion (T+duration), pings every
--     accepted user still NULL with a "scan QR to validate" message. They
--     have 1h post-end to act before the QR window closes.

-- ----------------------------------------------------------------------------
-- 1. notify_presence_reminders — include creator
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

-- ----------------------------------------------------------------------------
-- 2. notify_presence_last_call — fires at completion for users still NULL
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_presence_last_call(
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
  IF v_activity.status != 'completed' THEN RETURN; END IF;
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
          AND n.type = 'presence_last_call'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    PERFORM create_notification(
      v_target.user_id,
      'presence_last_call',
      'Dernière chance — valide ta présence',
      'Scan le QR du créateur dans l''heure pour ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_last_call FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Wire into transitions
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

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      PERFORM notify_presence_reminders(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_presence_reminders(p_activity_id);
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
-- 4. transition_statuses_only — sweep reminders + last calls on every run
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

  -- Sweep presence_reminder for in_progress activities (notify_presence_reminders dedupes)
  FOR v_activity_id IN
    SELECT id FROM activities
    WHERE status = 'in_progress' AND requires_presence = TRUE AND deleted_at IS NULL
  LOOP
    PERFORM notify_presence_reminders(v_activity_id);
  END LOOP;

  -- Sweep presence_last_call for completed activities still inside the QR window
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

  -- Auto-FALSE no-shows whose 24h window has closed
  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
