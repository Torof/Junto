-- ============================================================================
-- 00372 — Audit H1/M2: distinguish social-contact DMs from logistics DMs.
--
-- One DM per pair is reused for everything (contact request, carpool, reply-to-
-- request). initiated_from records how it was FIRST created:
--   social contact  → 'profile' | 'discovery' | 'invite'  (a contact request)
--   logistics       → 'transport' (request_seat) | 'request_reply' (reply_to_request)
-- A "contact" is only a social connection. get_contacts + remove_connection now
-- act on social DMs only, so a carpool/reply thread is never listed as a contact
-- nor deletable by removing a contact (H1/M2). Extra guard: remove_connection
-- refuses while a live carpool ties the pair — deleting the thread would strand
-- the accepted seat + reservation. Adds the missing suspension check.
-- ============================================================================

-- get_contacts → social connections only.
CREATE OR REPLACE FUNCTION get_contacts()
RETURNS TABLE (id UUID, display_name TEXT, avatar_url TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT pp.id, pp.display_name, pp.avatar_url, c.created_at
  FROM conversations c
  JOIN public_profiles pp
    ON pp.id = CASE WHEN c.user_1 = v_user_id THEN c.user_2 ELSE c.user_1 END
  WHERE c.type = 'dm'
    AND c.status = 'active'
    AND c.initiated_from IN ('profile', 'discovery', 'invite')
    AND (c.user_1 = v_user_id OR c.user_2 = v_user_id)
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = c.user_1 AND b.blocked_id = c.user_2)
         OR (b.blocker_id = c.user_2 AND b.blocked_id = c.user_1)
    )
  ORDER BY c.created_at DESC;
END;
$$;

-- remove_connection → social DMs only; refuse while a live carpool ties the pair.
CREATE OR REPLACE FUNCTION remove_connection(p_other_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only a genuine social connection can be removed here — never a transport /
  -- request_reply logistics thread.
  SELECT id INTO v_conv_id
  FROM conversations
  WHERE type = 'dm'
    AND status = 'active'
    AND initiated_from IN ('profile', 'discovery', 'invite')
    AND ((user_1 = v_user_id AND user_2 = p_other_user_id)
      OR (user_1 = p_other_user_id AND user_2 = v_user_id));
  IF v_conv_id IS NULL THEN RETURN; END IF;

  -- A live carpool between the pair would be stranded (accepted seat + reservation)
  -- if we deleted the shared thread. Ask the user to settle it first.
  IF EXISTS (
    SELECT 1 FROM seat_requests s
    WHERE s.status IN ('pending', 'accepted')
      AND ((s.driver_id = v_user_id AND s.requester_id = p_other_user_id)
        OR (s.driver_id = p_other_user_id AND s.requester_id = v_user_id))
  ) THEN
    RAISE EXCEPTION 'junto.carpool_active';
  END IF;

  DELETE FROM conversations WHERE id = v_conv_id;
END;
$$;

REVOKE ALL ON FUNCTION remove_connection(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_connection(UUID) TO authenticated;
