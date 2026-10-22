-- Migration 00095: relax wall rate limit (1/min → 30/min)
-- The wall has evolved into a real chat: 1 message/minute prevents normal
-- back-and-forth. Since wall messages are already gated by accepted-
-- participant + activity-active checks, spam from outsiders is impossible.
-- 30/min keeps protection against client-side bugs (runaway double-taps)
-- without throttling actual conversation. Advisory lock pattern unchanged.

CREATE OR REPLACE FUNCTION send_wall_message(
  p_activity_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity_status TEXT;
  v_message_id UUID;
  v_recent_count INTEGER;
  v_clean_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT status INTO v_activity_status FROM activities WHERE id = p_activity_id;
  IF v_activity_status IS NULL OR v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id
      AND user_id = v_user_id
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rate limit: 30 messages per minute per activity (chat-friendly)
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_wall_' || p_activity_id::text));

  SELECT count(*) INTO v_recent_count
  FROM wall_messages
  WHERE activity_id = p_activity_id
    AND user_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 30 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_content := regexp_replace(trim(p_content), '<[^>]*>', '', 'g');

  INSERT INTO wall_messages (activity_id, user_id, content, created_at)
  VALUES (p_activity_id, v_user_id, v_clean_content, now())
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_wall_message FROM anon;
GRANT EXECUTE ON FUNCTION send_wall_message TO authenticated;
