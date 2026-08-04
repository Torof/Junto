-- ============================================================================
-- 00362 — Post-code audit: moderation on the unified store (HIGH, 3/4 reviewers).
--
-- After the wave, all messages live in `messages`. admin_remove_content still
-- soft-deleted `wall_messages` (dead for reads → takedown was a silent no-op),
-- and create_report validated targets against the legacy tables (new messages
-- unreportable). Add the spec'd `message` + `group` report targets and point
-- content removal at `messages` / `conversations`.
-- ============================================================================

ALTER TABLE reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_type_check
  CHECK (target_type IN ('user', 'activity', 'wall_message', 'private_message',
                         'pro_review', 'offering_review', 'message', 'group'));

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
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity', 'wall_message', 'private_message',
                           'pro_review', 'offering_review', 'message', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');
  IF char_length(v_reason) < 10 THEN RAISE EXCEPTION 'junto.report_reason_too_short'; END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Existence checks. 'message' / 'group' hit the unified store; the reporter
  -- must be a member of the conversation the content lives in (no probing).
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
  IF p_target_type = 'message' AND NOT EXISTS (
    SELECT 1 FROM messages m
    WHERE m.id = p_target_id AND m.deleted_at IS NULL
      AND private.is_conversation_member(m.conversation_id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'group' AND NOT EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = p_target_id AND c.type = 'group'
      AND private.is_conversation_member(c.id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN RAISE EXCEPTION 'junto.report_already_filed'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));
  SELECT count(*) INTO v_hourly_count FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.report_rate_limit'; END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;
  RETURN v_report_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION create_report FROM anon;
GRANT EXECUTE ON FUNCTION create_report TO authenticated;

CREATE OR REPLACE FUNCTION admin_remove_content(
  p_target_type TEXT,
  p_target_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_found BOOLEAN := false;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF p_target_type NOT IN ('activity', 'wall_message', 'message', 'group', 'pro_review', 'offering_review') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  IF p_target_type = 'activity' THEN
    UPDATE activities SET deleted_at = now(), updated_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type IN ('wall_message', 'message') THEN
    -- Unified store: reads come from `messages`. 'wall_message' kept for
    -- migrated ids (id is shared), 'message' for post-rebuild content.
    UPDATE messages SET deleted_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'group' THEN
    UPDATE conversations SET name = '[Groupe retiré]', icon = NULL
    WHERE id = p_target_id AND type = 'group';
    v_found := FOUND;
  ELSIF p_target_type = 'pro_review' THEN
    DELETE FROM pro_reviews WHERE id = p_target_id;
    v_found := FOUND;
  ELSIF p_target_type = 'offering_review' THEN
    DELETE FROM offering_reviews WHERE id = p_target_id;
    v_found := FOUND;
  END IF;

  IF NOT v_found THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM log_admin_action(v_admin, 'remove_content', p_target_type, p_target_id, v_reason, NULL);
END;
$$;
REVOKE EXECUTE ON FUNCTION admin_remove_content FROM anon;
GRANT EXECUTE ON FUNCTION admin_remove_content TO authenticated;
