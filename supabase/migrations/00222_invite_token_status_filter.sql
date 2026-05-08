-- Migration 00222: get_activity_by_invite_token also filters out
-- cancelled / expired activities. From the parallel security audit
-- MINOR list.
--
-- Before: only `deleted_at IS NULL`. A cancelled or expired activity
-- still resolved on the invite link, returning title / description /
-- creator / coords / participant count to anyone with the URL —
-- low-impact (UUID-typed token, no enumeration), but inconsistent
-- with every other write RPC's `status IN ('published','in_progress')`
-- gate, and there's no UX scenario where opening a cancelled activity
-- from an old invite-link is desirable.
--
-- Body otherwise identical to 00211 (which fixed the 42702
-- ambiguous-id bug). Same alias-+-qualify pattern preserved.

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
    AND a.status IN ('published', 'in_progress')
    AND a.deleted_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_by_invite_token FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_by_invite_token TO authenticated;
