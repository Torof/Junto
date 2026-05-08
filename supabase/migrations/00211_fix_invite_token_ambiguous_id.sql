-- Migration 00211: fix ambiguous `id` in get_activity_by_invite_token.
--
-- Same 42702 bug we caught on get_activity_seat_assignments (00210).
-- The function's RETURNS TABLE declares `id` as the first OUT column;
-- the suspension check `SELECT 1 FROM users WHERE id = v_user_id …`
-- has a bare `id` that PL/pgSQL flags as ambiguous (could be the OUT
-- parameter or users.id) and raises 42702 at call time:
--
--   ERROR: column reference "id" is ambiguous
--
-- Result: every authenticated invite-link tap fails inside the auth
-- chain. The client (activity-service.getByInviteToken) swallows
-- the error and shows nothing — broken deep-link UX.
--
-- Fix: alias the users table and qualify columns. Body otherwise
-- identical to 00045.

CREATE OR REPLACE FUNCTION get_activity_by_invite_token(
  p_token UUID
)
RETURNS TABLE (
  id UUID,
  creator_id UUID,
  sport_id UUID,
  title TEXT,
  description TEXT,
  level TEXT,
  max_participants INTEGER,
  starts_at TIMESTAMPTZ,
  duration INTERVAL,
  visibility TEXT,
  status TEXT,
  lng FLOAT,
  lat FLOAT,
  creator_name TEXT,
  creator_avatar TEXT,
  sport_key TEXT,
  sport_icon TEXT,
  sport_category TEXT,
  participant_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Invite token brute-force protection:
  -- UUID v4 has 2^122 bits of entropy — statistically impossible to guess
  -- Supabase API has built-in per-IP rate limiting

  RETURN QUERY
  SELECT
    a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.status,
    ST_X(a.location_start::geometry)::FLOAT AS lng,
    ST_Y(a.location_start::geometry)::FLOAT AS lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.invite_token = p_token
    AND a.deleted_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_by_invite_token FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_by_invite_token TO authenticated;
