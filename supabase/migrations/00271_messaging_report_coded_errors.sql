-- Migration 00271: coded, user-actionable errors for messaging/report/onboarding RPCs.
--
-- Same SAFE/SENSITIVE split as 00268-00270. Bodies copied VERBATIM from their
-- latest definitions (send_wall_message 00095, send_private_message 00264,
-- share_trace_message 00158, send_contact_request 00239, create_report 00258,
-- set_date_of_birth 00239) — ONLY targeted RAISE strings on user-actionable
-- failures become 'junto.<code>'.
--
-- Blocking stays generic EVERYWHERE: a blocked sender must never learn the
-- block exists. Same for empty-content (UI-prevented tamper), conversation
-- state on contact re-request (anti-spam), and target/ownership checks.

-- ============================================================================
-- send_wall_message — wall_rate_limit. Empty content / participant / status generic.
-- ============================================================================
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
    RAISE EXCEPTION 'junto.wall_rate_limit';
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

-- ============================================================================
-- send_private_message — dm_rate_limit. Blocking / empty / membership generic.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.send_private_message(
  p_conversation_id UUID,
  p_content TEXT,
  p_reply_to_message_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_conversation RECORD;
  v_other_user_id UUID;
  v_message_id UUID;
  v_sender_name TEXT;
  v_secret TEXT;
  v_clean_content TEXT;
  v_reply_to UUID;
  v_recent_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
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

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_other_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rate limit: 15/min/conversation under advisory lock (mig 00264 —
  -- reinstated after being lost in the 00208/00209 reply rework; the
  -- historical 1/min was conversation-hostile and is deliberately NOT
  -- restored).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dm_' || p_conversation_id::text));

  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 15 THEN
    RAISE EXCEPTION 'junto.dm_rate_limit';
  END IF;

  v_clean_content := regexp_replace(trim(p_content), '<[^>]*>', '', 'g');

  v_reply_to := NULL;
  IF p_reply_to_message_id IS NOT NULL THEN
    SELECT id INTO v_reply_to
    FROM private_messages
    WHERE id = p_reply_to_message_id
      AND conversation_id = p_conversation_id
      AND deleted_at IS NULL;
  END IF;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, reply_to_message_id, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, v_clean_content, v_reply_to, now())
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;

  -- Push title sourced from public_profiles so a sender suspended
  -- mid-flight has their name elided to NULL → 'Junto' fallback.
  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
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

-- ============================================================================
-- share_trace_message — trace_rate_limit. GeoJSON validation (tamper) /
-- blocking / membership stay generic.
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
  IF v_recent_count >= 1 THEN RAISE EXCEPTION 'junto.trace_rate_limit'; END IF;

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

-- ============================================================================
-- send_contact_request — contact_request_pending_cap, contact_request_daily_cap.
-- Conversation-state re-request stays generic (anti-spam); blocking generic.
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
  v_daily_count INTEGER;
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

  -- Pending-count cap + daily cap. Both behind the same advisory lock
  -- so concurrent senders can't both squeeze past either bound.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE status = 'pending_request'
    AND ((user_1 = v_user_id) OR (user_2 = v_user_id))
    AND initiated_from IS NOT NULL;
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  -- New: 5 requests / 24h regardless of acceptance state. Caps the
  -- "send fresh as old expire" attack on top of the static 10-pending
  -- cap (which doesn't bound velocity).
  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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

-- ============================================================================
-- create_report — report_reason_too_short, report_already_filed,
-- report_rate_limit. target_type tamper / self-report / target-not-found generic.
-- ============================================================================
CREATE OR REPLACE FUNCTION create_report(
  p_target_type TEXT,
  p_target_id UUID,
  p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity', 'wall_message', 'private_message', 'pro_review', 'offering_review') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Sanitize first so the length check is on cleaned text.
  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');

  IF char_length(v_reason) < 10 THEN
    RAISE EXCEPTION 'junto.report_reason_too_short';
  END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'activity' AND NOT EXISTS (SELECT 1 FROM activities WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'wall_message' AND NOT EXISTS (SELECT 1 FROM wall_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'private_message' AND NOT EXISTS (SELECT 1 FROM private_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN
    RAISE EXCEPTION 'junto.report_already_filed';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));

  SELECT count(*) INTO v_hourly_count
  FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
    RAISE EXCEPTION 'junto.report_rate_limit';
  END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$$;

-- ============================================================================
-- set_date_of_birth — dob_underage. Already-set (idempotent) stays generic.
-- ============================================================================
CREATE OR REPLACE FUNCTION set_date_of_birth(p_date_of_birth DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize concurrent attempts to set DoB so two near-simultaneous
  -- calls can't both pass the "not yet set" check below.
  PERFORM pg_advisory_xact_lock(hashtext('set_dob:' || auth.uid()::text));

  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND date_of_birth IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years')::date THEN
    RAISE EXCEPTION 'junto.dob_underage';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET date_of_birth = p_date_of_birth WHERE id = auth.uid();
END;
$$;
