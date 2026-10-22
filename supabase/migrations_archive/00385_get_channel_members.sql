-- ============================================================================
-- 00385 — Channels: get_channel_members, so the creator's manage sheet can list
-- members and remove one (remove_channel_member already exists, 00383).
-- Roster is visible to members of the channel only. Creator listed first.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_channel_members(p_conversation_id UUID)
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  is_creator BOOLEAN, joined_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- Channel must exist; caller must be a member to see the roster.
  SELECT created_by INTO v_creator FROM channels WHERE conversation_id = p_conversation_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM conversation_members m
    WHERE m.conversation_id = p_conversation_id AND m.user_id = v_user_id
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT m.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         (m.user_id = v_creator) AS is_creator, m.joined_at
  FROM conversation_members m
  JOIN public_profiles pp ON pp.id = m.user_id
  WHERE m.conversation_id = p_conversation_id
  ORDER BY (m.user_id = v_creator) DESC, m.joined_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION get_channel_members(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_channel_members(UUID) TO authenticated;
