-- ============================================================================
-- 00486 — Phase vie privée, lot 2.
-- IX-1  Une sortie privée ne se rejoint plus avec son seul identifiant : il
--       faut avoir ouvert son lien (enregistré par get_activity_by_invite_token,
--       que l'app appelle déjà avant de rejoindre) ou avoir reçu un partage de
--       son organisateur. Corrige au passage un bug : une sortie privée
--       partagée par l'organisateur dans une conversation ne s'ouvrait pas chez
--       le destinataire.
-- AC-8  invite_token n'est plus lisible en direct (droits par colonne).
-- IX-2  Une demande de place ne transforme plus en conversation un contact que
--       le conducteur a refusé ou pas encore accepté (notification seulement).
-- TX-3  Les buckets publics ne sont plus listables : lecture de son propre
--       dossier seulement (les liens publics des images restent valides).
-- ============================================================================

CREATE TABLE IF NOT EXISTS invite_grants (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, activity_id)
);
ALTER TABLE invite_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE invite_grants FORCE ROW LEVEL SECURITY;
REVOKE ALL ON invite_grants FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.private_activity_access(p_activity_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
      SELECT 1 FROM invite_grants g
      WHERE g.activity_id = p_activity_id AND g.user_id = p_user_id
        AND g.at > now() - INTERVAL '30 days')
    OR EXISTS (
      -- Shared by the organiser (share card or invitation) into a
      -- conversation this account belongs to.
      SELECT 1 FROM activities a
      JOIN messages m ON m.sender_id = a.creator_id
      JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = p_user_id
      WHERE a.id = p_activity_id
        AND m.deleted_at IS NULL
        AND m.metadata->>'type' = 'shared_activity'
        AND m.metadata->>'activity_id' = p_activity_id::text);
