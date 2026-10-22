-- ============================================================================
-- 00378 — Discovery « Inviter » : demande de contact pré-cadrée sur une sortie.
--
-- From a Discovery card you don't yet have a connection with, "Inviter" sends a
-- CONTACT REQUEST framed around one of your own activities that matches the
-- target's active dispo (sport ∈ dispo.sport_keys ∩ activity.starts_at ∈ dispo
-- window). The anti-cold-invite gate is preserved: nothing lands in the target's
-- participation list until THEY accept the contact request. On accept, the pair
-- is connected first, then the invitation materialises as an 'invited'
-- participation (they still confirm the outing via the activity screen —
-- capacity is checked there, exactly like a normal invite).
--
-- Level is NEVER a match filter (human judgment — Discovery doctrine).
-- ============================================================================

-- ---------- Schema: link a pending request to the framed activity ----------
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS pending_activity_id UUID
    REFERENCES activities(id) ON DELETE SET NULL;

-- Privileged: only the SECURITY DEFINER writers below set/clear it. Freeze it to
-- OLD on any client UPDATE (whitelist pattern, bypass_lock escape hatch).
CREATE OR REPLACE FUNCTION conversations_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.user_1 := OLD.user_1;
  NEW.user_2 := OLD.user_2;
  NEW.type := OLD.type;
  NEW.activity_id := OLD.activity_id;
  NEW.created_by := OLD.created_by;
  NEW.created_at := OLD.created_at;
  NEW.initiated_by := OLD.initiated_by;
  NEW.initiated_from := OLD.initiated_from;
  NEW.request_sender_id := OLD.request_sender_id;
  NEW.pending_activity_id := OLD.pending_activity_id;
  RETURN NEW;
END;
$$;

