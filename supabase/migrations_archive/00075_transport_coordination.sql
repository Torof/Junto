-- Migration 00075: transport coordination on activities
-- Participants declare how they're getting there, from where, and
-- how many seats they have if driving. Visible to co-participants
-- in the Organization tab; summary visible publicly on Info tab.

-- ============================================================================
-- 1. Transport columns on participations
-- ============================================================================
ALTER TABLE participations
  ADD COLUMN IF NOT EXISTS transport_type TEXT
    CHECK (transport_type IS NULL OR transport_type IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other')),
  ADD COLUMN IF NOT EXISTS transport_seats SMALLINT
    CHECK (transport_seats IS NULL OR (transport_seats >= 0 AND transport_seats <= 8)),
  ADD COLUMN IF NOT EXISTS transport_from_name TEXT
    CHECK (transport_from_name IS NULL OR char_length(transport_from_name) BETWEEN 1 AND 100);

-- ============================================================================
-- 2. RPC: set own transport info for an activity
-- ============================================================================
CREATE OR REPLACE FUNCTION set_participation_transport(
  p_activity_id UUID,
  p_transport_type TEXT,
  p_transport_seats SMALLINT DEFAULT NULL,
  p_transport_from_name TEXT DEFAULT NULL
)
RETURNS VOID
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

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Must be an accepted participant
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Validate transport type
  IF p_transport_type NOT IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Seats only relevant for car/carpool
  IF p_transport_type NOT IN ('car', 'carpool') AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = CASE WHEN p_transport_from_name IS NOT NULL THEN trim(p_transport_from_name) ELSE NULL END
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;

REVOKE EXECUTE ON FUNCTION set_participation_transport FROM anon;
GRANT EXECUTE ON FUNCTION set_participation_transport TO authenticated;

-- ============================================================================
-- 3. RPC: get transport summary for an activity (public — no names)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_transport_summary(
  p_activity_id UUID
)
RETURNS TABLE (
  transport_type TEXT,
  count INTEGER,
  total_seats INTEGER,
  cities TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.transport_type,
    count(*)::int AS count,
    COALESCE(sum(p.transport_seats)::int, 0) AS total_seats,
    array_agg(DISTINCT p.transport_from_name) FILTER (WHERE p.transport_from_name IS NOT NULL) AS cities
  FROM participations p
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.transport_type IS NOT NULL
  GROUP BY p.transport_type
  ORDER BY count DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_transport_summary FROM anon;
GRANT EXECUTE ON FUNCTION get_transport_summary TO authenticated;

-- ============================================================================
-- 4. Update activity_participants view to include transport info
-- ============================================================================
DROP VIEW IF EXISTS activity_participants;

CREATE VIEW activity_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  p.left_reason,
  p.penalty_waived,
  p.transport_type,
  p.transport_seats,
  p.transport_from_name,
  a.creator_id,
  pp.display_name,
  pp.avatar_url,
  pp.sports,
  pp.levels_per_sport,
  u.reliability_score
FROM participations p
JOIN activities a ON a.id = p.activity_id
JOIN public_profiles pp ON pp.id = p.user_id
JOIN users u ON u.id = p.user_id
WHERE a.creator_id = auth.uid()
  AND p.user_id != a.creator_id
  AND p.status != 'removed'
  AND a.deleted_at IS NULL
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON activity_participants TO authenticated;

-- Also update public_participants to include transport (for accepted participants to see each other)
DROP VIEW IF EXISTS public_participants;

CREATE VIEW public_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.transport_type,
  p.transport_seats,
  p.transport_from_name,
  pp.display_name,
  pp.avatar_url
FROM participations p
JOIN public_profiles pp ON pp.id = p.user_id
WHERE p.status = 'accepted'
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON public_participants TO authenticated;
