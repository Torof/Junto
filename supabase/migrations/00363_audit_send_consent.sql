-- ============================================================================
-- 00363 — Post-code audit: send path + consent parity.
--   • message_author_visible: DM block hides the WHOLE thread (both sides) —
--     restores the 00031 anti-harassment control lost at port.
--   • get_my_conversations: exclude DMs with a block between the pair.
--   • send_message: re-add the peer-suspension gate for DMs.
--   • reply_to_request: never reactivate a pending/declined DM (would reverse a
--     silent decline / silently accept a pending contact request).
--   • get_wall_messages: server-side LIMIT (was transferring full history).
--   • edit_message: for activity messages, re-assert alive activity + membership.
-- ============================================================================

CREATE OR REPLACE FUNCTION private.message_author_visible(p_conversation_id UUID, p_sender_id UUID, p_viewer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_sender_id IS NULL  -- system message (deleted author): always visible
    OR (
      -- ACTIVITY: hide authors the viewer blocked, or suspended authors (wall parity 00324).
      NOT (
        EXISTS (SELECT 1 FROM conversations c WHERE c.id = p_conversation_id AND c.type = 'activity')
        AND (
          EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_viewer_id AND blocked_id = p_sender_id)
          OR private.user_is_suspended(p_sender_id)
        )
      )
      -- DM: hide the whole thread if a block exists between the two parties,
      -- either direction (restores 00031 private_messages_select behaviour).
      AND NOT EXISTS (
        SELECT 1 FROM conversations c
        WHERE c.id = p_conversation_id AND c.type = 'dm'
          AND EXISTS (
            SELECT 1 FROM blocked_users b
            WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
               OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
          )
      )
    );
$$;

CREATE OR REPLACE FUNCTION get_my_conversations()
RETURNS TABLE (
  id UUID, user_1 UUID, user_2 UUID, status TEXT,
  last_message_at TIMESTAMPTZ, created_at TIMESTAMPTZ,
  other_user_name TEXT, other_user_avatar TEXT,
  last_message_content TEXT, last_message_sender_id UUID, last_message_metadata JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.user_1, c.user_2, c.status, c.last_message_at, c.created_at,
         COALESCE(pp.display_name, '?'), pp.avatar_url,
         lm.content, lm.sender_id, lm.metadata
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND c.type = 'dm'
    AND c.status = 'active'
    -- Blocked pair → the DM disappears from the hub (00031 parity).
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
         OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
    )
  ORDER BY c.last_message_at DESC NULLS LAST
$$;
REVOKE ALL ON FUNCTION get_my_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_conversations() TO authenticated;

