-- 00313: retire the redundant 'carpool' transport type
--
-- 'car' already IS carpooling — declaring a car with seats is the carpool
-- offer (Scott, 2026-07-10). The separate 'carpool' option was noise.
-- 1. Data: existing 'carpool' rows become 'car' (identical semantics —
--    seats/from/departs_at all behave the same).
-- 2. Table CHECK re-created without 'carpool'.
-- 3. set_participation_transport (latest body 00238) re-created with the
--    tamper list / driver checks reduced to 'car'. Signature unchanged ->
--    CREATE OR REPLACE, grants preserved (re-asserted anyway).
-- Read-side filters in seat-request functions still tolerate the legacy
-- value ('car','carpool') — harmless post-migration, no rows carry it.

UPDATE participations SET transport_type = 'car' WHERE transport_type = 'carpool';

ALTER TABLE participations DROP CONSTRAINT IF EXISTS participations_transport_type_check;
ALTER TABLE participations ADD CONSTRAINT participations_transport_type_check
  CHECK (transport_type IS NULL OR transport_type IN ('car', 'public_transport', 'bike', 'on_foot', 'other'));

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
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_from_name TEXT;
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

  -- Strip HTML/script tags from the city/place name before storing.
  -- Matches the pattern used for wall_messages (00006), private_messages
  -- (00099) and seat_requests.message (00085).
  v_from_name := CASE
    WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
    THEN regexp_replace(trim(p_transport_from_name), '<[^>]*>', '', 'g')
    ELSE NULL
  END;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = v_from_name,
      transport_departs_at = p_transport_departs_at
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$$;

REVOKE ALL ON FUNCTION set_participation_transport FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION set_participation_transport FROM anon;
GRANT EXECUTE ON FUNCTION set_participation_transport TO authenticated;
