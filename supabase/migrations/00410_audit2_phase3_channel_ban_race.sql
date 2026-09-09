-- ============================================================================
-- 00410 — Audit 2nd pass, phase 3 (M2): make channel bans authoritative on the
-- send path + serialize join vs remove.
--
-- The ban was enforced only by the ABSENCE of a membership row: assert_can_send
-- / send_message check is_conversation_member but never channel_bans, and
-- join_channel vs remove_channel_member weren't serialized. Under READ COMMITTED
-- a banned user hammering join_channel while being removed could interleave to
-- end up member AND banned → post + read again.
--
--   (1) assert_can_send: add a channel branch that rejects a banned sender
--       (authoritative — closes the send path regardless of membership state).
--   (2) join_channel + remove_channel_member: take a shared per-conversation
--       advisory xact lock so the DELETE-then-ban and the ban-check-then-INSERT
--       can never interleave → the member+banned state can't arise, so RLS
--       reads stay denied for a banned user too.
-- (Scott 2026-09-09, 2nd adversarial pass.)
-- ============================================================================

-- ---------- (1) assert_can_send — reject banned senders in channels ----------
CREATE OR REPLACE FUNCTION private.assert_can_send(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv RECORD;
  v_other UUID;
BEGIN
  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT private.is_conversation_member(p_conversation_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = p_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = p_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = p_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'channel' THEN
    -- Ban is authoritative on the send path (defense against a join/remove race
    -- that could leave a banned user with a stale membership row).
    IF EXISTS (
      SELECT 1 FROM channel_bans
      WHERE conversation_id = p_conversation_id AND user_id = p_user_id
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.assert_can_send(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- ---------- (2) join_channel — serialize with remove_channel_member ----------
CREATE OR REPLACE FUNCTION join_channel(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_ch RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize against remove_channel_member so a ban-check + INSERT can't
  -- interleave with a DELETE + ban INSERT (no member+banned state).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  SELECT c.conversation_id, c.closed_at INTO v_ch
  FROM channels c WHERE c.conversation_id = p_conversation_id;
  IF v_ch.conversation_id IS NULL OR v_ch.closed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = p_conversation_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, v_user_id, NULL, now())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION join_channel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION join_channel(UUID) TO authenticated;

-- ---------- (2) remove_channel_member — same lock + suspension gate (from 00405) ----------
CREATE OR REPLACE FUNCTION remove_channel_member(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF v_creator IS NULL OR v_creator != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_user_id IS NULL OR p_user_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Serialize against join_channel (see above).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  -- Ban FIRST, then remove membership: with the shared lock this order also
  -- means a concurrent join blocks until the ban row is visible.
  INSERT INTO channel_bans (conversation_id, user_id, banned_by)
  VALUES (p_conversation_id, p_user_id, v_user_id)
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
END;
$$;
REVOKE ALL ON FUNCTION remove_channel_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_channel_member(UUID, UUID) TO authenticated;
