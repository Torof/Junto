-- Migration 00239: round-2 audit — Medium-tier DB fixes.
--
-- M4 — set_date_of_birth + accept_tos one-time checks ran without an
--      advisory lock. Two concurrent calls from the same user could
--      both pass the "not yet set" check and both UPDATE (last writer
--      wins on the column, but recalc / cascading effects could fire
--      twice). Add a per-user advisory lock for serial execution.
--
-- M5 — send_contact_request caps at 10 *pending* requests but has no
--      time-windowed rate limit. An aggressor can keep the cap full
--      by sending fresh ones as old ones expire (30-day window from
--      00221). Add a 5/day cap as belt-and-suspenders on top of the
--      pending-count cap. Locks share the same name as the existing
--      pending-count advisory.

-- ============================================================================
-- M4 — set_date_of_birth + accept_tos with per-user advisory lock
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
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET date_of_birth = p_date_of_birth WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION set_date_of_birth(DATE) FROM anon;
GRANT EXECUTE ON FUNCTION set_date_of_birth(DATE) TO authenticated;

CREATE OR REPLACE FUNCTION accept_tos()
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

  PERFORM pg_advisory_xact_lock(hashtext('accept_tos:' || auth.uid()::text));

  IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET accepted_tos_at = now(), accepted_privacy_at = now() WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_tos() FROM anon;
GRANT EXECUTE ON FUNCTION accept_tos() TO authenticated;

-- ============================================================================
-- M5 — send_contact_request: add 5/day daily cap on top of pending-count
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
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- New: 5 requests / 24h regardless of acceptance state. Caps the
  -- "send fresh as old expire" attack on top of the static 10-pending
  -- cap (which doesn't bound velocity).
  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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

REVOKE EXECUTE ON FUNCTION send_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION send_contact_request TO authenticated;
