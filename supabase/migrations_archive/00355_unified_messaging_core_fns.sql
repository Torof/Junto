-- ============================================================================
-- 00355 — Unified messaging: core functions (brique 2, part 3 — validated lot ①).
-- send_message (unified), contact-request ports (member rows), mark-read,
-- hidden, reply_to_request. Edit/delete ports follow in the next part.
-- ============================================================================

-- ---------- send_message: the single send path ----------
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

  -- Per-type gates.
  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = v_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
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
    v_limit := 30; -- group
  END IF;

  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM messages m
    WHERE m.id = p_reply_to_message_id
      AND m.conversation_id = p_conversation_id AND m.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Rate limits under one advisory lock: per-conversation + global sender cap.
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
  -- Unhide for every member (a new message resurfaces the conversation).
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;

  RETURN v_msg_id;
END;
$$;
REVOKE ALL ON FUNCTION send_message(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_message(UUID, TEXT, UUID) TO authenticated;

-- ---------- contact-request ports: member rows at creation ----------
-- send_contact_request keeps its 00350 body; only the INSERT block changes to
-- also create the two member rows.
CREATE OR REPLACE FUNCTION create_dm_member_rows()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.type = 'dm' THEN
    INSERT INTO conversation_members (conversation_id, user_id, joined_at)
    VALUES (NEW.id, NEW.user_1, now()), (NEW.id, NEW.user_2, now())
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
-- A trigger (not function edits) so EVERY dm creation path — send_contact_request,
-- invite_users_to_activity's pending branch, future reply_to_request — gets its
-- member rows atomically without touching each writer.
CREATE TRIGGER trg_dm_member_rows
  AFTER INSERT ON conversations
  FOR EACH ROW EXECUTE FUNCTION create_dm_member_rows();

-- accept_contact_request: port the first-message insert onto `messages`.
-- (Fetch current definition's behavior: flip to active + seed message + notify.)
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
END;
$$;
REVOKE ALL ON FUNCTION accept_contact_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION accept_contact_request(UUID) TO authenticated;

-- decline_contact_request: status-blind recipient path (validated refinement).
CREATE OR REPLACE FUNCTION decline_contact_request(
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL OR v_conv.type != 'dm' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.status = 'pending_request' THEN
    UPDATE conversations SET status = 'declined' WHERE id = p_conversation_id;
  ELSIF v_conv.status = 'declined' THEN
    NULL; -- double-tap safe, indistinguishable
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION decline_contact_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION decline_contact_request(UUID) TO authenticated;

-- ---------- mark-read + hidden (member self-service, RPC-only writes) ----------
CREATE OR REPLACE FUNCTION mark_conversation_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE conversation_members
  SET last_read_at = GREATEST(COALESCE(last_read_at, 'epoch'::timestamptz), now())
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
  -- Not a member → zero rows → silent no-op (own state only, no oracle).
END;
$$;
REVOKE ALL ON FUNCTION mark_conversation_read(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mark_conversation_read(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION set_conversation_hidden(p_conversation_id UUID, p_hidden BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE conversation_members
  SET hidden_at = CASE WHEN p_hidden THEN now() ELSE NULL END
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION set_conversation_hidden(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_conversation_hidden(UUID, BOOLEAN) TO authenticated;

-- ---------- reply_to_request: the recipient opens the thread ----------
-- Amended 00072 invariant: an active DM requires BOTH parties' consent — the
-- requester consented by requesting, the recipient consents by replying.
CREATE OR REPLACE FUNCTION reply_to_request(
  p_request_type TEXT,   -- 'join' | 'seat' | 'invitation'
  p_request_id UUID,     -- participation id (join/invitation) or seat_request id
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

  -- Resolve the live request and verify the CALLER IS ITS RECIPIENT.
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
    -- pending/declined between the pair: the recipient's reply supersedes —
    -- activate (their consent is explicit; the other party initiated contact).
    UPDATE conversations SET status = 'active', request_expires_at = NULL
    WHERE id = v_conv.id;
    v_conv_id := v_conv.id;
  END IF;

  RETURN send_message(v_conv_id, p_content);
END;
$$;
REVOKE ALL ON FUNCTION reply_to_request(TEXT, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reply_to_request(TEXT, UUID, TEXT) TO authenticated;

-- Allow the new initiated_from value.
DO $$
DECLARE v_cname TEXT;
BEGIN
  SELECT conname INTO v_cname
  FROM pg_constraint
  WHERE conrelid = 'conversations'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%initiated_from%';
  IF v_cname IS NOT NULL THEN
    EXECUTE 'ALTER TABLE conversations DROP CONSTRAINT ' || quote_ident(v_cname);
  END IF;
END $$;
ALTER TABLE conversations ADD CONSTRAINT conversations_initiated_from_check
  CHECK (initiated_from IS NULL OR initiated_from IN ('profile', 'discovery', 'transport', 'invite', 'request_reply'));
