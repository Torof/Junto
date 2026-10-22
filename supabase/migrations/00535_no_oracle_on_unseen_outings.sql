-- 00535 — no oracle on outings one cannot see (audit 2026-10-23, L-3 / outings F4).
--
-- With only an outing's id, a stranger (or someone removed / blocked / who left)
-- could learn whether a PRIVATE outing exists, its exact start time (by
-- bisecting confirm_presence_via_geo's distinct errors), its status
-- (transition_single_activity) and existence (create_report succeeded only on
-- real ids). private.can_see_activity reproduces the read rules (organiser,
-- participant, public/approval live outing, private access) and gates them:
-- * confirm_presence_via_geo: an accepted participation is checked FIRST, and
--   coordinates are range-checked (they used to wrap around);
-- * transition_single_activity: does nothing and returns NULL for an outing the
--   caller cannot see (the app still calls it from every visible outing page);
-- * create_report on an outing: same generic refusal for unknown and unseen.

CREATE OR REPLACE FUNCTION private.can_see_activity(p_activity_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      AND (
        a.creator_id = p_user_id
        OR EXISTS (SELECT 1 FROM participations p
                   WHERE p.activity_id = a.id AND p.user_id = p_user_id
                     AND p.status IN ('accepted', 'pending', 'invited'))
        OR (a.visibility IN ('public', 'approval')
            AND a.status IN ('published', 'in_progress')
            AND a.deleted_at IS NULL
            AND (a.is_demo = false OR demo_content_visible())
            AND NOT private.user_is_suspended(a.creator_id))
        OR (a.visibility = 'private_link' AND a.deleted_at IS NULL
            AND private.private_activity_access(a.id, p_user_id))
      )
  );
$function$;
REVOKE ALL ON FUNCTION private.can_see_activity(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.confirm_presence_via_geo(p_activity_id uuid, p_lng double precision, p_lat double precision, p_captured_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_skip_push boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_window_anchor TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
  v_requires_presence BOOLEAN;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration, status, deleted_at, creator_id, requires_presence, is_demo
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id, v_requires_presence, v_is_demo
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00535: an accepted participant only, checked BEFORE any distinct error
  -- (they revealed a private outing's existence, status and start time).
  IF NOT EXISTS (SELECT 1 FROM participations
                 WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00535: real coordinates only (out-of-range values used to wrap around).
  IF p_lng IS NULL OR p_lat IS NULL OR NOT (p_lng BETWEEN -180 AND 180) OR NOT (p_lat BETWEEN -90 AND 90) THEN
    RAISE EXCEPTION 'junto.presence_too_far';
  END IF;

  -- 00429 : une sortie qui ne demande PAS de validation de présence n'a aucun
  -- chemin de confirmation (le finaliseur sort tôt, donc aucun risque de FALSE)
  -- → confirmer y gonflait le score de fiabilité sans risque de baisse.
  IF v_requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;
  -- 00429 : rideau démo côté ÉCRITURE, garde ABSOLUE (admin en mode démo
  -- compris) — même règle que join_activity et que les envois de 00426.
  IF v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- RESTAURÉ (00292) — Invariant : la présence du créateur n'est JAMAIS
  -- auto-attestée. No-op silencieux (pas une erreur : le client ne propose
  -- pas le bouton, un appel direct ne doit simplement rien faire).
  IF v_user_id = v_creator_id THEN RETURN; END IF;

  -- Reject cancelled / expired activities, and soft-deleted ones. The
  -- time-window check below catches future-dated activities, but a
  -- creator cancelling within the validation window would otherwise
  -- still allow validations.
  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    -- 00419 : un événement « capturé dans le futur » est forcément forgé
    -- (2 min de tolérance d'horloge pour les replays offline légitimes).
    IF p_captured_at > now() + INTERVAL '2 minutes' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00429 : la borne d'ARRIVÉE du rejeu passe de fin+3h à fin+24h (alignée
    -- sur la fenêtre de témoignage et sur l'auto-absence). Scénario outdoor
    -- normal : fin 17h, réseau retrouvé à 18h30, app ouverte à 21h → la preuve
    -- était valide et mesurée sur place, elle était jetée. L'anti-fraude réel
    -- reste l'heure de CAPTURE (fenêtre T±15min, vérifiée juste en dessous),
    -- la distance, le refus du futur et l'idempotence — pas l'heure d'arrivée.
    IF now() > v_starts_at + v_duration + INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.presence_window_closed';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  -- CORRIGÉ (00428) : location_start a été SUPPRIMÉE en 00306 (fusionnée dans
  -- location_meeting). 00419 la référençait encore → la fonction levait
  -- « column location_start does not exist » à CHAQUE appel. Les trois points
  -- valides sont meeting / end / trace.
  SELECT
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'junto.presence_too_far';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id, p_skip_push);

  -- RESTAURÉ (00292) — Règle A : un non-créateur qui confirme PROUVE que la
  -- sortie a eu lieu → la présence du créateur est validée automatiquement.
  -- C'est le SEUL chemin de validation du créateur côté géo (il n'est jamais
  -- relancé par les notifications, précisément parce que cette règle existe).
  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, p_activity_id, p_skip_push);
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.transition_single_activity(p_activity_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN NULL;
  END IF;

  -- 00535: nothing done, nothing said, for an outing the caller cannot see.
  IF NOT private.can_see_activity(p_activity_id, v_user_id) THEN RETURN NULL; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  -- 00495: a suspended organiser's outing is frozen (no reminders, no vote
  -- requests, no finalisation) — same as the minute sweep.
  IF private.user_is_suspended(v_activity.creator_id) THEN RETURN v_activity.status; END IF;
  -- 00429 : même garde que le balayage cron — une sortie supprimée ne transite
  -- plus (sinon elle passait 'completed' puis se faisait finaliser).
  IF v_activity.deleted_at IS NOT NULL THEN RETURN v_activity.status; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress', 'completed') THEN
    RETURN v_activity.status;
  END IF;

  IF v_activity.status = 'published'
     AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id
          AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      -- CORRIGÉ (00428) : notify_presence_reminders(UUID) a été SUPPRIMÉE en
      -- 00148 (spine de notifs simplifié) mais l'appel a été transporté
      -- verbatim de migration en migration (00136 → 00225 → 00286 → 00427).
      -- Résultat : cette RPC levait « function does not exist » à chaque
      -- appel, donc le flip completed, la fermeture de fenêtre de présence et
      -- rate_participants côté lazy n'ont JAMAIS tourné (les deux appelants
      -- client avalent l'erreur). Les rappels pré-event vivent dans
      -- notify_presence_pre_warning / _10min, appelés par le balayage cron.
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_creator_qr_reminder(p_activity_id);
  END IF;

  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    -- Solo end-of-window → expired, not completed (see header).
    IF (SELECT count(*) FROM participations p
        WHERE p.activity_id = p_activity_id
        AND p.status = 'accepted'
        AND p.user_id != v_activity.creator_id) = 0
    THEN
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'in_progress';
      IF FOUND THEN
        RETURN 'expired';
      END IF;
    END IF;

    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';
    IF FOUND THEN
      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
    -- 00427: emit rate_participants here too (lazy path) — gates internally
    -- on the real vote window [end+15min, end+24h] + dedup.
    PERFORM notify_rate_participants(p_activity_id);
  END IF;

  RETURN v_activity.status;
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
  -- 00535: an outing one cannot see is answered like an unknown one.
  IF p_target_type = 'activity' AND NOT private.can_see_activity(p_target_id, v_user_id) THEN
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
