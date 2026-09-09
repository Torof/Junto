-- ============================================================================
-- 00397 — Make demo activities JOINABLE by an admin in demo mode (Scott 2026-09-05).
-- Demo mode is admin-only + meant to let the admin experience the full app
-- without seeding/cleaning real activities. join_activity blocked ALL demo
-- activities (00350) → the admin couldn't join → "peut-être complète ou annulée".
-- Relax the guard to `is_demo AND NOT demo_content_visible()`: an admin with
-- demo mode ON can join demo activities; everyone else (real users, anon, or
-- demo OFF) stays blocked exactly as before. leave_activity / request_seat /
-- send_message carry NO is_demo guard, so chat / leave / seat already work once
-- the join succeeds. (Reproduced from 00365; only the is_demo line changes.)
-- ============================================================================

CREATE OR REPLACE FUNCTION join_activity(p_activity_id UUID)
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo, deleted_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Demo activities are joinable only by an admin currently in demo mode.
  IF v_activity.is_demo AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at INTO v_existing
  FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    IF v_existing.status = 'invited' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE participations
      SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
      WHERE id = v_existing.id;
      SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
      PERFORM create_notification(
        v_activity.creator_id, 'invitation_accepted',
        coalesce(v_user_name, 'Quelqu''un') || ' a accepté ton invitation',
        regexp_replace(v_activity.title, '<[^>]*>', '', 'g'),
        jsonb_build_object('activity_id', p_activity_id)
      );
      RETURN 'accepted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now(), refused_at = NULL
    WHERE id = v_existing.id;
  ELSE
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id, 'join_request', 'Nouvelle demande',
      v_user_name || ' souhaite rejoindre ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  ELSE
    PERFORM notify_participant_joined(v_activity.creator_id, p_activity_id, v_user_name, v_activity.title);
  END IF;

  RETURN v_result_status;
END;
$$;
REVOKE ALL ON FUNCTION join_activity(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION join_activity(UUID) TO authenticated;
