-- Migration 00172: allow transport_departs_at for non-car modes.
--
-- The previous version of set_participation_transport (00120) silently
-- nulled p_transport_departs_at whenever the type wasn't 'car' or
-- 'carpool'. The client now exposes a departure-time picker for every
-- mode (cyclist leaving Gap at 7h, walker setting off at 8h, transit
-- rider's train departure), so the DB must persist those values too.
--
-- Auth chain unchanged from 00120:
--   1. auth.uid() not null
--   2. user not suspended
--   3. activity status in (published, in_progress)
--   4. caller is an accepted participant
--   5. transport_type is in the closed enum
--   6. seats nulled for non-car (still gated)
--   7. departs_at bounded to [starts_at - 12h, starts_at + 6h]
--
-- Removed: the unconditional null-out of departs_at for non-car modes.
-- The bounds check (#7) keeps the value sane regardless of mode, so
-- this is strictly less restrictive without opening new abuse surface.

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
