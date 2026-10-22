-- Migration 00199: block driver flipping away from car/carpool while
-- accepted passengers exist.
--
-- Audit pass 1 finding N-2: when a driver changes transport_type to
-- a non-carrier mode (bike, on_foot, etc.) via set_participation_transport,
-- 00172 just nulls transport_seats. Accepted seat_requests stay
-- 'accepted'. A subsequent passenger cancel runs
-- COALESCE(transport_seats, 0) + 1 (00120 → 00195) — the driver
-- ends up showing 1 free seat on a bike. State-consistency drift.
--
-- Two options: (a) auto-decline accepted passengers, surprising the
-- driver; (b) block the flip while accepted passengers exist, asking
-- the driver to deal with their passengers first. (b) preserves
-- passenger trust (their seat doesn't vanish silently) and matches
-- the activity-level lock pattern in handle_activity_update where
-- privileged columns get pinned to OLD once participants exist.
--
-- Fix: in set_participation_transport, when the new transport_type
-- is NOT in (car, carpool) AND accepted seat_requests exist with
-- this user as driver, raise. The driver decides explicitly via
-- decline_seat_request before changing mode.

CREATE OR REPLACE FUNCTION set_participation_transport(
  p_activity_id UUID,
  p_transport_type TEXT,
  p_transport_seats SMALLINT DEFAULT NULL,
  p_transport_from_name TEXT DEFAULT NULL,
  p_transport_departs_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
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
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Block flipping away from car/carpool while accepted passengers
  -- exist. Driver must decline_seat_request each first.
  IF (p_transport_type IS NULL OR p_transport_type NOT IN ('car', 'carpool'))
     AND EXISTS (
       SELECT 1 FROM seat_requests
       WHERE activity_id = p_activity_id
         AND driver_id = v_user_id
         AND status = 'accepted'
     ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Seats are still car-only — non-car modes don't carry passengers.
  IF p_transport_type NOT IN ('car', 'carpool') AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  -- Departs_at bounded to a sane window around starts_at, regardless
  -- of mode. Cyclists/walkers/transit-riders can log a time too.
  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = CASE WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
                                 THEN trim(p_transport_from_name) ELSE NULL END,
      transport_departs_at = p_transport_departs_at
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;

REVOKE EXECUTE ON FUNCTION set_participation_transport FROM anon;
GRANT EXECUTE ON FUNCTION set_participation_transport TO authenticated;
