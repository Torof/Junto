-- Migration 00221: strip HTML from send_contact_request.p_message.
-- From the parallel security audit MINOR list.
--
-- send_contact_request only `trim()`d the request message before
-- inserting it into `conversations.request_message`. The message
-- gets stored verbatim and surfaces in the recipient's request card
-- (and later in private_messages on accept, where the
-- strip_html_private_messages trigger sanitises — but the original
-- request_message in conversations stays raw).
--
-- Apply the same `regexp_replace('<[^>]*>', '', 'g')` used elsewhere
-- (send_private_message, request_seat) so the request_message never
-- carries HTML tags into the UI.
--
-- Body otherwise identical to 00117.

CREATE OR REPLACE FUNCTION send_contact_request(
  p_target_user_id UUID,
  p_message TEXT,
  p_source TEXT DEFAULT 'profile'
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
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_clean_message TEXT;
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

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  SELECT id INTO v_conversation_id
  FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;

  IF v_conversation_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conversation_id AND status = 'active') THEN
      RETURN v_conversation_id;
    END IF;
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));
  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE status = 'pending_request'
    AND ((user_1 = v_user_id) OR (user_2 = v_user_id))
    AND initiated_from IS NOT NULL;
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Strip HTML before insert (matches send_private_message / request_seat).
  v_clean_message := regexp_replace(trim(p_message), '<[^>]*>', '', 'g');

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'pending_request', p_source, v_user_id, v_clean_message, NOW() + INTERVAL '30 days', NOW(), NOW())
  RETURNING id INTO v_conversation_id;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' souhaite te contacter',
    '',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id)
  );

  RETURN v_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION send_contact_request TO authenticated;
