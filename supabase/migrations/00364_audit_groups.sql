-- ============================================================================
-- 00364 — Post-code audit: group hardening.
--   • create_group: require ≥2 RETAINED members (min 3 total) — a 2-person group
--     is a block-resistant DM; a duo should use a DM.
--   • add_group_member / leave_group: take a CONVERSATION-scoped advisory lock so
--     membership mutations serialize (fixes the cap-20 race — the caller-keyed
--     lock didn't serialize two different adders — and the empty-cleanup race).
-- ============================================================================

CREATE OR REPLACE FUNCTION create_group(p_name TEXT, p_icon TEXT, p_member_ids UUID[])
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_n INTEGER;
  v_daily INTEGER;
  v_target UUID;
  v_retained UUID[] := '{}';
  v_conv_id UUID;
  v_caller_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := regexp_replace(trim(COALESCE(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_clean_name) < 1 OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;
  IF p_icon IS NOT NULL AND (char_length(p_icon) < 1 OR char_length(p_icon) > 8 OR p_icon ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;

  v_n := array_length(p_member_ids, 1);
  IF p_member_ids IS NULL OR v_n IS NULL OR v_n < 2 THEN
    RAISE EXCEPTION 'junto.group_min_members';  -- min 3 total (creator + 2)
  END IF;
  IF v_n > 19 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  SELECT count(*) INTO v_daily FROM conversations
  WHERE type = 'group' AND created_by = v_user_id
    AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.group_rate_limit'; END IF;

  FOR v_target IN SELECT DISTINCT unnest(p_member_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users bu
      JOIN unnest(v_retained) AS r(id) ON TRUE
      WHERE (bu.blocker_id = v_target AND bu.blocked_id = r.id)
         OR (bu.blocker_id = r.id AND bu.blocked_id = v_target)
    );
    v_retained := array_append(v_retained, v_target);
  END LOOP;

  -- ≥2 retained → group of ≥3 with the creator. A 1-retained result would be a
  -- DM-equivalent 2-person group; refuse (count only — no cause leaked).
  IF array_length(v_retained, 1) IS NULL OR array_length(v_retained, 1) < 2 THEN
    RAISE EXCEPTION 'junto.group_min_members';
  END IF;

  INSERT INTO conversations (type, status, name, icon, created_by, created_at, last_message_at)
  VALUES ('group', 'active', v_clean_name, p_icon, v_user_id, now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  SELECT v_conv_id, r.id, v_user_id, now() FROM unnest(v_retained) AS r(id);

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  FOR v_target IN SELECT unnest(v_retained) LOOP
    PERFORM create_notification(
      v_target, 'group_added',
      coalesce(v_caller_name, 'Quelqu''un') || ' t''a ajouté au groupe',
      v_clean_name, jsonb_build_object('conversation_id', v_conv_id)
    );
  END LOOP;

  RETURN v_conv_id;
END;
$$;
REVOKE ALL ON FUNCTION create_group(TEXT, TEXT, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_group(TEXT, TEXT, UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION add_group_member(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_member_count INTEGER;
  v_added_today INTEGER;
  v_caller_name TEXT;
  v_group_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT name INTO v_group_name FROM conversations
  WHERE id = p_conversation_id AND type = 'group';
  IF v_group_name IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_user_id IS NULL OR p_user_id = v_user_id
     OR NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF private.is_conversation_member(p_conversation_id, p_user_id) THEN RETURN; END IF;

  -- Caller lock (30/24h add-rate) + CONVERSATION lock (cap-20 + membership race).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_group_members'));

  SELECT count(*) INTO v_member_count FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_member_count >= 20 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  SELECT count(*) INTO v_added_today FROM conversation_members
  WHERE added_by = v_user_id AND joined_at > now() - INTERVAL '24 hours';
  IF v_added_today >= 30 THEN RAISE EXCEPTION 'junto.group_add_rate_limit'; END IF;

  IF NOT private.is_messaging_eligible(v_user_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users bu
    JOIN conversation_members cm ON cm.conversation_id = p_conversation_id
    WHERE (bu.blocker_id = p_user_id AND bu.blocked_id = cm.user_id)
       OR (bu.blocker_id = cm.user_id AND bu.blocked_id = p_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, p_user_id, v_user_id, now())
  ON CONFLICT DO NOTHING;

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_user_id, 'group_added',
    coalesce(v_caller_name, 'Quelqu''un') || ' t''a ajouté au groupe',
    v_group_name, jsonb_build_object('conversation_id', p_conversation_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION add_group_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_group_member(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION leave_group(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_left INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conversation_id AND type = 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize with adds/other leavers so the empty-cleanup can't race.
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_group_members'));

  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = v_user_id;

  SELECT count(*) INTO v_left FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_left = 0 THEN
    DELETE FROM conversations WHERE id = p_conversation_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION leave_group(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION leave_group(UUID) TO authenticated;
