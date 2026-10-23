-- A channel roster no longer lists the people the viewer blocked (lot B4 of the
-- 2026-10-23 sweep), like the outing participants list; their messages were
-- already hidden. The creator keeps the full roster to moderate.

CREATE OR REPLACE FUNCTION public.get_channel_members(p_conversation_id uuid)
 RETURNS TABLE(user_id uuid, display_name text, avatar_url text, reliability_tier text, is_creator boolean, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
    -- 00546: someone the viewer blocked leaves their roster (their messages are
    -- already hidden), except for the creator, who must still be able to ban them.
    AND (v_user_id = v_creator OR NOT EXISTS (
      SELECT 1 FROM blocked_users b WHERE b.blocker_id = v_user_id AND b.blocked_id = m.user_id))
  ORDER BY (m.user_id = v_creator) DESC, m.joined_at ASC;
END;
$function$;
