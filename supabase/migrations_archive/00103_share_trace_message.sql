-- Migration 00103: share a GPX trace as a typed private message.
-- Trace is inlined as GeoJSON in private_messages.metadata so no Storage
-- bucket is needed (typical traces ≤ 10000 points fit comfortably). Auth
-- chain mirrors send_private_message + the rate limit (1/min).
-- The client renders metadata.type='shared_trace' bubbles as a tappable
-- chip that opens a map preview modal.

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

  -- Validate the GeoJSON shape: LineString with 2-10000 coords (mirrors the
  -- activities.trace_geojson CHECK constraint).
  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN
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
    p_conversation_id,
    v_user_id,
    v_other_user_id,
    '📍 ' || v_clean_name,
    jsonb_build_object(
      'type', 'shared_trace',
      'name', v_clean_name,
      'trace_geojson', p_trace_geojson
    ),
    NOW()
  )
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = NOW() WHERE id = p_conversation_id;

  -- Push to recipient
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
        'body', '📍 ' || v_clean_name,
        'data', jsonb_build_object(
          'conversation_id', p_conversation_id,
          'type', 'shared_trace'
        )
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION share_trace_message FROM anon;
GRANT EXECUTE ON FUNCTION share_trace_message TO authenticated;