-- ---------- get_invitable_activities_for_dispo (read — feeds the picker) ----------
-- MY future activities that match the target's active dispo. The target's window
-- stays server-side (never returned). Silent empty on any ineligibility.
CREATE OR REPLACE FUNCTION get_invitable_activities_for_dispo(p_target_user_id UUID)
RETURNS TABLE (
  id UUID,
  title TEXT,
  sport_key TEXT,
  starts_at TIMESTAMPTZ,
  max_participants INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_dispo RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_target_user_id THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT a.id, a.title, s.key, a.starts_at, a.max_participants
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.creator_id = v_user_id
    AND a.deleted_at IS NULL
    AND NOT a.is_demo
    AND a.status IN ('published', 'in_progress')
    AND s.key = ANY(v_dispo.sport_keys)
    AND a.starts_at BETWEEN v_dispo.window_start AND v_dispo.window_end
  ORDER BY a.starts_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION get_invitable_activities_for_dispo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_invitable_activities_for_dispo(UUID) TO authenticated;

-- ---------- send_discovery_invite ----------
-- A contact request (same caps/quota as send_contact_request) framed around an
-- activity. RETURNS the conversation id.
CREATE OR REPLACE FUNCTION send_discovery_invite(
  p_target_user_id UUID,
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_activity RECORD;
  v_sport_key TEXT;
  v_dispo RECORD;
  v_clean_title TEXT;
  v_message TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_target_user_id AND u.suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be mine, live, real.
  SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo, a.starts_at, a.sport_id
  INTO v_activity FROM activities a WHERE a.id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.creator_id != v_user_id
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key FROM sports s WHERE s.id = v_activity.sport_id;

  -- Match against the target's ACTIVE dispo: sport overlap + date within window.
  -- Level is deliberately not checked (human judgment).
  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active;
  IF NOT FOUND
     OR v_sport_key IS NULL
     OR NOT (v_sport_key = ANY(v_dispo.sport_keys))
     OR v_activity.starts_at < v_dispo.window_start
     OR v_activity.starts_at > v_dispo.window_end THEN
    RAISE EXCEPTION 'junto.discovery_no_match';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  -- Already have a row for this pair? Active = already connected (use the normal
  -- invite flow); any other existing row blocks a duplicate request.
  SELECT id INTO v_conversation_id
  FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;
  IF v_conversation_id IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Same quota as ordinary contact requests (this IS one).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND (
      status = 'pending_request'
      OR (status = 'declined' AND created_at > NOW() - INTERVAL '30 days')
    );
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  v_message := 'Je t''invite à rejoindre « ' || v_clean_title || ' »';

  INSERT INTO conversations (
    user_1, user_2, initiated_by, status, initiated_from,
    request_sender_id, request_message, request_expires_at,
    pending_activity_id, created_at, last_message_at
  )
  VALUES (
    v_user_1, v_user_2, v_user_id, 'pending_request', 'invite',
    v_user_id, v_message, NOW() + INTERVAL '30 days',
    p_activity_id, NOW(), NOW()
  )
  RETURNING id INTO v_conversation_id;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
    v_clean_title,
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'activity_id', p_activity_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION send_discovery_invite(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_discovery_invite(UUID, UUID) TO authenticated;

-- ---------- accept_contact_request (recreated: materialise the framed invite) ----------
CREATE OR REPLACE FUNCTION accept_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_name TEXT;
  v_act RECORD;
  v_existing RECORD;
  v_sender_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL OR v_conv.type != 'dm' OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Defense-in-depth: a block that appeared meanwhile forbids the acceptance.
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_conv.request_sender_id)
       OR (blocker_id = v_conv.request_sender_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE conversations
  SET status = 'active', request_expires_at = NULL, last_message_at = now()
  WHERE id = p_conversation_id;

  -- The request message becomes the first message of the thread.
  IF v_conv.request_message IS NOT NULL AND char_length(trim(v_conv.request_message)) > 0 THEN
    INSERT INTO messages (conversation_id, sender_id, content, created_at)
    VALUES (p_conversation_id, v_conv.request_sender_id, v_conv.request_message, now());
  END IF;

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_conv.request_sender_id,
    'contact_request_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ta demande',
    '',
    jsonb_build_object('conversation_id', p_conversation_id)
  );

  -- Discovery invite: the request was framed around one of the sender's
  -- activities. The pair is connected now, so the anti-cold gate holds —
  -- materialise the invitation as an 'invited' participation (the accepter
  -- still confirms the outing via the activity screen; capacity is checked
  -- there). Consume the link regardless of outcome.
  IF v_conv.pending_activity_id IS NOT NULL THEN
    SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo
    INTO v_act FROM activities a WHERE a.id = v_conv.pending_activity_id;

    IF v_act.id IS NOT NULL AND v_act.deleted_at IS NULL AND NOT v_act.is_demo
       AND v_act.creator_id = v_conv.request_sender_id
       AND v_act.status IN ('published', 'in_progress') THEN

      SELECT id, status INTO v_existing FROM participations
      WHERE activity_id = v_act.id AND user_id = v_user_id;

      PERFORM set_config('junto.bypass_lock', 'true', true);
      IF v_existing.id IS NULL THEN
        INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
        VALUES (v_act.id, v_user_id, 'invited', v_conv.request_sender_id, NULL, now());
      ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
        UPDATE participations
        SET status = 'invited', invited_by = v_conv.request_sender_id,
            invite_message = NULL, created_at = now(), refused_at = NULL, left_at = NULL
        WHERE id = v_existing.id;
      END IF;
      PERFORM set_config('junto.bypass_lock', 'false', true);

      IF v_existing.id IS NULL OR v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
        SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_conv.request_sender_id;
        PERFORM create_notification(
          v_user_id,
          'activity_invitation',
          coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à rejoindre',
          regexp_replace(v_act.title, '<[^>]*>', '', 'g'),
          jsonb_build_object('activity_id', v_act.id, 'type', 'activity_invitation')
        );
      END IF;
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations SET pending_activity_id = NULL WHERE id = p_conversation_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION accept_contact_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION accept_contact_request(UUID) TO authenticated;