$function$;
REVOKE ALL ON FUNCTION private.private_activity_access(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_activity_by_invite_token(p_token uuid)
 RETURNS TABLE(id uuid, creator_id uuid, sport_id uuid, title text, description text, level text, level_max text, max_participants integer, starts_at timestamp with time zone, duration interval, visibility text, status text, lng double precision, lat double precision, creator_name text, creator_avatar text, sport_key text, sport_icon text, sport_category text, participant_count integer)
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 00486 (IX-1): remember that this account opened the link; join_activity
  -- requires it for a private outing (the app calls this before joining).
  INSERT INTO invite_grants (user_id, activity_id, at)
  SELECT v_user_id, a.id, now() FROM activities a
  WHERE a.invite_token = p_token AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL
  ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now();

  RETURN QUERY
  SELECT
    a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.level_max,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.status,
    ST_X(a.location_meeting::geometry)::FLOAT AS lng,
    ST_Y(a.location_meeting::geometry)::FLOAT AS lat,
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
$function$;

CREATE OR REPLACE FUNCTION public.join_activity(p_activity_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo, deleted_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Demo activities are joinable only by an admin currently in demo mode.
  IF v_activity.is_demo AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00486 (IX-1): a private outing is joined only through its link (opened
  -- by this account) or an invitation from its organiser — never by id alone.
  IF v_activity.visibility = 'private_link'
     AND NOT private.private_activity_access(p_activity_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at, left_at INTO v_existing
  FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- 00477 (DB-PR-1): test the id, not the record — a RECORD with any NULL field
  -- (refused_at, left_at) is never « IS NOT NULL », which sent every rejoin to
  -- the INSERT branch and a raw unique violation.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    IF v_existing.status = 'invited' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE participations
      SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
      WHERE id = v_existing.id;
      SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
      PERFORM create_notification(
        v_activity.creator_id, 'invitation_accepted',
        coalesce(v_user_name, 'Quelqu''un') || ' a accepté ton invitation',
        '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
        jsonb_build_object('activity_id', p_activity_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
      );
      RETURN 'accepted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    -- 00477 (AB-1): a join/leave loop pushed the organiser without limit — the
    -- hourly cap counts rows and a rejoin reuses the same row. 15 min after a
    -- withdrawal before rejoining the same outing.
    IF v_existing.status = 'withdrawn'
       AND v_existing.left_at IS NOT NULL
       AND v_existing.left_at > NOW() - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'junto.rejoin_cooldown';
    END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now(), refused_at = NULL
    WHERE id = v_existing.id;
  ELSE
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id, 'join_request',
      coalesce(v_user_name, 'Quelqu''un') || ' veut rejoindre ta sortie',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id,
        'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title))
    );
  ELSE
    PERFORM notify_participant_joined(v_activity.creator_id, p_activity_id, v_user_name, v_activity.title);
  END IF;

  RETURN v_result_status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_detail(p_activity_id uuid)
 RETURNS SETOF activities_with_coords
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
    a.distance_km, a.elevation_gain_m,
    a.max_participants, a.starts_at, a.duration, a.visibility,
    a.requires_presence,
    a.status, a.deleted_at, a.created_at, a.updated_at,
    a.objective_name, a.meeting_name,
    a.trace_geojson,
    ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
    ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
    ST_X(a.location_meeting::geometry) AS meeting_lng,
    ST_Y(a.location_meeting::geometry) AS meeting_lat,
    ST_X(a.location_end::geometry) AS end_lng,
    ST_Y(a.location_end::geometry) AS end_lat,
    ST_X(a.location_objective::geometry) AS objective_lng,
    ST_Y(a.location_objective::geometry) AS objective_lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
    a.level_max,
    a.meeting_locality
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.id = p_activity_id
    AND a.deleted_at IS NULL
    AND (a.is_demo = false OR demo_content_visible())
    AND NOT private.user_is_suspended(a.creator_id)
    AND a.creator_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
    AND (
      a.creator_id = v_user_id
      OR EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id AND p.user_id = v_user_id
          AND p.status IN ('accepted', 'pending')
      )
      OR a.visibility IN ('public', 'approval')
      -- 00486: opened through its link, or shared by its organiser.
      OR (a.visibility = 'private_link' AND private.private_activity_access(a.id, v_user_id))
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text DEFAULT NULL::text, p_message text DEFAULT NULL::text, p_requested_pickup_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_starts_at TIMESTAMPTZ;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_conv_sender UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_seed_message TEXT;
  v_recent_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_driver_id)
       OR (blocker_id = p_driver_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('request_seat:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM seat_requests
  WHERE requester_id = v_user_id
    AND created_at > NOW() - INTERVAL '5 minutes';
  IF v_recent_count >= 5 THEN RAISE EXCEPTION 'junto.seat_rate_limit'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id
    AND a.status IN ('published', 'in_progress')
    AND a.starts_at > NOW() - INTERVAL '15 seconds'
    AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'junto.no_seats_available'; END IF;

  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'junto.pickup_out_of_window';
    END IF;
  END IF;

  -- Strip HTML/script tags from pickup_from too (message already does).
  v_pickup := CASE
    WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
    THEN regexp_replace(trim(p_pickup_from), '<[^>]*>', '', 'g')
    ELSE NULL
  END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
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
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  IF v_user_id < p_driver_id THEN
    v_u1 := v_user_id; v_u2 := p_driver_id;
  ELSE
    v_u1 := p_driver_id; v_u2 := v_user_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (pas seulement active).
  -- Une ligne pending/declined est réactivée en logistique (retag 'transport'
  -- + purge des champs de requête — invariant 00372 : un refus social ne
  -- devient pas un contact par le covoit). Plus d'unique_violation brute.
  SELECT id, status, request_sender_id INTO v_conversation_id, v_conv_status, v_conv_sender
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  -- 00486 (IX-2 / BR-1): if the requester's own contact request to the driver
  -- was refused (or is still unanswered), the seat request must not turn into
  -- a conversation the driver never accepted. The driver gets the request by
  -- notification and decides; accepting it is the driver's consent.
  IF v_conversation_id IS NOT NULL AND v_conv_status IN ('declined', 'pending_request')
     AND v_conv_sender = v_user_id THEN
    v_conversation_id := NULL;
  END IF;

  IF v_conversation_id IS NULL AND v_conv_status IS NOT NULL THEN
    NULL; -- 00486: muted (see above)
  ELSIF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES (v_u1, v_u2, v_user_id, 'active', 'transport', NOW(), NOW())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  ELSIF v_conv_status != 'active' THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations
    SET status = 'active', initiated_from = 'transport',
        request_sender_id = NULL, request_message = NULL,
        pending_activity_id = NULL, request_expires_at = NULL,
        last_message_at = NOW()
    WHERE id = v_conversation_id;
    UPDATE conversation_members SET hidden_at = NULL
    WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;

  IF v_conversation_id IS NOT NULL THEN
  v_seed_message := '🚗 Demande de place pour « ' || v_activity_title || ' »'
    || CASE WHEN v_pickup IS NOT NULL THEN E'\nDepuis : ' || v_pickup ELSE '' END
    || CASE WHEN v_message IS NOT NULL THEN E'\n\n' || v_message ELSE '' END;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, p_driver_id, v_seed_message,
    jsonb_build_object(
      'type', 'seat_request_pending',
      'activity_id', p_activity_id,
      'seat_request_id', v_request_id
    ),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_driver_id,
    'seat_request',
    'Demande de covoiturage',
    coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »'
      || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'conversation_id', v_conversation_id,
      'variant', CASE WHEN v_pickup IS NOT NULL THEN 'pickup' ELSE NULL END,
      'params', jsonb_build_object('name', coalesce(v_requester_name, 'Quelqu''un'), 'title', v_activity_title, 'pickup', coalesce(v_pickup, ''))
    )
  );

  RETURN v_conversation_id;
END;
$function$;

-- ---------- AC-8 : invite_token illisible en direct ----------
DO $$
DECLARE v_cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(attname), ', ' ORDER BY attnum) INTO v_cols
  FROM pg_attribute
  WHERE attrelid = 'public.activities'::regclass AND attnum > 0 AND NOT attisdropped
    AND attname <> 'invite_token';
  EXECUTE 'REVOKE SELECT ON public.activities FROM anon, authenticated';
  EXECUTE format('GRANT SELECT (%s) ON public.activities TO anon, authenticated', v_cols);
END $$;

-- ---------- TX-3 : buckets non listables ----------
DROP POLICY IF EXISTS avatars_read_all ON storage.objects;
DROP POLICY IF EXISTS pro_photos_read_all ON storage.objects;
DROP POLICY IF EXISTS channel_photos_read_all ON storage.objects;
-- Own folder only: needed by upload with upsert. Public image URLs are served
-- by the public bucket endpoint, which does not go through these policies.
CREATE POLICY avatars_read_own ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY pro_photos_read_own ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'pro-photos' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY channel_photos_read_own ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'channel-photos' AND (storage.foldername(name))[1] = auth.uid()::text);
