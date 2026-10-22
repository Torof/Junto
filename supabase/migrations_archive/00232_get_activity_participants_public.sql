-- Migration 00232: open `get_activity_participants` to any auth user.
--
-- Per product decision (Scott, 2026-05-14): the participants section
-- and transport list on the activity detail are part of the
-- "what is this outing about" context — they MUST be visible to anyone
-- who can see the activity, not gated behind membership. Knowing who's
-- already in, and what transport they offer, is essential pre-join info.
--
-- Migration 00230 had locked this RPC to creator-or-accepted-participant
-- because the participations RLS only exposes the caller's own row. The
-- RPC is SECURITY DEFINER so it can bypass that RLS safely with its own
-- gating — we just relax the gate.
--
-- Authorization chain (this version):
--   1. auth.uid() required.
--   2. Caller must not be suspended.
--   3. Activity must exist.
--   4. (Returns every accepted participant row for the activity.)
--   5. Caller's blocked_users filter still applied — anyone the caller
--      has blocked is hidden from their view.
--
-- Dropped check: "caller must be creator OR accepted participant".
-- Public-profile data (display_name, avatar_url) is already public via
-- the public_profiles view; transport_* columns are semi-public by
-- product decision; confirmed_present is reputation-adjacent (tied to
-- the visible reliability score) and acceptable to expose.

CREATE OR REPLACE FUNCTION get_activity_participants(p_activity_id UUID)
RETURNS TABLE (
  participation_id UUID,
  activity_id UUID,
  user_id UUID,
  status TEXT,
  created_at TIMESTAMPTZ,
  left_at TIMESTAMPTZ,
  confirmed_present BOOLEAN,
  transport_type TEXT,
  transport_seats SMALLINT,
  transport_from_name TEXT,
  transport_departs_at TIMESTAMPTZ,
  display_name TEXT,
  avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    p.confirmed_present,
    p.transport_type,
    p.transport_seats,
    p.transport_from_name,
    p.transport_departs_at,
    pp.display_name,
    pp.avatar_url
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
  ORDER BY p.created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_participants FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_participants TO authenticated;
