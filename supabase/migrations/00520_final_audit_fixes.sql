-- ============================================================================
-- 00520 — Dernier audit avant migration (couverture, autorisations, attaques).
-- COV-1 / authz 6  Écran d'évaluation : ni compte suspendu, ni sortie retirée.
-- authz 1  Lien d'invitation : jamais pour une personne retirée / bloquée, ni
--          pour la sortie d'un organisateur suspendu ; rideau démo.
-- authz 2  Agrégats de trophées : absences et sorties retirées exclues.
-- authz 3  Modification de message : rétablit la règle « discussion fermée »
--          (perdue par 00519, reconstruite depuis une copie antérieure à 00514)
--          et applique les règles d'envoi (conversation, blocages, bannis).
-- authz 4  Pas d'acceptation d'un demandeur suspendu entre-temps.
-- authz 5  Annuler sa place ne dépasse jamais 8 places.
-- authz 7  Signalements : verrou + index unique.
-- authz 8  Pas de photo communautaire chez un pro suspendu.
-- C1       Découverte : « peu importe » ne fait plus un annuaire national — les
--          zones doivent vraiment se croiser (rayon de l'autre).
-- ID-9     Statistiques de profil : appelant connecté et non suspendu.
-- C6       Accepté quelque part → ses demandes en attente qui chevauchent sont
--          retirées (plus d'oracle d'agenda par l'organisateur).
-- AB-7     Plafond global quotidien des appels de tracé.
-- C8       Discussions : 100 messages / jour / membre / discussion.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS reports_one_per_target ON reports (reporter_id, target_type, target_id);

CREATE OR REPLACE FUNCTION public.get_activity_peer_review_state(p_activity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_result jsonb;
  v_sport_key TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00520 (COV-1): suspended caller or moderated outing → nothing.
  IF private.user_is_suspended(v_user_id)
     OR EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id',                p.user_id,
      'display_name',           pp.display_name,
      'avatar_url',             pp.avatar_url,
      -- 00488 (DX-1): never echo an absence to co-participants.
      'confirmed_present',      CASE WHEN p.confirmed_present THEN true END,
      -- 00508: peer presence testimony removed (disabled since 00434).
      'peer_validation_count',  0,
      'i_voted_presence',       false,
      'my_badge_votes',         coalesce(my_votes.keys, ARRAY[]::TEXT[]),
      'declared_level',         NULLIF(pp.levels_per_sport ->> v_sport_key, '')
    )
  ) INTO v_result
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  LEFT JOIN (
    SELECT voted_id, array_agg(badge_key) AS keys
    FROM reputation_votes
    WHERE activity_id = p_activity_id AND voter_id = v_user_id
    GROUP BY voted_id
  ) my_votes ON my_votes.voted_id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id != v_user_id;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_by_invite_token(p_token uuid)
 RETURNS TABLE(id uuid, creator_id uuid, sport_id uuid, title text, description text, level text, level_max text, max_participants integer, starts_at timestamp with time zone, duration interval, visibility text, status text, lng double precision, lat double precision, creator_name text, creator_avatar text, sport_key text, sport_icon text, sport_category text, participant_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    -- 00520: never for someone the organiser removed or blocked, nor for a
    -- suspended organiser's outing (same rules as private_activity_access).
    AND NOT private.user_is_suspended(a.creator_id)
    AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = a.creator_id AND b.blocked_id = v_user_id)
    AND NOT EXISTS (SELECT 1 FROM participations rp WHERE rp.activity_id = a.id AND rp.user_id = v_user_id AND rp.status = 'removed')
    AND (a.is_demo = false OR demo_content_visible())
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
    AND a.deleted_at IS NULL
    -- 00520: never for someone the organiser removed or blocked, nor for a
    -- suspended organiser's outing (same rules as private_activity_access).
    AND NOT private.user_is_suspended(a.creator_id)
    AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = a.creator_id AND b.blocked_id = v_user_id)
    AND NOT EXISTS (SELECT 1 FROM participations rp WHERE rp.activity_id = a.id AND rp.user_id = v_user_id AND rp.status = 'removed')
    AND (a.is_demo = false OR demo_content_visible());
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_award_aggregates(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH completed AS (
    SELECT
      a.id,
      a.creator_id,
      a.duration,
      s.key AS sport_key,
      s.category
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS DISTINCT FROM false  -- 00520 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00520 (PR-10)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  per_category AS (
    SELECT
      category,
      count(*)::int AS outings,
      count(DISTINCT sport_key)::int AS distinct_sports
    FROM completed
    GROUP BY category
  )
  SELECT jsonb_build_object(
    'joined', (SELECT count(*)::int FROM completed WHERE creator_id IS DISTINCT FROM p_user_id),
    'created', (SELECT count(*)::int FROM completed WHERE creator_id = p_user_id),
    'distinct_sports', (SELECT count(DISTINCT sport_key)::int FROM completed),
    'multi_day_count', (SELECT count(*)::int FROM completed WHERE duration > INTERVAL '1 day'),
    'by_category', COALESCE((
      SELECT jsonb_object_agg(category, jsonb_build_object(
        'outings', outings,
        'distinct_sports', distinct_sports
      )) FROM per_category
    ), '{}'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv_id UUID;
  v_type TEXT;
  v_activity_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT c.id, c.type, c.activity_id INTO v_conv_id, v_type, v_activity_id
  FROM messages m JOIN conversations c ON c.id = m.conversation_id
  WHERE m.id = p_message_id AND m.sender_id = v_user_id
    AND m.deleted_at IS NULL AND m.metadata IS NULL; -- rich cards not editable
  IF v_conv_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: a group taken down by moderation is read-only.
  -- 00520: restores 00514 (lost by 00519) — no rewriting in a closed discussion,
  -- and the same thread rules as sending (DM status, blocks, bans).
  IF v_type = 'channel' AND EXISTS (SELECT 1 FROM channels WHERE conversation_id = v_conv_id AND closed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.assert_can_send(v_conv_id, v_user_id);
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv_id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Must still be a member; for activity messages the activity must be alive
  -- (wall edit parity 00177).
  IF NOT private.is_conversation_member(v_conv_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_type = 'activity' AND NOT EXISTS (
    SELECT 1 FROM activities a WHERE a.id = v_activity_id
      AND a.deleted_at IS NULL AND a.status IN ('published', 'in_progress')
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00474 (counter-audit F5): keep the first version for moderation (internal
  -- table, no client grant) — an edit can no longer launder a thread.
  INSERT INTO message_original_content (message_id, content)
  SELECT id, content FROM messages WHERE id = p_message_id
  ON CONFLICT (message_id) DO NOTHING;

  UPDATE messages SET content = trim(p_content), edited_at = now()
  WHERE id = p_message_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_participation(p_participation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_max_participants INTEGER;
  v_activity_status TEXT;
  v_current_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00516: not on an outing removed by moderation, nor once the presence
  -- check window of a started outing has passed.
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_participation.activity_id
             AND (a.deleted_at IS NOT NULL OR (a.requires_presence AND now() > a.starts_at + INTERVAL '15 minutes'))) THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00520: not a requester suspended in the meantime.
  IF private.user_is_suspended(v_participation.user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Lock the activity row and re-read cap AND status under the lock:
  -- serializes concurrent accepts with each other, with join_activity
  -- (same lock), with update_activity lowering the cap, and with
  -- cancel_activity flipping the status (00311 re-read the cap only —
  -- an accept racing a cancel could accept into a cancelled activity).
  SELECT max_participants, status INTO v_max_participants, v_activity_status
  FROM activities WHERE id = v_participation.activity_id
  FOR UPDATE;

  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  -- Open activities (max_participants IS NULL) honor a hidden 50-soft-cap, same as join_activity
  IF v_current_count >= COALESCE(v_max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_accepted',
    'Tu es dans la sortie !',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_accepted_seat(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.requester_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_request.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  UPDATE seat_requests SET status = 'cancelled'
  WHERE id = p_request_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations
  SET transport_seats = LEAST(COALESCE(transport_seats, 0) + 1, 8)  -- 00520: never above the CHECK
  WHERE activity_id = v_request.activity_id
    AND user_id = v_request.driver_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity',
                           'pro_review', 'offering_review', 'message', 'group', 'channel') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');
  IF char_length(v_reason) < 10 THEN RAISE EXCEPTION 'junto.report_reason_too_short'; END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Existence checks. 'message' / 'group' hit the unified store; the reporter
  -- must be a member of the conversation the content lives in (no probing).
  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'activity' AND NOT EXISTS (SELECT 1 FROM activities WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'message' AND NOT EXISTS (
    -- 00499 (MS-8): a message deleted by its author stays reportable by a
    -- member (deleting abuse right after sending it must not dodge a report).
    SELECT 1 FROM messages m
    WHERE m.id = p_target_id
      AND private.is_conversation_member(m.conversation_id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'group' AND NOT EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = p_target_id AND c.type = 'group'
      AND private.is_conversation_member(c.id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'channel' AND NOT EXISTS (
    SELECT 1 FROM conversations c WHERE c.id = p_target_id AND c.type = 'channel'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00520: serialised per reporter (and a unique index backs it).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_report'));
  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN RAISE EXCEPTION 'junto.report_already_filed'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));
  SELECT count(*) INTO v_hourly_count FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.report_rate_limit'; END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;
  RETURN v_report_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid DEFAULT NULL::uuid, p_offering_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF private.user_is_suspended(p_pro_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;  -- 00520
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : cible = pro APPROUVÉ (ferme l'oracle de candidature — même
  -- erreur générique qu'une cible inexistante).
  -- 00443 B5 : et NON démo — un compte démo ne reçoit jamais d'écriture réelle (00426).
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND status = 'approved' AND is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : URL ancrée hôte + dossier du CONTRIBUTEUR (fin du wildcard).
  IF NOT private.pro_photo_url_ok(p_photo_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_review_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_reviews
    WHERE id = p_review_id AND reviewer_id = v_user_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_offering_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_offerings
    WHERE id = p_offering_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_community_photo:' || v_user_id::text || ':' || p_pro_id::text));

  SELECT count(*) INTO v_count
  FROM pro_community_photos
  WHERE pro_id = p_pro_id AND contributor_id = v_user_id;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'junto.photo_limit';
  END IF;

  INSERT INTO pro_community_photos (pro_id, contributor_id, photo_url, review_id, offering_id)
  VALUES (p_pro_id, v_user_id, p_photo_url, p_review_id, p_offering_id)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_discovery_cards()
 RETURNS TABLE(user_id uuid, display_name text, avatar_url text, reliability_tier text, sport_keys text[], levels jsonb, transport_modes text[], radius_km integer, window_start timestamp with time zone, window_end timestamp with time zone, intent text[], distance_km double precision, sorties_count integer, about text, contact_state text, conversation_id uuid, is_demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes, d.radius_km,
         d.window_start, d.window_end, d.intent,
         -- 00485 (DC-1): whole kilometres, never below 1.
         greatest(1, round(ST_Distance(d.base, v_base) / 1000.0))::float8 AS distance_km,
         -- 00435 (trouvé par Scott) : ce compteur n'exigeait QUE status =
         -- 'accepted' — donc s'inscrire à 200 sorties futures affichait
         -- « 200 sorties » immédiatement, sans qu'aucune ait eu lieu. Et c'est
         -- le chiffre qu'un inconnu lit avant de décider de te contacter. On
         -- applique le même prédicat que get_user_public_stats : sortie
         -- réellement terminée, et présence non démentie.
         (SELECT count(*)::int FROM participations p
          JOIN activities pa ON pa.id = p.activity_id
          WHERE p.user_id = d.user_id
            AND p.status = 'accepted'
            AND p.confirmed_present IS DISTINCT FROM false
            AND pa.status = 'completed'
            AND pa.deleted_at IS NULL) AS sorties_count,
         d.about,
         coalesce((
           SELECT CASE
             WHEN c.status = 'active' THEN 'connected'
             WHEN c.request_sender_id = v_user_id THEN 'pending'
             WHEN c.status = 'pending_request' AND c.request_expires_at > NOW() THEN 'pending_received'
             ELSE 'none'
           END
           FROM conversations c
           WHERE c.type = 'dm'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ), 'none') AS contact_state,
         (
           SELECT c.id FROM conversations c
           WHERE c.type = 'dm' AND c.status = 'active'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ) AS conversation_id,
         u.is_demo
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND d.window_end > now()
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         (v_radius IS NULL AND d.radius_km IS NULL)
         OR ST_DWithin(d.base, v_base, (coalesce(v_radius, 0) + coalesce(d.radius_km, 0)) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  -- 00435 : le tri portait sur pp.reliability_score, que la vue public_profiles
  -- force à NULL depuis 00347 (elle ne publie que le palier) → clé de tri
  -- constamment vide, classement dégénéré en distance seule, et ce depuis six
  -- réécritures de cette fonction. On trie sur la table users, déjà jointe
  -- ligne « JOIN users u ». Ce n'est qu'un ORDER BY : aucune colonne
  -- supplémentaire n'est retournée, donc le score brut reste non publié.
  ORDER BY u.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_discovery_count(p_sport_keys text[], p_base_lng double precision, p_base_lat double precision, p_radius_km integer, p_window_start timestamp with time zone, p_window_end timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN 0; END IF;
  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_window_start IS NULL OR p_window_end IS NULL THEN
    RETURN 0;
  END IF;
  -- 00485 (DC-2): radius from the app's list only (NULL = « anywhere », which
  -- constrains no position), probe rounded like stored bases, and a budget.
  IF p_radius_km IS NOT NULL AND p_radius_km NOT IN (5, 10, 15, 30, 50) THEN
    RAISE EXCEPTION 'junto.dispo_radius';
  END IF;
  PERFORM private.rate_hit('dispo_count', 300, INTERVAL '1 hour');
  v_base := ST_SetSRID(ST_MakePoint(round(p_base_lng::numeric, 2)::float8, round(p_base_lat::numeric, 2)::float8), 4326)::geography;

  SELECT count(*) INTO v_count
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  WHERE d.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND d.window_end > now()
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && p_sport_keys
    AND tstzrange(d.window_start, d.window_end) && tstzrange(p_window_start, p_window_end)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         (p_radius_km IS NULL AND d.radius_km IS NULL)
         OR ST_DWithin(d.base, v_base, (coalesce(p_radius_km, 0) + coalesce(d.radius_km, 0)) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id));

  IF v_count > 0 AND v_count <= 2 THEN RETURN -1; END IF;  -- -1 = "quelques"
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dispo_zone(p_user_id uuid)
 RETURNS TABLE(base_lng double precision, base_lat double precision, radius_km integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_user_id THEN RETURN; END IF;  -- own zone comes from get_my_dispo

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE (b.blocker_id = v_user_id AND b.blocked_id = p_user_id)
       OR (b.blocker_id = p_user_id AND b.blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT ST_X(t.base::geometry), ST_Y(t.base::geometry), t.radius_km
  FROM discovery_availabilities t
  JOIN users u ON u.id = t.user_id AND u.suspended_at IS NULL
  WHERE t.user_id = p_user_id
    AND t.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND t.window_end > now()
    AND (t.is_demo = false OR demo_content_visible())
    AND t.sport_keys && v_sports
    AND tstzrange(t.window_start, t.window_end) && tstzrange(v_ws, v_we)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         (v_radius IS NULL AND t.radius_km IS NULL)
         OR ST_DWithin(t.base, v_base, (coalesce(v_radius, 0) + coalesce(t.radius_km, 0)) * 1000.0));
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_discovery_invite(p_target_user_id uuid, p_activity_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_activity RECORD;
  v_sport_key TEXT;
  v_dispo RECORD;
  v_clean_title TEXT;
  v_message TEXT;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Rideau démo côté écriture : garde ABSOLUE, même en mode démo admin
  -- (demo_content_visible() rend les gates de réciprocité perméables à
  -- l'admin — la cible démo doit être rejetée AVANT).
  IF NOT EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = p_target_user_id AND u.suspended_at IS NULL AND u.is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Reciprocity + demo gate: the target must be one of MY discovery matches.
  -- Generic failure (sensitive): don't reveal whether it's no-dispo vs no-match.
  IF NOT EXISTS (
    SELECT 1
    FROM discovery_availabilities me
    JOIN discovery_availabilities tgt
      ON tgt.user_id = p_target_user_id AND tgt.is_active AND tgt.window_end > now()  -- 00496 (BR-5)
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active AND me.window_end > now()
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         (me.radius_km IS NULL AND tgt.radius_km IS NULL)
         OR ST_DWithin(me.base, tgt.base, (coalesce(me.radius_km, 0) + coalesce(tgt.radius_km, 0)) * 1000.0))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be mine, live, real.
  SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo, a.starts_at, a.sport_id
  INTO v_activity FROM activities a WHERE a.id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.creator_id != v_user_id
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00514 (MS-3): never re-invite someone who declined this outing.
  IF EXISTS (SELECT 1 FROM invitation_declines d WHERE d.activity_id = p_activity_id AND d.user_id = p_target_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key FROM sports s WHERE s.id = v_activity.sport_id;

  -- Match the chosen activity against the target's ACTIVE dispo (sport + date).
  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active AND d.window_end > now()
    AND (d.is_demo = false OR demo_content_visible());
  IF NOT FOUND
     OR v_sport_key IS NULL
     OR NOT (v_sport_key = ANY(v_dispo.sport_keys))
     OR v_activity.starts_at < v_dispo.window_start
     OR v_activity.starts_at > v_dispo.window_end THEN
    RAISE EXCEPTION 'junto.discovery_no_match';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT * INTO v_conv FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;
  IF v_conv.id IS NOT NULL THEN
    -- Même règle de réouverture que send_contact_request (00426 §3).
    IF v_user_id IS DISTINCT FROM v_conv.request_sender_id
       AND (v_conv.status = 'declined'
            OR (v_conv.status = 'pending_request' AND v_conv.request_expires_at < NOW())) THEN
      DELETE FROM conversations WHERE id = v_conv.id;
    ELSE
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND status IN ('pending_request', 'declined')
    AND created_at > NOW() - INTERVAL '30 days';
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  v_message := 'Je t''invite à rejoindre « ' || v_clean_title || ' »';

  INSERT INTO conversations (
    user_1, user_2, initiated_by, status, initiated_from,
    request_sender_id, request_message, request_expires_at,
    pending_activity_id, created_at, last_message_at
  )
  VALUES (
    v_user_1, v_user_2, v_user_id, 'pending_request', 'invite',
    v_user_id, v_message, NOW() + INTERVAL '30 days',
    p_activity_id, NOW(), NOW()
  )
  ON CONFLICT (user_1, user_2) DO NOTHING
  RETURNING id INTO v_conversation_id;
  IF v_conversation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
    '« ' || v_clean_title || ' »',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'activity_id', p_activity_id,
      'variant', 'invite', 'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
  );

  RETURN v_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_invitable_activities_for_dispo(p_target_user_id uuid)
 RETURNS TABLE(id uuid, title text, sport_key text, starts_at timestamp with time zone, max_participants integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_dispo RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_target_user_id THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  -- Reciprocity: the target must be one of MY discovery matches. Silent empty
  -- otherwise (no availability oracle for a non-match / demo dispo).
  IF NOT EXISTS (
    SELECT 1
    FROM discovery_availabilities me
    JOIN discovery_availabilities tgt
      ON tgt.user_id = p_target_user_id AND tgt.is_active AND tgt.window_end > now()  -- 00496 (BR-5)
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active AND me.window_end > now()
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         (me.radius_km IS NULL AND tgt.radius_km IS NULL)
         OR ST_DWithin(me.base, tgt.base, (coalesce(me.radius_km, 0) + coalesce(tgt.radius_km, 0)) * 1000.0))
  ) THEN RETURN; END IF;

  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active AND d.window_end > now()
    AND (d.is_demo = false OR demo_content_visible());
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT a.id, a.title, s.key, a.starts_at, a.max_participants
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.creator_id = v_user_id
    AND a.deleted_at IS NULL
    AND NOT a.is_demo
    AND a.status IN ('published', 'in_progress')
    AND s.key = ANY(v_dispo.sport_keys)
    AND a.starts_at BETWEEN v_dispo.window_start AND v_dispo.window_end
  ORDER BY a.starts_at ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_public_stats(p_user_id uuid)
 RETURNS TABLE(total_activities integer, completed_activities integer, created_activities integer, joined_activities integer, sports_count integer, reliability_score double precision, reliability_tier text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 00419 M3 : rideau démo.
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  -- 00499 (DX-3): a suspended account reveals nothing (like public_profiles).
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  -- 00520 (ID-9): a signed-in, non-suspended caller only.
  IF auth.uid() IS NULL OR private.user_is_suspended(auth.uid()) THEN RETURN; END IF;

  RETURN QUERY
  WITH real_outings AS (
    SELECT a.id, a.creator_id
    FROM participations par
    JOIN activities a ON a.id = par.activity_id
    WHERE par.user_id = p_user_id
      AND par.status = 'accepted'
      AND par.confirmed_present IS DISTINCT FROM false
      AND a.status = 'completed'
      AND a.deleted_at IS NULL
  )
  SELECT
    (SELECT count(*)::int FROM real_outings) AS total_activities,
    (SELECT count(*)::int FROM real_outings) AS completed_activities,
    (SELECT count(*)::int FROM real_outings WHERE creator_id = p_user_id) AS created_activities,
    (SELECT count(*)::int FROM real_outings WHERE creator_id != p_user_id) AS joined_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    -- 00488: the raw score is not public (public_profiles hides it since
    -- 00347); only the tier below is.
    NULL::double precision AS reliability_score,
    (SELECT public.reliability_tier(u.reliability_score)
     FROM users u WHERE u.id = p_user_id) AS reliability_tier;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_sport_levels(p_user_id uuid)
 RETURNS TABLE(sport_key text, dots smallint, last_at timestamp with time zone, first_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH completed AS (
    SELECT s.key AS sport_key, a.level AS level, a.starts_at AS at
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS DISTINCT FROM false  -- 00495 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00495
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  agg AS (
    SELECT
      completed.sport_key,
      count(*) AS total,
      count(*) FILTER (
        WHERE completed.level IN ('intermédiaire', 'intermediate', 'avancé', 'advanced', 'expert')
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE completed.level IN ('avancé', 'advanced', 'expert')
      ) AS at_advanced,
      count(*) FILTER (WHERE completed.level = 'expert') AS at_expert,
      max(completed.at) AS last_at,
      min(completed.at) AS first_at
    FROM completed
    GROUP BY completed.sport_key
  )
  SELECT
    agg.sport_key,
    (CASE
      WHEN agg.at_expert >= 3 THEN 4
      WHEN agg.at_advanced >= 5 THEN 3
      WHEN agg.at_intermediate >= 3 THEN 2
      WHEN agg.total >= 1 THEN 1
      ELSE 0
    END)::SMALLINT AS dots,
    -- 00499 (DX-4): month only — an exact time could date a private outing.
    date_trunc('month', agg.last_at),
    date_trunc('month', agg.first_at)
  FROM agg
  WHERE agg.total > 0;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_sport_level_votes(p_user_id uuid)
 RETURNS TABLE(sport_key text, level_over integer, level_right integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    s.key AS sport_key,
    count(*) FILTER (WHERE rv.badge_key = 'level_over')::int AS level_over,
    count(*) FILTER (WHERE rv.badge_key = 'level_right')::int AS level_right
  FROM reputation_votes rv
  JOIN activities a ON a.id = rv.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE rv.voted_id = p_user_id
    AND rv.badge_key IN ('level_over', 'level_right')
    AND rv.counted_at IS NOT NULL
    AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
    AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
    AND rv.created_at >= now() - INTERVAL '12 months'   -- sliding freshness window
    -- 00493 (IX-3): demo curtain.
    AND (NOT EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo) OR demo_content_visible())
  GROUP BY s.key
  HAVING count(*) > 0;
$function$;

CREATE OR REPLACE FUNCTION private.check_schedule_conflict()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_range TSTZRANGE;
BEGIN
  -- 00503: a join REQUEST (pending) is checked too, for the requester
  -- only — otherwise the organiser who accepts later learns of another outing.
  IF NEW.status NOT IN ('accepted', 'pending') THEN RETURN NEW; END IF;
  IF NEW.status = 'pending' AND auth.uid() IS DISTINCT FROM NEW.user_id THEN RETURN NEW; END IF;
  -- System writes (scheduled jobs, demo seeding) have no end user.
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'accepted' THEN RETURN NEW; END IF;

  SELECT tstzrange(a.starts_at, a.starts_at + a.duration) INTO v_range
  FROM activities a
  WHERE a.id = NEW.activity_id AND NOT a.is_demo AND a.deleted_at IS NULL;
  IF v_range IS NULL THEN RETURN NEW; END IF;

  -- Serialise this person's acceptances (two joins at once).
  PERFORM pg_advisory_xact_lock(hashtext('schedule:' || NEW.user_id::text));

  IF EXISTS (
    SELECT 1 FROM participations p
    JOIN activities a ON a.id = p.activity_id
    WHERE p.user_id = NEW.user_id
      AND p.status = 'accepted'
      AND p.activity_id <> NEW.activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration) && v_range
  ) THEN
    IF auth.uid() IS NOT DISTINCT FROM NEW.user_id THEN
      RAISE EXCEPTION 'junto.schedule_conflict';
    ELSE
      RAISE EXCEPTION 'junto.participant_schedule_conflict';
    END IF;
  END IF;
  -- 00520 (C6): once accepted somewhere, the person's overlapping pending
  -- requests are withdrawn — no organiser can probe their schedule later.
  IF NEW.status = 'accepted' THEN
    UPDATE participations p SET status = 'withdrawn'
    FROM activities a
    WHERE p.user_id = NEW.user_id AND p.status = 'pending' AND p.activity_id <> NEW.activity_id
      AND a.id = p.activity_id AND a.deleted_at IS NULL AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration) && v_range;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.consume_snap_trail_quota()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user UUID;
  v_count INTEGER;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_snap_trail'));
  DELETE FROM snap_trail_calls WHERE user_id = v_user AND called_at < now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_count FROM snap_trail_calls WHERE user_id = v_user;
  IF v_count >= 200 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  -- 00520 (AB-7): a global daily ceiling protects the shared routing quota.
  IF (SELECT count(*) FROM snap_trail_calls WHERE called_at > now() - INTERVAL '1 day') >= 1500 THEN
    RAISE EXCEPTION 'junto.rate_limited';
  END IF;
  INSERT INTO snap_trail_calls (user_id) VALUES (v_user);
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_message(p_conversation_id uuid, p_content text, p_reply_to_message_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_other UUID;
  v_count INTEGER;
  v_limit INTEGER;
  v_msg_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: a group taken down by moderation is read-only.
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv.id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00520 (C8): in an open discussion, 100 messages a day per member (each
  -- one fans out to every member).
  IF v_conv.type = 'channel' THEN
    PERFORM private.rate_hit('ch:' || v_conv.id::text, 100, INTERVAL '1 day');
  END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = v_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    -- Peer must exist and not be suspended (parity with old send_private_message).
    IF EXISTS (SELECT 1 FROM users WHERE id = v_other AND suspended_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 15;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_limit := 30;
  ELSE
    v_limit := 30;
  END IF;

  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reply_to_message_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM messages m
    WHERE m.id = p_reply_to_message_id
      AND m.conversation_id = p_conversation_id AND m.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_send_message'));
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND conversation_id = p_conversation_id
    AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= v_limit THEN
    IF v_conv.type = 'dm' THEN RAISE EXCEPTION 'junto.dm_rate_limit';
    ELSE RAISE EXCEPTION 'junto.wall_rate_limit'; END IF;
  END IF;
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '1 minute';
  IF v_count >= 60 THEN RAISE EXCEPTION 'junto.send_rate_limit'; END IF;
  -- 00479 (AB-3): daily cap — one account could otherwise fill the database
  -- in under a day (60/min × 2000 chars, no daily bound).
  SELECT count(*) INTO v_count FROM messages
  WHERE sender_id = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_count >= 500 THEN RAISE EXCEPTION 'junto.message_daily_cap'; END IF;

  INSERT INTO messages (conversation_id, sender_id, content, reply_to_message_id)
  VALUES (p_conversation_id, v_user_id, trim(p_content), p_reply_to_message_id)
  RETURNING id INTO v_msg_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = p_conversation_id AND hidden_at IS NOT NULL;

  RETURN v_msg_id;
END;
$function$;
