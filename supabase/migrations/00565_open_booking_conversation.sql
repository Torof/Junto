-- The pro can write to a client from a booking — pending or confirmed —
-- (Scott 2026-11-01, option B): the client's booking request is their consent
-- to talk; a guide often checks the level before saying yes. Until now the
-- thread only opened on accept_booking.
--
-- Same DM handling as accept_booking (00418 H2): a reactivated row is
-- RETAGGED 'booking' and its social-request fields purged — a booking never
-- turns into a social contact. No seed message: the pro writes first.
-- No rate limit: the pro can only reach clients who booked them, and booking
-- requests are capped on the client side (create_booking).

CREATE OR REPLACE FUNCTION public.open_booking_conversation(p_booking_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Approved, non-suspended pro.
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT id, pro_id, client_id, status INTO v_bk
  FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk.id IS NULL
     OR v_bk.pro_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted')
     OR v_bk.client_id IS NULL THEN   -- manual booking: no client in the app
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
       OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_bk.client_id < v_user_id THEN v_u1 := v_bk.client_id; v_u2 := v_user_id;
  ELSE v_u1 := v_user_id; v_u2 := v_bk.client_id; END IF;

  SELECT id INTO v_conversation_id FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES ('dm', v_u1, v_u2, v_user_id, 'active', 'booking', now(), now())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations
  SET status = 'active',
      initiated_from = CASE WHEN status != 'active' THEN 'booking' ELSE initiated_from END,
      request_sender_id = CASE WHEN status != 'active' THEN NULL ELSE request_sender_id END,
      request_message   = CASE WHEN status != 'active' THEN NULL ELSE request_message END,
      pending_activity_id = CASE WHEN status != 'active' THEN NULL ELSE pending_activity_id END,
      request_expires_at = CASE WHEN status != 'active' THEN NULL ELSE request_expires_at END
  WHERE id = v_conversation_id;
  -- The pro is about to write: their hidden copy comes back. The client's
  -- reappears with the first message, like any DM.
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND user_id = v_user_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN v_conversation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.open_booking_conversation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.open_booking_conversation(uuid) TO authenticated;
