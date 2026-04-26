-- Migration 00111: security review fixes from end-to-end audit
--
-- (1) peer_validate_presence: SELECT FOR UPDATE on the voted participation
--     row to serialize concurrent peer votes (otherwise threshold can be
--     missed when 2 votes arrive within the same race window).
-- (2) accept_seat_request: SELECT FOR UPDATE on the seat request + idempotent
--     UPDATE filter to prevent double-accept on rapid double-tap.
-- (3) Presence notif dedup: partial UNIQUE index + EXCEPTION-tolerant insert
--     in notify_presence_*.
-- (4) share_trace_message: deep-validate coordinate types (numeric pairs).
-- (5) request_seat: catch unique_violation and re-raise as generic.

-- ----------------------------------------------------------------------------
-- (3) Notif dedup index — partial UNIQUE for presence notifs only.
--     Other notif types (participant_joined etc) can legitimately have
--     duplicates, so we restrict the constraint to the dedup'd types.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS idx_notif_presence_dedup
ON notifications (user_id, type, ((data->>'activity_id')))
WHERE type IN ('presence_reminder', 'presence_last_call');

-- ----------------------------------------------------------------------------
-- (1) peer_validate_presence — FOR UPDATE on voted participation
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION peer_validate_presence(
  p_voted_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_voter_present BOOLEAN;
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Lock the voted user's participation row to serialize concurrent peer votes.
  -- Without this, two simultaneous votes can both fail to trigger the flip
  -- because each sees count=1 in its own snapshot.
  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;
  IF v_voted_status != 'accepted' OR v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  IF v_vote_count >= 2 THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    PERFORM recalculate_reliability_score(p_voted_id);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION peer_validate_presence FROM anon;
GRANT EXECUTE ON FUNCTION peer_validate_presence TO authenticated;

-- ----------------------------------------------------------------------------
-- (2) accept_seat_request — FOR UPDATE + idempotent UPDATE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION accept_seat_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_secret TEXT;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Lock the seat request row first so concurrent accept calls serialize.
  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Idempotent flip — only succeeds if still pending. The FOR UPDATE above
  -- already ensures that, but the WHERE clause makes the intent explicit
  -- and provides defense in depth.
  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;
  SELECT transport_from_name INTO v_driver_from FROM participations WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted';

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  SELECT id INTO v_conversation_id FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2 AND status = 'active';
  IF v_conversation_id IS NULL THEN
    INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
    RETURNING id INTO v_conversation_id;
  END IF;

  v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
    || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
    || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_req.driver_id, v_req.requester_id, v_message,
    jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (
    v_req.requester_id, 'seat_request_accepted', 'Place confirmée !', '',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'type', 'seat_request_accepted'
    ),
    NOW()
  );

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', v_req.requester_id,
        'title', 'Place confirmée !',
        'body', coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
        'data', jsonb_build_object(
          'conversation_id', v_conversation_id,
          'activity_id', v_req.activity_id,
          'type', 'seat_request_accepted'
        )
      )
    );
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_seat_request FROM anon;
GRANT EXECUTE ON FUNCTION accept_seat_request TO authenticated;

-- ----------------------------------------------------------------------------
-- (3) notify_presence_reminders + notify_presence_last_call — tolerant of
--     constraint violations (defense in depth on top of NOT EXISTS check).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_presence_reminders(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'in_progress' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_reminder'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_reminder',
        'Pense à valider ta présence',
        v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL; -- another tx beat us, fine
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_reminders FROM anon, authenticated;

CREATE OR REPLACE FUNCTION notify_presence_last_call(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_last_call'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_last_call',
        'Dernière chance — valide ta présence',
        'Scan le QR du créateur dans l''heure pour ' || v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_last_call FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- (4) share_trace_message — validate every coordinate is a numeric pair
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION share_trace_message(
  p_conversation_id UUID,
  p_trace_geojson JSONB,
  p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other_user_id UUID;
  v_recent_count INTEGER;
  v_message_id UUID;
  v_clean_name TEXT;
  v_sender_name TEXT;
  v_secret TEXT;
  v_coord_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2, status INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conv.user_1 THEN v_conv.user_2 ELSE v_conv.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Deep coordinate validation: each entry must be a numeric pair (lng, lat)
  -- with optional 3rd numeric (elevation). Rejects malformed or non-numeric
  -- entries that would otherwise pass the shallow shape check.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_trace_geojson->'coordinates') AS coord
    WHERE jsonb_typeof(coord) != 'array'
       OR jsonb_array_length(coord) < 2
       OR jsonb_array_length(coord) > 3
       OR jsonb_typeof(coord->0) != 'number'
       OR jsonb_typeof(coord->1) != 'number'
       OR (jsonb_array_length(coord) = 3 AND jsonb_typeof(coord->2) != 'number')
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_trace'));
  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE sender_id = v_user_id
    AND metadata->>'type' = 'shared_trace'
    AND created_at > NOW() - INTERVAL '1 minute';
  IF v_recent_count >= 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    p_conversation_id, v_user_id, v_other_user_id, '📍 ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson),
    NOW()
  )
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = NOW() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', '📍 ' || v_clean_name,
        'data', jsonb_build_object('conversation_id', p_conversation_id, 'type', 'shared_trace')
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION share_trace_message FROM anon;
GRANT EXECUTE ON FUNCTION share_trace_message TO authenticated;

-- ----------------------------------------------------------------------------
-- (5) request_seat — wrap UNIQUE violation as generic error
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION request_seat(
  p_activity_id UUID,
  p_driver_id UUID,
  p_pickup_from TEXT DEFAULT NULL,
  p_message TEXT DEFAULT NULL
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

  -- Lock-then-insert pattern via FOR UPDATE on existing row prevents
  -- the unique_violation race when the same user spams the request.
  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message)
      RETURNING id INTO v_request_id;
    EXCEPTION
      WHEN unique_violation THEN
        -- Concurrent insert won the race; fail generically.
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
