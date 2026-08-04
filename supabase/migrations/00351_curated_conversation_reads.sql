-- ============================================================================
-- 00351 — Curated conversation reads (brique 1, phase 1 of the messaging plan).
--
-- Replaces the client's four direct SELECTs on `conversations` with SECURITY
-- DEFINER RPCs so the base table can stop being directly readable (phase 2,
-- separate migration AFTER the client OTA propagates). The load-bearing rule:
-- the request SENDER can never distinguish pending / declined / block-cascaded
-- — get_conversation_state_with coalesces them all into 'pending', and no RPC
-- ever returns the raw status column. Closes the live leak found by the
-- design review (conversations_select_own exposed status via PostgREST).
--
-- Reads are auth-gated but NOT suspension-gated (suspension blocks writes;
-- a suspended user keeps seeing their own data — today's behavior).
-- ============================================================================

-- 1. Profile screen: relationship state with another user.
--    'active' | 'pending' (= pending_request OR declined, both sides) — no row = none.
CREATE OR REPLACE FUNCTION get_conversation_state_with(p_other_user_id UUID)
RETURNS TABLE (id UUID, state TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id,
         CASE WHEN c.status = 'active' THEN 'active' ELSE 'pending' END AS state
  FROM conversations c
  WHERE auth.uid() IS NOT NULL
    AND p_other_user_id IS NOT NULL
    AND c.user_1 = LEAST(auth.uid(), p_other_user_id)
    AND c.user_2 = GREATEST(auth.uid(), p_other_user_id)
$$;
REVOKE ALL ON FUNCTION get_conversation_state_with(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_conversation_state_with(UUID) TO authenticated;

-- 2. Messagerie list: my ACTIVE conversations + peer + last message (kills the
--    client-side N+1 as a bonus). Hidden-for-me rows excluded server-side.
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
         lm.content AS last_message_content,
         lm.sender_id AS last_message_sender_id,
         lm.metadata AS last_message_metadata
  FROM conversations c
  LEFT JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END
  LEFT JOIN LATERAL (
    SELECT m.content, m.sender_id, m.metadata
    FROM private_messages m
    WHERE m.conversation_id = c.id AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC
    LIMIT 1
  ) lm ON TRUE
  WHERE auth.uid() IS NOT NULL
    AND c.status = 'active'
    AND ((c.user_1 = auth.uid() AND NOT COALESCE(c.hidden_by_user_1, false))
      OR (c.user_2 = auth.uid() AND NOT COALESCE(c.hidden_by_user_2, false)))
  ORDER BY c.last_message_at DESC NULLS LAST
$$;
REVOKE ALL ON FUNCTION get_my_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_conversations() TO authenticated;

-- 3. Demandes (received): pending requests where I'm the recipient. Expiry
--    filtered server-side; the expiry column itself is never returned.
CREATE OR REPLACE FUNCTION get_pending_contact_requests()
RETURNS TABLE (
  id UUID,
  user_1 UUID,
  user_2 UUID,
  request_sender_id UUID,
  initiated_from TEXT,
  request_message TEXT,
  created_at TIMESTAMPTZ,
  sender_name TEXT,
  sender_avatar TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.user_1, c.user_2, c.request_sender_id, c.initiated_from,
         c.request_message, c.created_at,
         COALESCE(pp.display_name, '?') AS sender_name,
         pp.avatar_url AS sender_avatar
  FROM conversations c
  LEFT JOIN public_profiles pp ON pp.id = c.request_sender_id
  WHERE auth.uid() IS NOT NULL
    AND c.status = 'pending_request'
    AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
    AND c.request_sender_id IS DISTINCT FROM auth.uid()
    AND (c.request_expires_at IS NULL OR c.request_expires_at > NOW())
  ORDER BY c.created_at DESC
$$;
REVOKE ALL ON FUNCTION get_pending_contact_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_pending_contact_requests() TO authenticated;

-- 4. Conversation screen header: the peer of one of MY conversations.
--    No row = conversation missing or not mine; NULL profile fields = the
--    other account is gone/suspended (public_profiles filters them).
CREATE OR REPLACE FUNCTION get_conversation_peer(p_conversation_id UUID)
RETURNS TABLE (other_id UUID, display_name TEXT, avatar_url TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END AS other_id,
         pp.display_name, pp.avatar_url
  FROM conversations c
  LEFT JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = auth.uid() THEN c.user_2 ELSE c.user_1 END
  WHERE auth.uid() IS NOT NULL
    AND c.id = p_conversation_id
    AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
$$;
REVOKE ALL ON FUNCTION get_conversation_peer(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_conversation_peer(UUID) TO authenticated;
