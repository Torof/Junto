-- ============================================================================
-- 00357 — Activity invitations (brique 2, part 5 — validated lot ④).
--
-- The mirror of join-requests: the CREATOR invites an eligible partner;
-- accepting makes them a participant directly (pre-approved). No seat
-- reservation: capacity is checked at accept time (Scott decision).
-- RETURNS VOID on send — no per-target outcome is observable (skips have
-- merged causes; a past decline is invisible to the sender).
-- ============================================================================

-- ---------- send_activity_invitations ----------
CREATE OR REPLACE FUNCTION send_activity_invitations(
  p_activity_id UUID,
  p_user_ids UUID[],
  p_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_n INTEGER;
  v_daily INTEGER;
  v_target UUID;
  v_existing RECORD;
  v_clean_msg TEXT;
  v_sender_name TEXT;
  v_clean_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_n := array_length(p_user_ids, 1);
  IF p_user_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_n > 20 THEN RAISE EXCEPTION 'junto.invite_cap'; END IF;

  IF p_message IS NOT NULL AND char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'junto.message_too_long';
  END IF;
  v_clean_msg := NULLIF(regexp_replace(trim(COALESCE(p_message, '')), '<[^>]*>', '', 'g'), '');

  SELECT id, title, creator_id, status, deleted_at, is_demo INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_activity.creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_invite'));
  SELECT count(*) INTO v_daily FROM participations
  WHERE invited_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 30 THEN RAISE EXCEPTION 'junto.invite_daily_cap'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  PERFORM set_config('junto.bypass_lock', 'true', true);

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    -- Server-side eligibility (never UI-only): active connection, or hardened
    -- recent partner with no pending/declined conversation between the pair.
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);

    SELECT id, status INTO v_existing FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_target;

    IF v_existing.id IS NULL THEN
      INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
      VALUES (p_activity_id, v_target, 'invited', v_user_id, v_clean_msg, now());
    ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
      -- UNIQUE(user,activity): re-invite reuses the row. The creator re-inviting
      -- a 'removed' user is an explicit reversal of his own removal.
      UPDATE participations
      SET status = 'invited', invited_by = v_user_id, invite_message = v_clean_msg,
          created_at = now(), refused_at = NULL, left_at = NULL
      WHERE id = v_existing.id;
    ELSE
      CONTINUE; -- invited / pending / accepted → skip silently
    END IF;

    PERFORM create_notification(
      v_target,
      'activity_invitation',
      coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à rejoindre',
      v_clean_title,
      jsonb_build_object('activity_id', p_activity_id, 'type', 'activity_invitation')
    );
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION send_activity_invitations(UUID, UUID[], TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_activity_invitations(UUID, UUID[], TEXT) TO authenticated;

-- ---------- accept_activity_invitation ----------
CREATE OR REPLACE FUNCTION accept_activity_invitation(p_activity_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_row RECORD;
  v_count INTEGER;
  v_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, deleted_at, max_participants, title INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id INTO v_row FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_count FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
  WHERE id = v_row.id;
  -- The 00354 sync trigger creates the member row (chat access) automatically.

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id,
    'invitation_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ton invitation',
    regexp_replace(v_activity.title, '<[^>]*>', '', 'g'),
    jsonb_build_object('activity_id', p_activity_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION accept_activity_invitation(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION accept_activity_invitation(UUID) TO authenticated;

-- ---------- decline_activity_invitation ----------
CREATE OR REPLACE FUNCTION decline_activity_invitation(p_activity_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- No refused_at (no cooldown inflicted), no notification (silent), row
  -- deleted so a later re-invite is a clean INSERT. Not invited → no-op.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  DELETE FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
END;
$$;
REVOKE ALL ON FUNCTION decline_activity_invitation(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION decline_activity_invitation(UUID) TO authenticated;

-- ---------- get_my_invitations (Demandes read — curated) ----------
CREATE OR REPLACE FUNCTION get_my_invitations()
RETURNS TABLE (
  activity_id UUID,
  activity_title TEXT,
  sport_id UUID,
  starts_at TIMESTAMPTZ,
  invited_by UUID,
  inviter_name TEXT,
  inviter_avatar TEXT,
  invite_message TEXT,
  invited_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.id, a.title, a.sport_id, a.starts_at,
         p.invited_by, pp.display_name, pp.avatar_url,
         p.invite_message, p.created_at
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  LEFT JOIN public_profiles pp ON pp.id = p.invited_by
  WHERE auth.uid() IS NOT NULL
    AND p.user_id = auth.uid()
    AND p.status = 'invited'
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
  ORDER BY p.created_at DESC
$$;
REVOKE ALL ON FUNCTION get_my_invitations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_invitations() TO authenticated;

-- ---------- join_activity: invited branch (00350 body + the new branch) ----------
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

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Demo content is a showcase, never joinable by real accounts.
  IF v_activity.is_demo THEN
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

    -- Invited → joining ACCEPTS the invitation, whatever the visibility mode
    -- (the invitation is pre-approved by the creator). Capacity already checked
    -- above under the activity lock.
    IF v_existing.status = 'invited' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE participations
      SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
      WHERE id = v_existing.id;
      SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
      PERFORM create_notification(
        v_activity.creator_id,
        'invitation_accepted',
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
REVOKE EXECUTE ON FUNCTION join_activity FROM anon;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;
