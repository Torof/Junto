-- Migration 00301: fix inverted participant_joined notification copy.
--
-- Since mig 00238 (and carried into 00269), join_activity called
-- notify_participant_joined with (title, name) instead of (name, title),
-- producing bodies like "Sortie escalade a rejoint Marc". This redefines
-- join_activity BYTE-IDENTICAL to its 00269 definition except the two
-- swapped arguments -- the authorization chain is untouched.

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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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

  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at INTO v_existing
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    -- Re-check capacity immediately before mutating. Activity row is
    -- still locked via FOR UPDATE above, but our count was read before
    -- handling pending state — refuse-then-rejoin within the lock
    -- holds, but defence-in-depth.
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted';
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
      FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted';
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
      v_activity.creator_id,
      'join_request',
      'Nouvelle demande',
      v_user_name || ' souhaite rejoindre ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  ELSE
    PERFORM notify_participant_joined(
      v_activity.creator_id,
      p_activity_id,
      v_user_name,
      v_activity.title
    );
  END IF;

  RETURN v_result_status;
END;
$$;
