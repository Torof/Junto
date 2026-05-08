-- Migration 00230: SECURITY DEFINER RPC for participant lists.
--
-- Bug: 00214 added `security_invoker = on` to the public_participants
-- view to fix the row-level visibility regression introduced in
-- 00112 / 00127 (where the view bypassed RLS via owner privileges,
-- letting any authenticated user read every participation row of
-- every activity). The fix re-applied the participations RLS via
-- the view — but the participations SELECT policy hasn't been
-- expanded since 00021 dropped the original recursive
-- creator/co-participant visibility check. Result: every user only
-- sees their own row through the view.
--
-- Symptom: the participant list on the activity detail (and the
-- transport summary on the same screen) showed only the caller's
-- own row. Creators were stuck on the 'soyez le 1er à rejoindre'
-- empty state because OrganizerCard filters their own row out
-- before deciding whether to render the avatar stack.
--
-- Fix: a SECURITY DEFINER RPC that does its own gating without
-- triggering the recursive-policy problem the original 00004 policy
-- had. The RPC:
--   1. Requires auth.uid().
--   2. Refuses suspended callers.
--   3. Loads the activity to learn the creator_id; refuses if
--      activity is missing.
--   4. Allows the call if caller is the creator OR an accepted
--      participant of the activity. Returns empty otherwise (no
--      RAISE — this is a read-only call and a non-member peeking
--      should just see no rows).
--   5. Returns every accepted participant row for the activity,
--      with the standard blocked-users filter (caller-side).
--
-- Same shape and column set as the public_participants view so the
-- two consumers (participation-service.getForActivity and
-- transport-service.getForActivity) can swap to the RPC with
-- minimal code change. The view itself stays in place — any
-- internal SECURITY DEFINER caller that already has a session
-- elevated past RLS keeps working.

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
  v_creator_id UUID;
  v_caller_accepted BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  SELECT a.creator_id INTO v_creator_id
  FROM activities a WHERE a.id = p_activity_id;
  IF v_creator_id IS NULL THEN RETURN; END IF;

  IF v_user_id <> v_creator_id THEN
    SELECT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id
        AND user_id = v_user_id
        AND status = 'accepted'
    ) INTO v_caller_accepted;
    IF NOT v_caller_accepted THEN RETURN; END IF;
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
