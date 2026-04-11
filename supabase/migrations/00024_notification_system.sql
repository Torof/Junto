-- Migration 00024: Notification system
-- 1. Internal create_notification function
-- 2. Mark notifications as read function (client-callable)
-- 3. Modify existing functions to create notifications on key events

-- ============================================================================
-- FUNCTION: create_notification (INTERNAL — not callable by clients)
-- ============================================================================
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id UUID;
BEGIN
  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (p_user_id, p_type, p_title, p_body, p_data, now())
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_notification FROM anon, authenticated;

-- ============================================================================
-- FUNCTION: mark_notification_read (client-callable)
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_notification_read(
  p_notification_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE notifications
  SET read_at = now()
  WHERE id = p_notification_id
    AND user_id = v_user_id
    AND read_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION mark_notification_read FROM anon;
GRANT EXECUTE ON FUNCTION mark_notification_read TO authenticated;

-- ============================================================================
-- FUNCTION: mark_all_notifications_read (client-callable)
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE notifications
  SET read_at = now()
  WHERE user_id = v_user_id
    AND read_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION mark_all_notifications_read FROM anon;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read TO authenticated;

-- ============================================================================
-- UPDATE: join_activity — notify creator on join/request
-- ============================================================================
CREATE OR REPLACE FUNCTION join_activity(
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
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
  v_user_name TEXT;
  v_activity_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= v_activity.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  -- Check for existing participation (withdrawn or refused — allow re-join)
  SELECT id, status INTO v_existing
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now()
    WHERE id = v_existing.id;
  ELSE
    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  -- Notify creator
  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id,
      'join_request',
      'Nouvelle demande',
      v_user_name || ' souhaite rejoindre ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  ELSE
    PERFORM create_notification(
      v_activity.creator_id,
      'participant_joined',
      'Nouveau participant',
      v_user_name || ' a rejoint ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  END IF;

  RETURN v_result_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION join_activity FROM public;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;

-- ============================================================================
-- UPDATE: accept_participation — notify participant
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_current_count INTEGER;
  v_activity_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.max_participants, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status != 'pending' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  IF v_current_count >= v_participation.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;

  -- Notify participant
  PERFORM create_notification(
    v_participation.user_id,
    'request_accepted',
    'Demande acceptée',
    'Ta demande pour ' || v_participation.title || ' a été acceptée',
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_participation FROM public;
GRANT EXECUTE ON FUNCTION accept_participation TO authenticated;

-- ============================================================================
-- UPDATE: refuse_participation — notify participant
-- ============================================================================
CREATE OR REPLACE FUNCTION refuse_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status != 'pending' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'refused' WHERE id = p_participation_id;

  -- Notify participant
  PERFORM create_notification(
    v_participation.user_id,
    'request_refused',
    'Demande refusée',
    'Ta demande pour ' || v_participation.title || ' a été refusée',
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION refuse_participation FROM public;
GRANT EXECUTE ON FUNCTION refuse_participation TO authenticated;

-- ============================================================================
-- UPDATE: leave_activity — notify creator
-- ============================================================================
CREATE OR REPLACE FUNCTION leave_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity_status TEXT;
  v_activity_creator UUID;
  v_activity_title TEXT;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.status
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status = 'removed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT status, creator_id, title INTO v_activity_status, v_activity_creator, v_activity_title
  FROM activities WHERE id = p_activity_id;
  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn', left_at = now()
  WHERE id = v_participation.id;

  -- Notify creator
  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity_creator,
    'participant_left',
    'Participant parti',
    v_user_name || ' a quitté ' || v_activity_title,
    jsonb_build_object('activity_id', p_activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION leave_activity FROM public;
GRANT EXECUTE ON FUNCTION leave_activity TO authenticated;

-- ============================================================================
-- UPDATE: remove_participant — notify removed participant
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_participant(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, a.creator_id, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.user_id = v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status != 'accepted' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'removed' WHERE id = p_participation_id;

  -- Notify removed participant
  PERFORM create_notification(
    v_participation.user_id,
    'participant_removed',
    'Retiré de l''activité',
    'Tu as été retiré de ' || v_participation.title,
    jsonb_build_object('activity_id', v_participation.activity_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_participant FROM public;
GRANT EXECUTE ON FUNCTION remove_participant TO authenticated;

-- ============================================================================
-- UPDATE: cancel_activity — notify all accepted participants
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = p_activity_id;

  -- Notify all accepted participants (except creator)
  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_cancelled',
      'Activité annulée',
      v_activity.title || ' a été annulée',
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_activity FROM public;
GRANT EXECUTE ON FUNCTION cancel_activity TO authenticated;
