-- Migration 00158: collapse new_message pushes by conversation.
--
-- The three message-sending paths (send_private_message,
-- share_activity_message, share_trace_message) each construct a direct
-- push payload via net.http_post and never set collapseId. Result: when
-- a conversation has rapid back-and-forth (5 messages in 30 seconds),
-- the recipient sees 5 stacked notifications in their tray, all from
-- the same person.
--
-- Adding collapseId = 'message-{conversation_id}' tells the Expo Push
-- API (and downstream FCM/APNs) to replace the prior visual for the
-- same key. Each message still buzzes (intentional — they're new
-- messages), but only the latest visual stays in the tray. Mirrors what
-- modern messengers do.
--
-- Each function below is recreated VERBATIM from its current latest
-- definition (mig 00082 / 00101 / 00111) with the sole addition of one
-- collapseId field in the push body. No other behavior change.

-- ============================================================================
-- 1. send_private_message — verbatim from mig 00082 + collapseId
-- ============================================================================
CREATE OR REPLACE FUNCTION send_private_message(
  p_conversation_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conversation RECORD;
  v_other_user_id UUID;
  v_message_id UUID;
  v_recent_count INTEGER;
  v_sender_name TEXT;
  v_secret TEXT;
  v_clean_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2, status INTO v_conversation FROM conversations WHERE id = p_conversation_id;
  IF v_conversation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conversation.status != 'active' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conversation.user_1 AND v_user_id != v_conversation.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conversation.user_1 THEN v_conversation.user_2 ELSE v_conversation.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dm_' || p_conversation_id::text));

  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_content := regexp_replace(trim(p_content), '<[^>]*>', '', 'g');

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, v_clean_content, now())
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', 'Tu as reçu un message',
        'data', jsonb_build_object('conversation_id', p_conversation_id, 'type', 'new_message'),
        'collapseId', 'message-' || p_conversation_id::text
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_private_message FROM anon;
GRANT EXECUTE ON FUNCTION send_private_message TO authenticated;

-- ============================================================================
-- 2. share_activity_message — verbatim from mig 00101 + collapseId
-- ============================================================================
CREATE OR REPLACE FUNCTION share_activity_message(
  p_conversation_id UUID,
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other_user_id UUID;
  v_activity RECORD;
  v_can_see BOOLEAN;
  v_recent_count INTEGER;
  v_message_id UUID;
  v_content TEXT;
  v_sender_name TEXT;
  v_secret TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2, status INTO v_conv
  FROM conversations
  WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'active' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conv.user_1 THEN v_conv.user_2 ELSE v_conv.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, title, visibility, deleted_at INTO v_activity
  FROM activities
  WHERE id = p_activity_id;
  IF v_activity IS NULL OR v_activity.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_can_see := v_activity.visibility = 'public'
    OR EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id
        AND user_id = v_user_id
        AND status IN ('accepted', 'pending')
    );
  IF NOT v_can_see THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_activity'));
  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE sender_id = v_user_id
    AND metadata->>'type' = 'shared_activity'
    AND created_at > NOW() - INTERVAL '1 minute';
  IF v_recent_count >= 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_content := 'Hé, regarde cette sortie 👀' || E'\n« ' || v_activity.title || ' »';

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    p_conversation_id,
    v_user_id,
    v_other_user_id,
    v_content,
    jsonb_build_object(
      'type', 'shared_activity',
      'activity_id', p_activity_id
    ),
    NOW()
  )
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = NOW() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', '📍 ' || v_activity.title,
        'data', jsonb_build_object(
          'conversation_id', p_conversation_id,
          'activity_id', p_activity_id,
          'type', 'shared_activity'
        ),
        'collapseId', 'message-' || p_conversation_id::text
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION share_activity_message FROM anon;
GRANT EXECUTE ON FUNCTION share_activity_message TO authenticated;

-- ============================================================================
-- 3. share_trace_message — verbatim from mig 00111 + collapseId
-- ============================================================================
CREATE OR REPLACE FUNCTION share_trace_message(
  p_conversation_id UUID,
  p_trace_geojson JSONB,
  p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other_user_id UUID;
  v_recent_count INTEGER;
  v_message_id UUID;
  v_clean_name TEXT;
  v_sender_name TEXT;
  v_secret TEXT;
  v_coord_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2, status INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conv.user_1 THEN v_conv.user_2 ELSE v_conv.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_trace_geojson->'coordinates') AS coord
    WHERE jsonb_typeof(coord) != 'array'
       OR jsonb_array_length(coord) < 2
       OR jsonb_array_length(coord) > 3
       OR jsonb_typeof(coord->0) != 'number'
       OR jsonb_typeof(coord->1) != 'number'
       OR (jsonb_array_length(coord) = 3 AND jsonb_typeof(coord->2) != 'number')
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_trace'));
  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE sender_id = v_user_id
    AND metadata->>'type' = 'shared_trace'
    AND created_at > NOW() - INTERVAL '1 minute';
  IF v_recent_count >= 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    p_conversation_id, v_user_id, v_other_user_id, '📍 ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson),
    NOW()
  )
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = NOW() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', '📍 ' || v_clean_name,
        'data', jsonb_build_object('conversation_id', p_conversation_id, 'type', 'shared_trace'),
        'collapseId', 'message-' || p_conversation_id::text
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION share_trace_message FROM anon;
GRANT EXECUTE ON FUNCTION share_trace_message TO authenticated;
