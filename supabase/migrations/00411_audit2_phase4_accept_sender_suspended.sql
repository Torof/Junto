-- ============================================================================
-- 00411 — Audit 2nd pass, phase 4 (LOW): re-check the SENDER's suspension at
-- accept time in accept_contact_request.
--
-- The accepter's suspension was re-checked, but not the sender's. If the sender
-- was suspended between sending and acceptance, the pair still connected and a
-- framed discovery invite still materialised as an 'invited' participation
-- invited_by = <suspended sender>. Add a sender-suspension gate (generic error —
-- don't reveal the sender's state). (Scott 2026-09-09, 2nd adversarial pass.)
-- ============================================================================

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
  -- Don't connect to a sender who was suspended after sending the request.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_conv.request_sender_id AND suspended_at IS NOT NULL) THEN
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