CREATE OR REPLACE FUNCTION send_message(
  p_conversation_id UUID,
  p_content TEXT,
  p_reply_to_message_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other UUID;
  v_count INTEGER;
  v_limit INTEGER;
  v_msg_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = v_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    -- Peer must exist and not be suspended (parity with old send_private_message).
    IF EXISTS (SELECT 1 FROM users WHERE id = v_other AND suspended_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 15;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 30;
  ELSE
    v_limit := 30;
  END IF;

  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM messages m
    WHERE m.id = p_reply_to_message_id
      AND m.conversation_id = p_conversation_id AND m.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_send_message'));
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND conversation_id = p_conversation_id
    AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= v_limit THEN
    IF v_conv.type = 'dm' THEN RAISE EXCEPTION 'junto.dm_rate_limit';
    ELSE RAISE EXCEPTION 'junto.wall_rate_limit'; END IF;
  END IF;
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= 60 THEN RAISE EXCEPTION 'junto.send_rate_limit'; END IF;

  INSERT INTO messages (conversation_id, sender_id, content, reply_to_message_id)
  VALUES (p_conversation_id, v_user_id, trim(p_content), p_reply_to_message_id)
  RETURNING id INTO v_msg_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;

  RETURN v_msg_id;
END;
$$;
REVOKE ALL ON FUNCTION send_message(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_message(UUID, TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION reply_to_request(
  p_request_type TEXT,
  p_request_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_other UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_conv RECORD;
  v_conv_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_request_type = 'join' THEN
    SELECT p.user_id INTO v_other
    FROM participations p JOIN activities a ON a.id = p.activity_id
    WHERE p.id = p_request_id AND p.status = 'pending'
      AND a.creator_id = v_user_id AND a.deleted_at IS NULL;
  ELSIF p_request_type = 'invitation' THEN
    SELECT a.creator_id INTO v_other
    FROM participations p JOIN activities a ON a.id = p.activity_id
    WHERE p.id = p_request_id AND p.status = 'invited'
      AND p.user_id = v_user_id AND a.deleted_at IS NULL;
  ELSIF p_request_type = 'seat' THEN
    SELECT sr.requester_id INTO v_other
    FROM seat_requests sr
    WHERE sr.id = p_request_id AND sr.status = 'pending' AND sr.driver_id = v_user_id;
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_other IS NULL OR v_other = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other)
       OR (blocker_id = v_other AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_other AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id < v_other THEN v_u1 := v_user_id; v_u2 := v_other;
  ELSE v_u1 := v_other; v_u2 := v_user_id; END IF;

  SELECT id, status INTO v_conv FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;

  IF v_conv.id IS NULL THEN
    INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES ('dm', v_u1, v_u2, v_user_id, 'active', 'request_reply', now(), now())
    RETURNING id INTO v_conv_id;
  ELSIF v_conv.status = 'active' THEN
    v_conv_id := v_conv.id;
  ELSE
    -- A pending_request / declined DM exists between the pair. Do NOT silently
    -- reactivate it: that would reverse a silent decline, or accept a pending
    -- contact request without its proper flow. The parties settle that request
    -- through accept/decline_contact_request. The operational request can still
    -- be accepted/declined on its own; only the quick-reply thread is unavailable.
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN send_message(v_conv_id, p_content);
END;
$$;
REVOKE ALL ON FUNCTION reply_to_request(TEXT, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reply_to_request(TEXT, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION get_wall_messages(p_activity_id UUID)
RETURNS TABLE (
  id UUID, user_id UUID, content TEXT, metadata JSONB,
  reply_to_message_id UUID, edited_at TIMESTAMPTZ, created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Latest 200 (server-side cap), returned oldest-first for the UI.
  SELECT * FROM (
    SELECT m.id, m.sender_id, m.content, m.metadata, m.reply_to_message_id,
           m.edited_at, m.created_at
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE auth.uid() IS NOT NULL
      AND c.activity_id = p_activity_id
      AND m.deleted_at IS NULL
      AND private.is_conversation_member(c.id, auth.uid())
      AND private.message_author_visible(c.id, m.sender_id, auth.uid())
    ORDER BY m.created_at DESC
    LIMIT 200
  ) sub
  ORDER BY created_at ASC
$$;
REVOKE ALL ON FUNCTION get_wall_messages(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_wall_messages(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION edit_message(p_message_id UUID, p_content TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv_id UUID;
  v_type TEXT;
  v_activity_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT c.id, c.type, c.activity_id INTO v_conv_id, v_type, v_activity_id
  FROM messages m JOIN conversations c ON c.id = m.conversation_id
  WHERE m.id = p_message_id AND m.sender_id = v_user_id
    AND m.deleted_at IS NULL AND m.metadata IS NULL; -- rich cards not editable
  IF v_conv_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Must still be a member; for activity messages the activity must be alive
  -- (wall edit parity 00177).
  IF NOT private.is_conversation_member(v_conv_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_type = 'activity' AND NOT EXISTS (
    SELECT 1 FROM activities a WHERE a.id = v_activity_id
      AND a.deleted_at IS NULL AND a.status IN ('published', 'in_progress')
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE messages SET content = trim(p_content), edited_at = now()
  WHERE id = p_message_id;
END;
$$;
REVOKE ALL ON FUNCTION edit_message(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION edit_message(UUID, TEXT) TO authenticated;
