-- ============================================================================
-- 00356 — Unified messaging: group functions (brique 2, part 4 — validated lot ②).
--
-- Eligibility (Scott arbitrage, hardened post-review): a target is addable iff
--   - the pair has a DM conversation AND it is 'active'  (mutual connection), OR
--   - the pair has NO conversation row at all AND they are HARDENED recent
--     partners: a shared outing ≤180 days old, activity alive (not cancelled/
--     expired/deleted), both sides accepted, and the CALLER's own presence was
--     validated (confirmed_present) — an edge you cannot mint with a drive-by
--     join (design-review C2 fix).
-- A pair with a pending/declined conversation is NEVER eligible (a declined
-- request cannot be bypassed by a 2-person group — design-review C1 fix).
-- Per-target failures are SILENT with merged causes (no oracles).
-- ============================================================================

-- ---------- eligibility helper ----------
CREATE OR REPLACE FUNCTION private.is_messaging_eligible(p_caller UUID, p_target UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.type = 'dm'
        AND c.user_1 = LEAST(p_caller, p_target)
        AND c.user_2 = GREATEST(p_caller, p_target)
    ) THEN COALESCE((
      SELECT c.status = 'active' FROM conversations c
      WHERE c.type = 'dm'
        AND c.user_1 = LEAST(p_caller, p_target)
        AND c.user_2 = GREATEST(p_caller, p_target)
    ), false)
    ELSE EXISTS (
      SELECT 1
      FROM participations pc
      JOIN participations pt ON pt.activity_id = pc.activity_id
      JOIN activities a ON a.id = pc.activity_id
      WHERE pc.user_id = p_caller AND pc.status = 'accepted' AND pc.confirmed_present = true
        AND pt.user_id = p_target AND pt.status = 'accepted'
        AND a.deleted_at IS NULL
        AND a.status NOT IN ('cancelled', 'expired')
        AND a.starts_at <= now()
        AND a.starts_at > now() - INTERVAL '180 days'
    )
  END;
$$;
REVOKE ALL ON FUNCTION private.is_messaging_eligible(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_messaging_eligible(UUID, UUID) TO authenticated;

-- ---------- create_group ----------
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
  IF p_member_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_n > 19 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  -- Serialize the caller's group writes: creation rate + add-rate share the lock.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  SELECT count(*) INTO v_daily FROM conversations
  WHERE type = 'group' AND created_by = v_user_id
    AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.group_rate_limit'; END IF;

  -- Per-target silent filtering (merged causes — no oracle).
  FOR v_target IN SELECT DISTINCT unnest(p_member_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    -- Block against every already-retained member (a third party must not be
    -- able to put a blocked pair in the same room).
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users bu
      JOIN unnest(v_retained) AS r(id) ON TRUE
      WHERE (bu.blocker_id = v_target AND bu.blocked_id = r.id)
         OR (bu.blocker_id = r.id AND bu.blocked_id = v_target)
    );
    v_retained := array_append(v_retained, v_target);
  END LOOP;

  IF array_length(v_retained, 1) IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
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
      v_target,
      'group_added',
      coalesce(v_caller_name, 'Quelqu''un') || ' t''a ajouté au groupe',
      v_clean_name,
      jsonb_build_object('conversation_id', v_conv_id)
    );
  END LOOP;

  RETURN v_conv_id;
END;
$$;
REVOKE ALL ON FUNCTION create_group(TEXT, TEXT, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_group(TEXT, TEXT, UUID[]) TO authenticated;

-- ---------- add_group_member ----------
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

  -- Already a member → silent idempotent no-op.
  IF private.is_conversation_member(p_conversation_id, p_user_id) THEN RETURN; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));

  SELECT count(*) INTO v_member_count FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_member_count >= 20 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  SELECT count(*) INTO v_added_today FROM conversation_members
  WHERE added_by = v_user_id AND joined_at > now() - INTERVAL '24 hours';
  IF v_added_today >= 30 THEN RAISE EXCEPTION 'junto.group_add_rate_limit'; END IF;

  -- Eligibility caller↔target (merged causes) + block vs EVERY current member.
  IF NOT private.is_messaging_eligible(v_user_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users bu
    JOIN conversation_members cm ON cm.conversation_id = p_conversation_id
    WHERE (bu.blocker_id = p_user_id AND bu.blocked_id = cm.user_id)
       OR (bu.blocker_id = cm.user_id AND bu.blocked_id = p_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, p_user_id, v_user_id, now())
  ON CONFLICT DO NOTHING;

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_user_id,
    'group_added',
    coalesce(v_caller_name, 'Quelqu''un') || ' t''a ajouté au groupe',
    v_group_name,
    jsonb_build_object('conversation_id', p_conversation_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION add_group_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_group_member(UUID, UUID) TO authenticated;

-- ---------- leave_group ----------
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

  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = v_user_id;
  -- Not a member → zero rows → silent no-op.

  SELECT count(*) INTO v_left FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_left = 0 THEN
    DELETE FROM conversations WHERE id = p_conversation_id; -- cascade wipes messages
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION leave_group(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION leave_group(UUID) TO authenticated;

-- ---------- rename_group ----------
CREATE OR REPLACE FUNCTION rename_group(p_conversation_id UUID, p_name TEXT, p_icon TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Creator only (MVP), and the creator must still be a member.
  IF NOT EXISTS (
    SELECT 1 FROM conversations
    WHERE id = p_conversation_id AND type = 'group' AND created_by = v_user_id
  ) OR NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := regexp_replace(trim(COALESCE(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_clean_name) < 1 OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;
  IF p_icon IS NOT NULL AND (char_length(p_icon) < 1 OR char_length(p_icon) > 8 OR p_icon ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;

  UPDATE conversations SET name = v_clean_name, icon = p_icon
  WHERE id = p_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION rename_group(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rename_group(UUID, TEXT, TEXT) TO authenticated;
