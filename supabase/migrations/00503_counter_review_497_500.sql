-- ============================================================================
-- 00503 — Contre-vérification de 00497-00500.
-- Créneaux : une demande d'inscription (en attente) est aussi refusée si elle
--   chevauche une sortie où l'on est déjà accepté (l'organisateur n'apprend
--   plus rien en acceptant) ; l'organisateur ne déplace pas sa sortie sur un
--   créneau où il est déjà pris.
-- MS-3  Une invitation refusée ne revient pas par l'acceptation d'un contact.
-- ID-3  Avatar et photos de canal : pas de remontée « .. » hors du dossier.
-- MS-5  Titre des notifications de message nettoyé (et paramètres côté envoi).
-- DX-3  Niveaux, votes de niveau et agrégats de trophées : rien pour un
--       compte suspendu. upsert_dispo sérialisée.
-- ============================================================================

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
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_activity(p_activity_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_level text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_meeting_lng double precision DEFAULT NULL::double precision, p_meeting_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT NULL::text, p_visibility text DEFAULT NULL::text, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_old RECORD;
  v_new RECORD;
  v_participant RECORD;
  v_trimmed_title TEXT;
  v_level_max TEXT;
  v_changes JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_update', 30, INTERVAL '1 hour');

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;
  END IF;

  -- Normalised range high end (only applied when the level is being edited).
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF p_level IS NOT NULL AND v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, max_participants, level, visibility, deleted_at
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00494 (BR-8): an outing removed by moderation is frozen.
  IF v_old.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- The client resends starts_at as an ISO string (millisecond precision)
  -- while Postgres stores microseconds — a raw IS DISTINCT FROM would see a
  -- sub-millisecond ghost diff on any row whose date has non-zero µs (seed,
  -- manual INSERTs) and re-trigger the date_in_past bug plus phantom
  -- "activity updated" notifs. Normalise: an unchanged-at-ms-precision date
  -- is treated as "not provided" for everything downstream (validation,
  -- UPDATE, change diff).
  IF p_starts_at IS NOT NULL
     AND date_trunc('milliseconds', p_starts_at) IS NOT DISTINCT FROM date_trunc('milliseconds', v_old.starts_at) THEN
    p_starts_at := NULL;
  END IF;

  -- Only validate the date when it actually changes — resending the
  -- unchanged (now past) starts_at of an in-progress activity is not a
  -- reschedule and must not block editing the other fields.
  -- 00503: the organiser cannot move their outing onto a slot where they are
  -- already accepted elsewhere (participants are told of the change).
  IF (p_starts_at IS NOT NULL OR p_duration IS NOT NULL) AND NOT EXISTS (
       SELECT 1 FROM activities x WHERE x.id = p_activity_id AND x.is_demo) AND EXISTS (
    SELECT 1 FROM participations p JOIN activities a ON a.id = p.activity_id
    WHERE p.user_id = v_user_id AND p.status = 'accepted' AND p.activity_id <> p_activity_id
      AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration)
          && tstzrange(coalesce(p_starts_at, v_old.starts_at),
                       coalesce(p_starts_at, v_old.starts_at) + coalesce(p_duration::interval, v_old.duration))
  ) THEN
    RAISE EXCEPTION 'junto.schedule_conflict';
  END IF;

  -- 00494 (BR-7): once under way, an outing's date no longer moves (it
  -- would leave « in progress » with a future start).
  IF p_starts_at IS NOT NULL AND v_old.status = 'in_progress' THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  -- 00496 (BR-7): nor its duration (the app locks it; the server too).
  IF p_duration IS NOT NULL AND v_old.status = 'in_progress'
     AND p_duration::interval IS DISTINCT FROM v_old.duration THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  IF p_starts_at IS NOT NULL THEN
    IF p_starts_at <= NOW() THEN
      RAISE EXCEPTION 'junto.date_in_past';
    END IF;
    IF p_starts_at > NOW() + INTERVAL '6 months' THEN
      RAISE EXCEPTION 'junto.date_too_far';
    END IF;
  END IF;

  -- p_max_participants = 0 is the explicit "make it open" sentinel (NULL
  -- means "unchanged", so it can't express open — the edit screen's open
  -- toggle silently did nothing before this). 0 sits outside the valid
  -- [2,50] range so it can't collide with a real cap. Any other
  -- out-of-range value is rejected (parity with create_activity — before
  -- this it surfaced as a raw table CHECK violation).
  IF p_max_participants IS NOT NULL AND p_max_participants != 0
     AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic. Parity with create_activity.
  IF p_visibility IS NOT NULL
     AND p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Private-link visibilities open to all (Scott 2026-07-10) — no gate.

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    level_max = CASE WHEN p_level IS NOT NULL THEN v_level_max ELSE level_max END,
    max_participants = CASE
      WHEN p_max_participants = 0 THEN NULL
      WHEN p_max_participants IS NOT NULL THEN p_max_participants
      ELSE max_participants END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting END,
    -- Only alongside a pin move (00441); the trigger freezes it otherwise.
    meeting_locality = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
                THEN left(trim(p_meeting_locality), 80) ELSE NULL END
      ELSE meeting_locality END,
    starts_at = COALESCE(p_starts_at, starts_at),
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE duration END,
    visibility = COALESCE(p_visibility, visibility)
  WHERE id = p_activity_id;

  -- Re-fetch after the UPDATE (whitelist trigger may have forced privileged
  -- columns back to OLD when participants exist — only notify on real changes).
  SELECT title, description, starts_at, duration, location_meeting,
         max_participants, level, visibility
  INTO v_new FROM activities WHERE id = p_activity_id;

  -- 00489 (AC-8): turning a public / on-request outing private rotates its
  -- link — anyone who saw the old token while it was public loses access.
  IF v_old.visibility IN ('public', 'approval')
     AND v_new.visibility IN ('private_link', 'private_link_approval') THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE activities SET invite_token = gen_random_uuid() WHERE id = p_activity_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    DELETE FROM invite_grants WHERE activity_id = p_activity_id;
  END IF;

  v_changes := '{}'::jsonb;
  IF v_old.title IS DISTINCT FROM v_new.title THEN
    v_changes := v_changes || jsonb_build_object('title', true);
  END IF;
  IF v_old.starts_at IS DISTINCT FROM v_new.starts_at THEN
    v_changes := v_changes || jsonb_build_object('starts_at', true);
  END IF;
  IF v_old.duration IS DISTINCT FROM v_new.duration THEN
    v_changes := v_changes || jsonb_build_object('duration', true);
  END IF;
  IF v_old.location_meeting IS DISTINCT FROM v_new.location_meeting THEN
    v_changes := v_changes || jsonb_build_object('location_meeting', true);
  END IF;
  IF v_old.description IS DISTINCT FROM v_new.description THEN
    v_changes := v_changes || jsonb_build_object('description', true);
  END IF;
  IF v_old.level IS DISTINCT FROM v_new.level THEN
    v_changes := v_changes || jsonb_build_object('level', true);
  END IF;
  IF v_old.max_participants IS DISTINCT FROM v_new.max_participants THEN
    v_changes := v_changes || jsonb_build_object('max_participants', true);
  END IF;
  IF v_old.visibility IS DISTINCT FROM v_new.visibility THEN
    v_changes := v_changes || jsonb_build_object('visibility', true);
  END IF;

  -- No real change happened (every requested field was rejected by trigger or unchanged) — skip notif
  IF v_changes = '{}'::jsonb THEN RETURN; END IF;

  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_updated',
      'Sortie modifiée',
      '« ' || v_new.title || ' » a changé — vérifie l''heure et le rendez-vous.',
      jsonb_build_object('activity_id', p_activity_id, 'changes', v_changes,
        'params', jsonb_build_object('title', v_new.title))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_contact_request(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_name TEXT;
  v_act RECORD;
  v_existing RECORD;
  v_sender_name TEXT;
  v_rows INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00496 (BR-4): accepting a contact is an action — onboarded accounts only.
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.age_confirmed_at IS NOT NULL AND u.accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- FOR UPDATE : sérialise accept ⨯ accept (double message d'amorce) et
  -- accept ⨯ decline (un refus ne peut plus être ressuscité en actif).
  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id FOR UPDATE;
  IF v_conv.id IS NULL OR v_conv.type != 'dm' OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Une demande expirée ne s'accepte plus (elle a déjà disparu des Demandes ;
  -- seul un conversation_id rejoué pouvait encore la flipper).
  IF v_conv.request_expires_at IS NOT NULL AND v_conv.request_expires_at < NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Don't connect to a sender who was suspended after sending the request.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_conv.request_sender_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Defense-in-depth: a block that appeared meanwhile forbids the acceptance.
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_conv.request_sender_id)
       OR (blocker_id = v_conv.request_sender_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE conversations
  SET status = 'active', request_expires_at = NULL, last_message_at = now()
  WHERE id = p_conversation_id AND status = 'pending_request';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- The request message becomes the first message of the thread.
  IF v_conv.request_message IS NOT NULL AND char_length(trim(v_conv.request_message)) > 0 THEN
    INSERT INTO messages (conversation_id, sender_id, content, created_at)
    VALUES (p_conversation_id, v_conv.request_sender_id, v_conv.request_message, now());
  END IF;

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_conv.request_sender_id,
    'contact_request_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ta demande de contact',
    '',
    jsonb_build_object('conversation_id', p_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un')))
  );

  -- Discovery invite: the request was framed around one of the sender's
  -- activities. The pair is connected now, so the anti-cold gate holds —
  -- materialise the invitation as an 'invited' participation (the accepter
  -- still confirms the outing via the activity screen; capacity is checked
  -- there). Consume the link regardless of outcome.
  IF v_conv.pending_activity_id IS NOT NULL THEN
    SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo
    INTO v_act FROM activities a WHERE a.id = v_conv.pending_activity_id;

    IF v_act.id IS NOT NULL AND v_act.deleted_at IS NULL AND NOT v_act.is_demo
       AND v_act.creator_id = v_conv.request_sender_id
       AND v_act.status IN ('published', 'in_progress')
       -- 00503 (MS-3): not an outing this person already declined.
       AND NOT EXISTS (SELECT 1 FROM invitation_declines d WHERE d.activity_id = v_act.id AND d.user_id = v_user_id) THEN

      SELECT id, status INTO v_existing FROM participations
      WHERE activity_id = v_act.id AND user_id = v_user_id;

      PERFORM set_config('junto.bypass_lock', 'true', true);
      IF v_existing.id IS NULL THEN
        INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
        VALUES (v_act.id, v_user_id, 'invited', v_conv.request_sender_id, NULL, now());
      ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
        UPDATE participations
        SET status = 'invited', invited_by = v_conv.request_sender_id,
            invite_message = NULL, created_at = now(), refused_at = NULL, left_at = NULL
        WHERE id = v_existing.id;
      END IF;
      PERFORM set_config('junto.bypass_lock', 'false', true);

      IF v_existing.id IS NULL OR v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
        SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_conv.request_sender_id;
        PERFORM create_notification(
          v_user_id,
          'activity_invitation',
          coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
          '« ' || regexp_replace(v_act.title, '<[^>]*>', '', 'g') || ' »',
          jsonb_build_object('activity_id', v_act.id, 'type', 'activity_invitation',
            'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', regexp_replace(v_act.title, '<[^>]*>', '', 'g')))
        );
      END IF;
    ELSE
      -- La sortie liée n'existe plus (annulée/supprimée/terminée) : au lieu
      -- d'un silence total, dire à l'accepteur pourquoi rien n'apparaît dans
      -- ses Invitations. Le fil, lui, reste connecté (voulu).
      PERFORM create_notification(
        v_user_id,
        'invite_activity_gone',
        'Cette sortie n''est plus disponible',
        coalesce('« ' || regexp_replace(v_act.title, '<[^>]*>', '', 'g') || ' »', ''),
        jsonb_build_object('conversation_id', p_conversation_id,
          'params', jsonb_build_object('title', coalesce(regexp_replace(v_act.title, '<[^>]*>', '', 'g'), '')))
      );
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations SET pending_activity_id = NULL WHERE id = p_conversation_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.check_avatar_url()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only the person editing their own profile (demo seeding by an admin and
  -- system writes keep their URLs). NOTE migration: project host below.
  IF auth.uid() IS DISTINCT FROM NEW.id THEN RETURN NEW; END IF;
  IF NEW.avatar_url IS NOT DISTINCT FROM OLD.avatar_url OR NEW.avatar_url IS NULL THEN RETURN NEW; END IF;
  IF NEW.avatar_url NOT LIKE 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/avatars/' || NEW.id::text || '/%'
     OR NEW.avatar_url ~* '(\.\.|%2e|%2f|%5c|\\)' THEN  -- 00503: no climbing out of the folder
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_channel_photo(p_conversation_id uuid, p_photo_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_photo TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM channels
    WHERE conversation_id = p_conversation_id
      AND created_by = v_user_id
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR v_photo NOT LIKE 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
       OR v_photo ~* '(\.\.|%2e|%2f|%5c|\\)'  -- 00503
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE channels SET photo_url = v_photo WHERE conversation_id = p_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_channel(p_name text, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_sport_key text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text, p_force boolean DEFAULT false)
 RETURNS TABLE(conversation_id uuid, duplicate boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_desc TEXT;
  v_label TEXT;
  v_base GEOGRAPHY;
  v_sport TEXT;
  v_photo TEXT;
  v_open_count INTEGER;
  v_daily INTEGER;
  v_existing UUID;
  v_conv_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_name IS NULL OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.channel_name';
  END IF;

  v_clean_desc := NULLIF(trim(regexp_replace(COALESCE(p_description, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean_desc IS NOT NULL AND char_length(v_clean_desc) > 500 THEN
    RAISE EXCEPTION 'junto.channel_desc';
  END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.channel_place';
  END IF;
  v_base := ST_SetSRID(ST_MakePoint(p_base_lng, p_base_lat), 4326)::geography;

  IF p_radius_km IS NULL OR p_radius_km NOT IN (35, 60, 100) THEN
    RAISE EXCEPTION 'junto.channel_radius';
  END IF;

  v_sport := NULLIF(trim(p_sport_key), '');
  IF v_sport IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = v_sport AND s.is_active) THEN
    RAISE EXCEPTION 'junto.channel_sport';
  END IF;

  -- Photo OPTIONAL: must be a public URL at the PROJECT storage origin, in the
  -- channel-photos bucket, under the caller's own {uid} folder. Host-anchored
  -- (no leading wildcard) so an external look-alike host cannot pass.
  v_photo := NULLIF(trim(p_photo_url), '');
  IF v_photo IS NOT NULL AND (
       char_length(v_photo) > 500
       OR v_photo NOT LIKE 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
       OR v_photo ~* '(\.\.|%2e|%2f|%5c|\\)'  -- 00503
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_channel'));
  SELECT count(*) INTO v_open_count FROM channels
  WHERE created_by = v_user_id AND closed_at IS NULL;
  IF v_open_count >= 5 THEN RAISE EXCEPTION 'junto.channel_cap'; END IF;
  SELECT count(*) INTO v_daily FROM channels
  WHERE created_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.channel_rate_limit'; END IF;

  IF NOT p_force THEN
    SELECT c.conversation_id INTO v_existing
    FROM channels c
    WHERE c.closed_at IS NULL
      AND ST_DWithin(c.base, v_base, c.radius_km * 1000.0)
    ORDER BY ST_Distance(c.base, v_base) ASC
    LIMIT 1;
    IF v_existing IS NOT NULL THEN
      RETURN QUERY SELECT v_existing, true;
      RETURN;
    END IF;
  END IF;

  INSERT INTO conversations (type, status, name, created_by, created_at, last_message_at)
  VALUES ('channel', 'active', v_clean_name, v_user_id, now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO channels (conversation_id, sport_key, base, base_label, radius_km, description, photo_url, created_by, created_at)
  VALUES (v_conv_id, v_sport, v_base, v_label, p_radius_km, v_clean_desc, v_photo, v_user_id, now());

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());

  RETURN QUERY SELECT v_conv_id, false;
END;
$function$;

CREATE OR REPLACE FUNCTION public.broadcast_and_push_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_conv RECORD;
  v_sender_name TEXT;
  v_secret TEXT;
  v_recipients UUID[];
  v_uid UUID;
  v_title TEXT;
BEGIN
  SELECT type, name, activity_id INTO v_conv
  FROM conversations WHERE id = NEW.conversation_id;

  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'messages', 'op', 'INSERT',
                         'conversation_id', NEW.conversation_id, 'message_id', NEW.id),
      'change', 'conversation:' || NEW.conversation_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  IF v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('table', 'messages', 'op', 'INSERT',
                           'conversation_id', NEW.conversation_id),
        'wall', 'activity:' || v_conv.activity_id::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  SELECT array_agg(cm.user_id) INTO v_recipients
  FROM conversation_members cm
  WHERE cm.conversation_id = NEW.conversation_id
    AND cm.user_id IS DISTINCT FROM NEW.sender_id
    -- 00472 (audit L12): a suspended member gets no message push or live event
    -- (create_notification already skipped them; the two paths now agree).
    AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = cm.user_id AND u.suspended_at IS NOT NULL)
    AND (NEW.sender_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE b.blocker_id = cm.user_id AND b.blocked_id = NEW.sender_id
    ));
  IF v_recipients IS NULL OR array_length(v_recipients, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  FOREACH v_uid IN ARRAY v_recipients LOOP
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('conversation_id', NEW.conversation_id),
        'inbox', 'user:' || v_uid::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;

  -- Push leg — skipped for rows mirrored from a legacy writer (already pushed).
  IF current_setting('junto.skip_message_push', true) IS DISTINCT FROM 'true' THEN
    IF NEW.sender_id IS NOT NULL THEN
      SELECT display_name INTO v_sender_name FROM users WHERE id = NEW.sender_id;
    END IF;
    v_title := coalesce(v_sender_name, 'Junto');
    IF v_conv.type = 'group' AND v_conv.name IS NOT NULL THEN
      v_title := v_title || ' · ' || v_conv.name;
    ELSIF v_conv.type = 'activity' THEN
      SELECT v_title || ' · ' || regexp_replace(a.title, '<[^>]*>', '', 'g')
      INTO v_title FROM activities a WHERE a.id = v_conv.activity_id;
    END IF;

    v_title := regexp_replace(v_title, '[[:cntrl:]]', ' ', 'g');  -- 00503 (MS-5)

    SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
    IF v_secret IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json',
                                        'x-junto-push-secret', v_secret),
          body := jsonb_build_object(
            'user_ids', to_jsonb(v_recipients),
            'title', v_title,
            'body', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140),
            -- 00437 : pour un fil d'ACTIVITÉ, on ajoute activity_id. Sans lui, le
            -- routeur push ouvrait /conversation/{id} — l'écran DM/groupe, qui ne
            -- sait pas afficher un fil d'activité (le mur vit dans l'onglet chat de
            -- l'écran d'activité). Les DM et groupes gardent le payload d'origine.
            'data', CASE
              WHEN v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'activity_id', v_conv.activity_id,
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'context', (SELECT regexp_replace(a.title, '<[^>]*>', '', 'g') FROM activities a WHERE a.id = v_conv.activity_id),
                                     'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
              WHEN v_conv.name IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'context', v_conv.name, 'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
              ELSE
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message', 'variant', 'dm',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'Junto'),
                                     'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
            END,
            'collapseId', 'message-' || NEW.conversation_id::text
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[] DEFAULT NULL::text[], p_about text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_id UUID;
  v_label TEXT;
  v_intent TEXT[];
  v_about TEXT;
  v_lng DOUBLE PRECISION;
  v_lat DOUBLE PRECISION;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR array_length(p_sport_keys, 1) NOT BETWEEN 1 AND 3
     OR EXISTS (SELECT 1 FROM unnest(p_sport_keys) k
                WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k AND s.is_active))
  THEN RAISE EXCEPTION 'junto.dispo_sports'; END IF;

  -- Levels: optional. If present it MUST be an object whose keys ⊆ chosen sports
  -- and whose values are short strings (cotation codes) — no unbounded / non-object
  -- blob can be stored and fanned out to matches.
  IF p_levels IS NOT NULL THEN
    IF jsonb_typeof(p_levels) <> 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(p_levels) AS lk(sport)
         WHERE lk.sport <> ALL(p_sport_keys)
       )
       OR EXISTS (
         SELECT 1 FROM jsonb_each_text(p_levels) AS e(k, v)
         WHERE v IS NULL OR char_length(v) > 20
       )
    THEN RAISE EXCEPTION 'junto.dispo_levels'; END IF;
  END IF;

  IF p_intent IS NULL OR cardinality(p_intent) = 0 THEN
    v_intent := NULL;
  ELSIF NOT (p_intent <@ ARRAY[
              'discovery','progression','performance','detente','conviviality',
              'dog','child','group','solo','active','calm','early',
              'nature','challenge','photo','mixed','same_level','beginners',
              'long_outing','after_work','regular','adapted','training',
              'experienced','competition'
            ]::text[])
        OR cardinality(p_intent) > 10 THEN
    RAISE EXCEPTION 'junto.dispo_intent';
  ELSE
    v_intent := p_intent;
  END IF;

  v_about := NULLIF(trim(regexp_replace(COALESCE(p_about, ''), '<[^>]*>', '', 'g')), '');
  IF v_about IS NOT NULL AND (
       char_length(v_about) > 1600
       OR array_length(regexp_split_to_array(v_about, '\s+'), 1) > 250
     ) THEN
    RAISE EXCEPTION 'junto.dispo_about';
  END IF;

  IF p_radius_km IS NOT NULL AND p_radius_km NOT IN (5, 10, 15, 30, 50) THEN
    RAISE EXCEPTION 'junto.dispo_radius';
  END IF;

  IF p_transport_modes IS NULL OR array_length(p_transport_modes, 1) IS NULL
     OR array_length(p_transport_modes, 1) < 1
     OR NOT (p_transport_modes <@ ARRAY['car', 'motorbike', 'bike', 'on_foot', 'public_transport'])
  THEN RAISE EXCEPTION 'junto.dispo_transport'; END IF;

  IF p_window_start IS NULL OR p_window_end IS NULL OR p_window_end <= p_window_start
     OR p_window_end > now() + INTERVAL '4 weeks' OR p_window_start < now() - INTERVAL '1 day'
  THEN RAISE EXCEPTION 'junto.dispo_window'; END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90
  THEN RAISE EXCEPTION 'junto.dispo_place'; END IF;

  -- 00485 (DC-1 / DX-2): the base is rounded to ~1 km BEFORE it is stored,
  -- so no read or matching probe can ever recover an exact address.
  v_lng := round(p_base_lng::numeric, 2)::float8;
  v_lat := round(p_base_lat::numeric, 2)::float8;

  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.dispo_place';
  END IF;

  -- 00488: counted only once every input check has passed.
  PERFORM private.rate_hit('dispo', 30, INTERVAL '1 day');

  -- 00503: serialised (one dispo per account is a unique index since 00499).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dispo'));
  SELECT id INTO v_id FROM discovery_availabilities WHERE user_id = v_user_id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO discovery_availabilities
      (user_id, sport_keys, levels, intent, about, base, base_label, radius_km, transport_modes, window_start, window_end)
    VALUES
      (v_user_id, p_sport_keys, p_levels, v_intent, v_about,
       ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
       v_label, p_radius_km, p_transport_modes, p_window_start, p_window_end)
    RETURNING id INTO v_id;
  ELSE
    UPDATE discovery_availabilities SET
      sport_keys = p_sport_keys, levels = p_levels, intent = v_intent, about = v_about,
      base = ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
      base_label = v_label, radius_km = p_radius_km, transport_modes = p_transport_modes,
      window_start = p_window_start, window_end = p_window_end
    WHERE id = v_id;
  END IF;
  RETURN v_id;
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
      AND a.status = 'completed'
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
    AND rv.created_at >= now() - INTERVAL '12 months'   -- sliding freshness window
    -- 00493 (IX-3): demo curtain.
    AND (NOT EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo) OR demo_content_visible())
  GROUP BY s.key
  HAVING count(*) > 0;
$function$;
