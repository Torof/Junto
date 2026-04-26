-- Migration 00100: share_activity_message — drop a typed message into an
-- existing conversation that points at an activity. The recipient sees
-- the metadata-driven "Voir l'activité" CTA below the bubble (rendering
-- already shipped via migration 00099).
--
-- Limited to existing conversations on purpose: the connection-request
-- gate prevents DM-ing strangers, so first-contact flow is unchanged.

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

  -- Sender must be allowed to see the activity. Public is fine; otherwise
  -- they need an accepted/pending participation. We don't gate on the
  -- recipient — RLS on the activity page handles their access.
  v_can_see := v_activity.visibility = 'public'
    OR EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id
        AND user_id = v_user_id
        AND status IN ('accepted', 'pending')
    );
  IF NOT v_can_see THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Rate limit: 1 share per minute per user (mirrors send_private_message).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_activity'));
  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE sender_id = v_user_id
    AND metadata->>'type' = 'shared_activity'
    AND created_at > NOW() - INTERVAL '1 minute';
  IF v_recent_count >= 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_content := '📍 ' || v_activity.title;

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

  -- Push notification to the recipient
  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx2amx0aHpkeWR6YXRjdnd3cml1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4MjUyNTMsImV4cCI6MjA5MTQwMTI1M30.cxBoxTF1eVNvA8kd_PhoLMmkdEbLvfyocm5kAWefEjM'
    ),
    body := jsonb_build_object(
      'user_id', v_other_user_id,
      'title', coalesce(v_sender_name, 'Junto'),
      'body', '📍 ' || v_activity.title,
      'data', jsonb_build_object(
        'conversation_id', p_conversation_id,
        'activity_id', p_activity_id,
        'type', 'shared_activity'
      )
    )
  );

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION share_activity_message FROM anon;
GRANT EXECUTE ON FUNCTION share_activity_message TO authenticated;
