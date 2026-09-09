-- ============================================================================
-- 00406 — Audit phase 3 (#7): filter banned users out of get_channel.
--
-- search_channels already excludes channels where the caller is in
-- channel_bans; get_channel (direct-by-id) did not, so a removed/banned user
-- could still pull the channel's name, description, base, radius, and photo_url.
-- Add the same ban check for consistency. (Scott 2026-09-09, post-audit.)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_channel(p_conversation_id UUID)
RETURNS TABLE (
  conversation_id UUID, name TEXT, sport_key TEXT,
  base_lng DOUBLE PRECISION, base_lat DOUBLE PRECISION, base_label TEXT, radius_km INTEGER,
  description TEXT, photo_url TEXT, member_count INTEGER,
  is_member BOOLEAN, is_creator BOOLEAN, is_closed BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key,
         ST_X(c.base::geometry), ST_Y(c.base::geometry), c.base_label, c.radius_km,
         c.description, c.photo_url,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id),
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id),
         (c.created_by = v_user_id),
         (c.closed_at IS NOT NULL)
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.conversation_id = p_conversation_id
    AND NOT EXISTS (
      SELECT 1 FROM channel_bans b
      WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id
    );
END;
$$;
REVOKE ALL ON FUNCTION get_channel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_channel(UUID) TO authenticated;
