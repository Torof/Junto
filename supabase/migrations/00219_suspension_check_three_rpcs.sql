-- Migration 00219: add the standard suspension check to three RPCs
-- that had auth.uid() but missed the `users.suspended_at IS NULL`
-- gate. From the parallel security audit MINOR list.
--
-- Affected:
--   - accept_contact_request — a suspended user could accept a
--     pending contact request and start a conversation.
--   - register_push_token — a suspended user could rotate their
--     push token (clear_push_token_on_suspension trigger only fires
--     on the UPDATE OF suspended_at NULL→NOT NULL transition; an
--     already-suspended user could re-register).
--   - get_my_active_presence_activities — a suspended user kept
--     getting presence activities to validate via the foreground
--     geo watcher (silent leak of activities they shouldn't be
--     coordinating).
--
-- Bodies otherwise identical to 00117 / 00122 / 00147.

-- ============================================================================
-- 1. accept_contact_request
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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_conv.request_sender_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_sender_id := v_conv.request_sender_id;

  UPDATE conversations
  SET status = 'active', request_expires_at = NULL
  WHERE id = p_conversation_id;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_sender_id, v_user_id, v_conv.request_message, v_conv.created_at);

  PERFORM create_notification(
    v_sender_id,
    'contact_request_accepted',
    'Demande acceptée',
    '',
    jsonb_build_object('conversation_id', p_conversation_id)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_contact_request TO authenticated;

-- ============================================================================
-- 2. register_push_token
-- ============================================================================

CREATE OR REPLACE FUNCTION register_push_token(
  p_token TEXT,
  p_device_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_token IS NULL OR char_length(p_token) < 20 OR char_length(p_token) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_token !~ '^Exp(o|onent)PushToken\[.+\]$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM push_tokens WHERE token = p_token AND user_id != v_user_id;

  IF p_device_id IS NOT NULL THEN
    DELETE FROM push_tokens
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND token != p_token;
    INSERT INTO push_tokens (user_id, token, device_id)
      VALUES (v_user_id, p_token, p_device_id)
      ON CONFLICT (user_id, token)
      DO UPDATE SET device_id = EXCLUDED.device_id;
  ELSE
    INSERT INTO push_tokens (user_id, token)
      VALUES (v_user_id, p_token)
      ON CONFLICT (user_id, token) DO NOTHING;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION register_push_token FROM anon;
GRANT EXECUTE ON FUNCTION register_push_token TO authenticated;

-- ============================================================================
-- 3. get_my_active_presence_activities
-- ============================================================================

CREATE OR REPLACE FUNCTION get_my_active_presence_activities()
RETURNS TABLE (
  activity_id UUID,
  title TEXT,
  starts_at TIMESTAMPTZ,
  duration INTERVAL,
  start_lng FLOAT,
  start_lat FLOAT,
  meeting_lng FLOAT,
  meeting_lat FLOAT,
  end_lng FLOAT,
  end_lat FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    a.id AS activity_id,
    a.title,
    a.starts_at,
    a.duration,
    ST_X(a.location_start::geometry)::float AS start_lng,
    ST_Y(a.location_start::geometry)::float AS start_lat,
    ST_X(a.location_meeting::geometry)::float AS meeting_lng,
    ST_Y(a.location_meeting::geometry)::float AS meeting_lat,
    ST_X(a.location_end::geometry)::float AS end_lng,
    ST_Y(a.location_end::geometry)::float AS end_lat
  FROM activities a
  JOIN participations p ON p.activity_id = a.id
  WHERE p.user_id = v_user_id
    AND p.status = 'accepted'
    AND p.confirmed_present IS NULL
    AND a.requires_presence = TRUE
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
    AND now() >= a.starts_at - INTERVAL '2 hours'
    AND now() <= a.starts_at + INTERVAL '15 minutes';
END;
$$;

REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities FROM anon;
GRANT EXECUTE ON FUNCTION get_my_active_presence_activities TO authenticated;
