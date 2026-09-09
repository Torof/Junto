-- ============================================================================
-- 00399 — Store the geocoded transport departure coordinates (Scott 2026-09-05)
-- so a third party can open the point in their maps app. The departure name was
-- text-only; a geocoded pick now also carries lat/lng (free-text stays null).
--   • participations.transport_from_lat / _lng (nullable)
--   • set_participation_transport(+ p_transport_from_lat/_lng) — coords kept only
--     when a name is present, range-validated; cleared with the name.
--   • get_activity_participants returns the coords (drives the tappable card).
-- ============================================================================

ALTER TABLE participations
  ADD COLUMN IF NOT EXISTS transport_from_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS transport_from_lng DOUBLE PRECISION;

-- ---------- set_participation_transport (+ coords, reproduced from 00313) ----------
DROP FUNCTION IF EXISTS set_participation_transport(UUID, TEXT, SMALLINT, TEXT, TIMESTAMPTZ);
CREATE FUNCTION set_participation_transport(
  p_activity_id UUID,
  p_transport_type TEXT,
  p_transport_seats SMALLINT DEFAULT NULL,
  p_transport_from_name TEXT DEFAULT NULL,
  p_transport_departs_at TIMESTAMPTZ DEFAULT NULL,
  p_transport_from_lat DOUBLE PRECISION DEFAULT NULL,
  p_transport_from_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_from_name TEXT;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_transport_type IS NULL OR p_transport_type != 'car')
     AND EXISTS (
       SELECT 1 FROM seat_requests
       WHERE activity_id = p_activity_id
         AND driver_id = v_user_id
         AND status = 'accepted'
     ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_transport_type != 'car' AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  v_from_name := CASE
    WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
    THEN regexp_replace(trim(p_transport_from_name), '<[^>]*>', '', 'g')
    ELSE NULL
  END;

  -- Coords only meaningful with a name; range-validated; cleared with the name
  -- (a free-text departure has a name but no coords).
  IF v_from_name IS NULL THEN
    v_lat := NULL; v_lng := NULL;
  ELSE
    IF p_transport_from_lat IS NOT NULL AND p_transport_from_lat NOT BETWEEN -90 AND 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_transport_from_lng IS NOT NULL AND p_transport_from_lng NOT BETWEEN -180 AND 180 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_lat := p_transport_from_lat; v_lng := p_transport_from_lng;
  END IF;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = v_from_name,
      transport_departs_at = p_transport_departs_at,
      transport_from_lat = v_lat,
      transport_from_lng = v_lng
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;
REVOKE ALL ON FUNCTION set_participation_transport(UUID, TEXT, SMALLINT, TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_participation_transport(UUID, TEXT, SMALLINT, TEXT, TIMESTAMPTZ, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- ---------- get_activity_participants (+ coords, reproduced from 00316) ----------
DROP FUNCTION IF EXISTS get_activity_participants(UUID);
CREATE FUNCTION get_activity_participants(p_activity_id UUID)
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
  transport_from_lat DOUBLE PRECISION,
  transport_from_lng DOUBLE PRECISION,
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

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id
        )
      )
  ) THEN
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
    p.transport_from_lat,
    p.transport_from_lng,
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
REVOKE ALL ON FUNCTION get_activity_participants(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_activity_participants(UUID) TO authenticated;
