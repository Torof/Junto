-- Migration 00072: connection request system
-- Gates ALL first-time DMs behind an accept/decline flow. No exceptions
-- (co-participants use the activity group chat for coordination).
-- Requests appear in Messagerie as a "Demandes" section.

-- ============================================================================
-- 1. Add status + source columns to conversations
-- ============================================================================
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('pending_request', 'active', 'declined')),
  ADD COLUMN IF NOT EXISTS initiated_from TEXT
    CHECK (initiated_from IS NULL OR initiated_from IN ('profile', 'discovery', 'transport')),
  ADD COLUMN IF NOT EXISTS request_sender_id UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS request_message TEXT,
  ADD COLUMN IF NOT EXISTS request_expires_at TIMESTAMPTZ;

-- ============================================================================
-- 2. send_contact_request — creates a pending conversation with message
-- ============================================================================
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_target_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_user_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Check blocked (either direction)
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Ordered pair for conversation uniqueness
  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  -- Check for existing conversation (any status)
  SELECT id INTO v_conversation_id
  FROM conversations
  WHERE user_1 = v_user_1 AND user_2 = v_user_2;

  IF v_conversation_id IS NOT NULL THEN
    -- If active conversation already exists, return it
    IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conversation_id AND status = 'active') THEN
      RETURN v_conversation_id;
    END IF;
    -- If pending or declined, block (no re-sending)
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rate limit: max 10 pending requests per sender
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));
  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE status = 'pending_request'
    AND ((user_1 = v_user_id) OR (user_2 = v_user_id))
    AND initiated_from IS NOT NULL;
  IF v_pending_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Validate message
  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Create pending conversation
  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'pending_request', p_source, v_user_id, trim(p_message), NOW() + INTERVAL '30 days', NOW(), NOW())
  RETURNING id INTO v_conversation_id;

  -- Notify the target (include sender name for context)
  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    p_target_user_id,
    'contact_request',
    (SELECT display_name FROM public_profiles WHERE id = v_user_id) || ' souhaite te contacter',
    '',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'type', 'contact_request'),
    NOW()
  );

  RETURN v_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION send_contact_request TO authenticated;

-- ============================================================================
-- 3. accept_contact_request — flips to active, creates first message
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
  v_sender_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only the recipient can accept (not the sender)
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_sender_id := v_conv.request_sender_id;

  -- Flip to active
  UPDATE conversations
  SET status = 'active', request_expires_at = NULL
  WHERE id = p_conversation_id;

  -- Insert the request message as the first real message
  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_sender_id, v_user_id, v_conv.request_message, v_conv.created_at);

  -- Notify the sender that their request was accepted
  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    v_sender_id,
    'contact_request_accepted',
    'Demande acceptée',
    '',
    jsonb_build_object('conversation_id', p_conversation_id, 'type', 'contact_request_accepted'),
    NOW()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_contact_request TO authenticated;

-- ============================================================================
-- 4. decline_contact_request — silent, marks declined
-- ============================================================================
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
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE conversations
  SET status = 'declined'
  WHERE id = p_conversation_id;

  -- No notification to sender (silent decline)
END;
$$;

REVOKE EXECUTE ON FUNCTION decline_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_contact_request TO authenticated;

-- ============================================================================
-- 5. cancel_contact_request — sender cancels their own pending request
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_contact_request(
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
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM conversations WHERE id = p_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION cancel_contact_request TO authenticated;

-- ============================================================================
-- 6. Block cascade: if A blocks B, decline any pending request between them
-- ============================================================================
CREATE OR REPLACE FUNCTION cascade_block_to_requests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  IF NEW.blocker_id < NEW.blocked_id THEN
    v_u1 := NEW.blocker_id; v_u2 := NEW.blocked_id;
  ELSE
    v_u1 := NEW.blocked_id; v_u2 := NEW.blocker_id;
  END IF;

  UPDATE conversations
  SET status = 'declined'
  WHERE user_1 = v_u1 AND user_2 = v_u2
    AND status = 'pending_request';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_cascade_requests ON blocked_users;
CREATE TRIGGER trg_block_cascade_requests
  AFTER INSERT ON blocked_users
  FOR EACH ROW
  EXECUTE FUNCTION cascade_block_to_requests();
