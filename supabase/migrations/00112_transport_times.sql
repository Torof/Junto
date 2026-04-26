-- Migration 00112: explicit departure / pickup times for transport coordination.
-- Driver declares when they leave; requester says when they want to be picked up.

-- ----------------------------------------------------------------------------
-- Schema
-- ----------------------------------------------------------------------------
ALTER TABLE participations ADD COLUMN IF NOT EXISTS transport_departs_at TIMESTAMPTZ;
ALTER TABLE seat_requests   ADD COLUMN IF NOT EXISTS requested_pickup_at TIMESTAMPTZ;

-- ----------------------------------------------------------------------------
-- set_participation_transport — accept p_transport_departs_at
-- (drop old signature so REVOKE/GRANT below isn't ambiguous)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS set_participation_transport(UUID, TEXT, SMALLINT, TEXT);

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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Seats only meaningful for car/carpool
  IF p_transport_type NOT IN ('car', 'carpool') AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  -- Departure time only meaningful for car/carpool
  IF p_transport_type NOT IN ('car', 'carpool') THEN
    p_transport_departs_at := NULL;
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

-- ----------------------------------------------------------------------------
-- request_seat — accept p_requested_pickup_at
-- (drop old signature so REVOKE/GRANT below isn't ambiguous)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS request_seat(UUID, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION request_seat(
  p_activity_id UUID,
  p_driver_id UUID,
  p_pickup_from TEXT DEFAULT NULL,
  p_message TEXT DEFAULT NULL,
  p_requested_pickup_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_secret TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id AND status IN ('published', 'in_progress') AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_pickup := CASE WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
                   THEN trim(p_pickup_from) ELSE NULL END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message,
        requested_pickup_at = p_requested_pickup_at
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message, requested_pickup_at)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message, p_requested_pickup_at)
      RETURNING id INTO v_request_id;
    EXCEPTION
      WHEN unique_violation THEN
        RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = p_activity_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    p_driver_id, 'seat_request',
    v_requester_name || ' demande une place' || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    COALESCE(v_message, ''),
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'type', 'seat_request'
    ),
    NOW()
  );

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', p_driver_id,
        'title', 'Demande de covoiturage',
        'body', coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »',
        'data', jsonb_build_object(
          'seat_request_id', v_request_id,
          'activity_id', p_activity_id,
          'type', 'seat_request'
        )
      )
    );
  END IF;

  RETURN v_request_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION request_seat FROM anon;
GRANT EXECUTE ON FUNCTION request_seat TO authenticated;

-- ----------------------------------------------------------------------------
-- public_participants view: expose transport_departs_at
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public_participants;
CREATE VIEW public_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  p.transport_type,
  p.transport_seats,
  p.transport_from_name,
  p.transport_departs_at,
  pp.display_name,
  pp.avatar_url
FROM participations p
JOIN public_profiles pp ON pp.id = p.user_id;

GRANT SELECT ON public_participants TO authenticated;
