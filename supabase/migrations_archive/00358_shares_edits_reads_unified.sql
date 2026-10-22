-- ============================================================================
-- 00358 — Shares, edits, compat wrappers, unified reads (brique 2, part 6).
--
-- Everything now writes into `messages`. The legacy RPC names
-- (send_private_message / send_wall_message) become thin wrappers over
-- send_message so the CURRENT client keeps working without repointing its
-- send paths — only its reads move (00351 RPCs updated here + a new wall read).
-- Metadata stays server-built with the exact legacy keys the client renders.
-- ============================================================================

-- ---------- shared metadata sender (internal) ----------
CREATE OR REPLACE FUNCTION private.insert_rich_message(
  p_conversation_id UUID,
  p_sender_id UUID,
  p_content TEXT,
  p_metadata JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (p_conversation_id, p_sender_id, p_content, p_metadata)
  RETURNING id INTO v_id;
  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION private.insert_rich_message(UUID, UUID, TEXT, JSONB) FROM PUBLIC, anon, authenticated;

-- ---------- per-type send gate (internal, shared by shares) ----------
CREATE OR REPLACE FUNCTION private.assert_can_send(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv RECORD;
  v_other UUID;
BEGIN
  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT private.is_conversation_member(p_conversation_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = p_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = p_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = p_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.assert_can_send(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- ---------- share_activity_message (ported) ----------
CREATE OR REPLACE FUNCTION share_activity_message(
  p_conversation_id UUID,
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_can_see BOOLEAN;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  SELECT id, title, visibility, deleted_at, creator_id, is_demo INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Share gate: public → anyone; private → creator only; approval → participant.
  v_can_see := v_activity.visibility = 'public'
    OR v_activity.creator_id = v_user_id
    OR (
      v_activity.visibility = 'approval'
      AND EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = p_activity_id AND user_id = v_user_id
          AND status IN ('accepted', 'pending')
      )
    );
  IF NOT v_can_see THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_activity'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '📍 ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g'),
    jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION share_activity_message(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION share_activity_message(UUID, UUID) TO authenticated;

-- ---------- share_trace_message (ported + numeric bounds) ----------
CREATE OR REPLACE FUNCTION share_trace_message(
  p_conversation_id UUID,
  p_trace_geojson JSONB,
  p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_coord_count INTEGER;
  v_clean_name TEXT;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Schema + NUMERIC BOUNDS (design review: 1e300 coords sailed straight into
  -- the map renderer). lon/lat ranges, plausible elevation.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_trace_geojson->'coordinates') AS coord
    WHERE jsonb_typeof(coord) != 'array'
       OR jsonb_array_length(coord) < 2
       OR jsonb_array_length(coord) > 3
       OR jsonb_typeof(coord->0) != 'number'
       OR jsonb_typeof(coord->1) != 'number'
       OR (coord->>0)::numeric < -180 OR (coord->>0)::numeric > 180
       OR (coord->>1)::numeric < -90 OR (coord->>1)::numeric > 90
       OR (jsonb_array_length(coord) = 3 AND (
            jsonb_typeof(coord->2) != 'number'
            OR (coord->>2)::numeric < -500 OR (coord->>2)::numeric > 9000
       ))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_trace'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '🗺️ ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson)
  );
END;
$$;
REVOKE ALL ON FUNCTION share_trace_message(UUID, JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION share_trace_message(UUID, JSONB, TEXT) TO authenticated;

-- ---------- legacy send wrappers (current client keeps working post-OTA) ----------
CREATE OR REPLACE FUNCTION send_private_message(
  p_conversation_id UUID,
  p_content TEXT,
  p_reply_to_message_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT send_message(p_conversation_id, p_content, p_reply_to_message_id);
$$;
REVOKE ALL ON FUNCTION send_private_message(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_private_message(UUID, TEXT, UUID) TO authenticated;

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
  v_conv_id UUID;
BEGIN
  SELECT id INTO v_conv_id FROM conversations WHERE activity_id = p_activity_id;
  IF v_conv_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  RETURN send_message(v_conv_id, p_content);
END;
$$;
REVOKE ALL ON FUNCTION send_wall_message(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_wall_message(UUID, TEXT) TO authenticated;

-- ---------- edit / delete (unified, sender-only) ----------
CREATE OR REPLACE FUNCTION edit_message(p_message_id UUID, p_content TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE messages
  SET content = trim(p_content), edited_at = now()
  WHERE id = p_message_id AND sender_id = v_user_id
    AND deleted_at IS NULL AND metadata IS NULL; -- rich cards are not editable
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION edit_message(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION edit_message(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION delete_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE messages
  SET deleted_at = now()
  WHERE id = p_message_id AND sender_id = v_user_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION delete_message(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_message(UUID) TO authenticated;

-- ---------- reads: 00351 RPCs now read `messages`; DM-only list ----------
CREATE OR REPLACE FUNCTION get_my_conversations()
RETURNS TABLE (
  id UUID,
  user_1 UUID,
  user_2 UUID,
  status TEXT,
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  other_user_name TEXT,
  other_user_avatar TEXT,
  last_message_content TEXT,
  last_message_sender_id UUID,
  last_message_metadata JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.user_1, c.user_2, c.status, c.last_message_at, c.created_at,
         COALESCE(pp.display_name, '?') AS other_user_name,
         pp.avatar_url AS other_user_avatar,
         lm.content, lm.sender_id, lm.metadata
  FROM conversations c
  JOIN conversation_members me
    ON me.conversation_id = c.id AND me.user_id = auth.uid() AND me.hidden_at IS NULL
  LEFT JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC
    LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND c.type = 'dm'
    AND c.status = 'active'
  ORDER BY c.last_message_at DESC NULLS LAST
$$;
REVOKE ALL ON FUNCTION get_my_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_conversations() TO authenticated;

-- Wall read for the current client (activity chat tab): membership-gated via
-- the messages RLS equivalents, author filters included (wall parity).
CREATE OR REPLACE FUNCTION get_wall_messages(p_activity_id UUID)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  content TEXT,
  metadata JSONB,
  reply_to_message_id UUID,
  edited_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.id, m.sender_id, m.content, m.metadata, m.reply_to_message_id,
         m.edited_at, m.created_at
  FROM messages m
  JOIN conversations c ON c.id = m.conversation_id
  WHERE auth.uid() IS NOT NULL
    AND c.activity_id = p_activity_id
    AND m.deleted_at IS NULL
    AND private.is_conversation_member(c.id, auth.uid())
    AND private.message_author_visible(c.id, m.sender_id, auth.uid())
  ORDER BY m.created_at ASC
$$;
REVOKE ALL ON FUNCTION get_wall_messages(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_wall_messages(UUID) TO authenticated;
