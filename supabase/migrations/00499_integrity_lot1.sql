-- ============================================================================
-- 00499 — Phase intégrité / anti-spam, lot 1.
-- DX-3  Statistiques d'un compte suspendu : rien. DX-4 Niveaux par sport : dates
--       au mois. DC-6 Alertes : coordonnées, rayon et sport validés, plafond
--       sous verrou. DC-7 Une seule dispo par compte (index unique).
-- MS-8  Un message supprimé reste signalable par un membre ; un canal est
--       signalable. MS-2 Ajouter à un groupe quelqu'un pris dans un blocage :
--       ignoré sans erreur (rien n'est révélé). AB-12 Quelqu'un qui a quitté un
--       groupe n'y est pas remis par les autres pendant 30 jours.
-- MS-3  Une invitation refusée n'est pas renvoyée pour la même sortie.
-- MS-5  Texte des notifications de message nettoyé des caractères de contrôle.
-- AB-14 Recherche de canaux bornée. B11 Site web d'un pro : http(s) seulement.
-- ID-3  Avatar : seulement une image de son propre dossier du stockage.
-- ============================================================================

CREATE TABLE IF NOT EXISTS conversation_departures (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
ALTER TABLE conversation_departures ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_departures FORCE ROW LEVEL SECURITY;
REVOKE ALL ON conversation_departures FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS invitation_declines (
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (activity_id, user_id)
);
ALTER TABLE invitation_declines ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitation_declines FORCE ROW LEVEL SECURITY;
REVOKE ALL ON invitation_declines FROM PUBLIC, anon, authenticated;

CREATE UNIQUE INDEX IF NOT EXISTS discovery_availabilities_one_per_user ON discovery_availabilities (user_id);

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

CREATE OR REPLACE FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text DEFAULT NULL::text, p_levels text[] DEFAULT NULL::text[], p_starts_on date DEFAULT NULL::date, p_ends_on date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_alert_count INTEGER;
  v_alert_id UUID;
  v_allowed_levels TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
  v_level TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00499 (DC-6): validated inputs.
  IF p_lng IS NULL OR p_lat IS NULL OR p_lng NOT BETWEEN -180 AND 180 OR p_lat NOT BETWEEN -90 AND 90
     OR p_radius_km IS NULL OR p_radius_km NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_sport_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = p_sport_key AND s.is_active) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Serialise the cap.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_alerts'));

  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'junto.alert_limit_reached';
  END IF;

  IF p_levels IS NOT NULL THEN
    IF array_length(p_levels, 1) IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    FOREACH v_level IN ARRAY p_levels LOOP
      IF NOT (v_level = ANY(v_allowed_levels)) THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
    END LOOP;
  END IF;

  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < current_date THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;

  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, levels, starts_on, ends_on, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_levels,
    p_starts_on,
    p_ends_on,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
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

  IF p_target_type NOT IN ('user', 'activity', 'wall_message', 'private_message',
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
  IF p_target_type = 'wall_message' AND NOT EXISTS (SELECT 1 FROM wall_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'private_message' AND NOT EXISTS (SELECT 1 FROM private_messages WHERE id = p_target_id) THEN
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

CREATE OR REPLACE FUNCTION public.add_group_member(p_conversation_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_member_count INTEGER;
  v_added_today INTEGER;
  v_caller_name TEXT;
  v_group_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT name INTO v_group_name FROM conversations
  WHERE id = p_conversation_id AND type = 'group';
  IF v_group_name IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_user_id IS NULL OR p_user_id = v_user_id
     OR NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF private.is_conversation_member(p_conversation_id, p_user_id) THEN RETURN; END IF;

  -- Caller lock (30/24h add-rate) + CONVERSATION lock (cap-20 + membership race).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_group_members'));

  SELECT count(*) INTO v_member_count FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_member_count >= 20 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  SELECT count(*) INTO v_added_today FROM conversation_members
  WHERE added_by = v_user_id AND joined_at > now() - INTERVAL '24 hours';
  IF v_added_today >= 30 THEN RAISE EXCEPTION 'junto.group_add_rate_limit'; END IF;

  IF NOT private.is_messaging_eligible(v_user_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users bu
    JOIN conversation_members cm ON cm.conversation_id = p_conversation_id
    WHERE (bu.blocker_id = p_user_id AND bu.blocked_id = cm.user_id)
       OR (bu.blocker_id = cm.user_id AND bu.blocked_id = p_user_id)
  ) THEN
    -- 00499 (MS-2): skipped silently — an error would tell the adder that
    -- someone in the group blocks (or is blocked by) this person.
    RETURN;
  END IF;
  -- 00499 (AB-12): someone who left this group is not put back by others
  -- for 30 days.
  IF EXISTS (SELECT 1 FROM conversation_departures d
             WHERE d.conversation_id = p_conversation_id AND d.user_id = p_user_id
               AND d.at > now() - INTERVAL '30 days') THEN
    RAISE EXCEPTION 'junto.member_left_recently';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, p_user_id, v_user_id, now())
  ON CONFLICT DO NOTHING;

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_user_id, 'group_added',
    coalesce(v_caller_name, 'Quelqu''un') || ' t''ajoute au groupe',
    v_group_name, jsonb_build_object('conversation_id', p_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_caller_name, 'Quelqu''un'), 'group', v_group_name))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.leave_group(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_left INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM conversations WHERE id = p_conversation_id AND type = 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize with adds/other leavers so the empty-cleanup can't race.
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_group_members'));

  DELETE FROM conversation_members
  WHERE conversation_id = p_conversation_id AND user_id = v_user_id;
  -- 00499 (AB-12): remember the departure (others cannot re-add for 30 days).
  INSERT INTO conversation_departures (conversation_id, user_id, at)
  VALUES (p_conversation_id, v_user_id, now())
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET at = now();

  SELECT count(*) INTO v_left FROM conversation_members
  WHERE conversation_id = p_conversation_id;
  IF v_left = 0 THEN
    DELETE FROM conversations WHERE id = p_conversation_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_n INTEGER;
  v_daily INTEGER;
  v_written INTEGER := 0;
  v_target UUID;
  v_existing RECORD;
  v_clean_msg TEXT;
  v_sender_name TEXT;
  v_clean_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_n := array_length(p_user_ids, 1);
  IF p_user_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_n > 20 THEN RAISE EXCEPTION 'junto.invite_cap'; END IF;

  IF p_message IS NOT NULL AND char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'junto.message_too_long';
  END IF;
  v_clean_msg := NULLIF(regexp_replace(trim(COALESCE(p_message, '')), '<[^>]*>', '', 'g'), '');

  SELECT id, title, creator_id, status, deleted_at, is_demo INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_activity.creator_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_invite'));
  SELECT count(*) INTO v_daily FROM participations
  WHERE invited_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 30 THEN RAISE EXCEPTION 'junto.invite_daily_cap'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  PERFORM set_config('junto.bypass_lock', 'true', true);

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL AND is_demo = false);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    -- 00499 (MS-3): someone who declined this outing's invitation is not
    -- invited to it again.
    CONTINUE WHEN EXISTS (SELECT 1 FROM invitation_declines d
                          WHERE d.activity_id = p_activity_id AND d.user_id = v_target);

    SELECT id, status INTO v_existing FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_target;

    IF v_existing.id IS NULL THEN
      EXIT WHEN v_daily + v_written >= 30;  -- in-loop cap (no single-batch overshoot)
      INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
      VALUES (p_activity_id, v_target, 'invited', v_user_id, v_clean_msg, now());
      v_written := v_written + 1;
    ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
      EXIT WHEN v_daily + v_written >= 30;
      UPDATE participations
      SET status = 'invited', invited_by = v_user_id, invite_message = v_clean_msg,
          created_at = now(), refused_at = NULL, left_at = NULL
      WHERE id = v_existing.id;
      v_written := v_written + 1;
    ELSE
      CONTINUE;
    END IF;

    PERFORM create_notification(
      v_target, 'activity_invitation',
      coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
      '« ' || v_clean_title || ' »', jsonb_build_object('activity_id', p_activity_id, 'type', 'activity_invitation',
        'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.decline_activity_invitation(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- No refused_at (no cooldown inflicted), no notification (silent), row
  -- deleted so a later re-invite is a clean INSERT. Not invited → no-op.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  DELETE FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
  -- 00499 (MS-3): remembered, so the invitation is not sent again.
  IF FOUND THEN
    INSERT INTO invitation_declines (activity_id, user_id, at) VALUES (p_activity_id, v_user_id, now())
    ON CONFLICT (activity_id, user_id) DO UPDATE SET at = now();
  END IF;
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

CREATE OR REPLACE FUNCTION public.search_channels(p_query text DEFAULT NULL::text, p_sport_key text DEFAULT NULL::text, p_near_lng double precision DEFAULT NULL::double precision, p_near_lat double precision DEFAULT NULL::double precision)
 RETURNS TABLE(conversation_id uuid, name text, sport_key text, base_label text, radius_km integer, description text, photo_url text, distance_km double precision, member_count integer, is_member boolean, is_creator boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_near GEOGRAPHY;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- 00499 (AB-14): bounded query.
  IF p_query IS NOT NULL AND char_length(p_query) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_near := CASE WHEN p_near_lng IS NOT NULL AND p_near_lat IS NOT NULL
                 THEN ST_SetSRID(ST_MakePoint(p_near_lng, p_near_lat), 4326)::geography END;

  RETURN QUERY
  SELECT c.conversation_id, conv.name, c.sport_key, c.base_label, c.radius_km, c.description, c.photo_url,
         CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) / 1000.0 END AS distance_km,
         (SELECT count(*)::int FROM conversation_members m WHERE m.conversation_id = c.conversation_id) AS member_count,
         EXISTS (SELECT 1 FROM conversation_members m WHERE m.conversation_id = c.conversation_id AND m.user_id = v_user_id) AS is_member,
         (c.created_by = v_user_id) AS is_creator
  FROM channels c
  JOIN conversations conv ON conv.id = c.conversation_id
  WHERE c.closed_at IS NULL
    AND (p_sport_key IS NULL OR p_sport_key = c.sport_key)
    AND (p_query IS NULL
         OR conv.name ILIKE '%' || p_query || '%'
         OR c.base_label ILIKE '%' || p_query || '%'
         OR c.sport_key ILIKE '%' || p_query || '%'
         OR coalesce(c.description, '') ILIKE '%' || p_query || '%')
    AND (v_near IS NULL OR ST_DWithin(c.base, v_near, c.radius_km * 1000.0))
    AND NOT EXISTS (SELECT 1 FROM channel_bans b WHERE b.conversation_id = c.conversation_id AND b.user_id = v_user_id)
  ORDER BY
    CASE WHEN v_near IS NULL THEN NULL ELSE ST_Distance(c.base, v_near) END ASC NULLS LAST,
    (SELECT count(*) FROM conversation_members m WHERE m.conversation_id = c.conversation_id) DESC,
    c.created_at DESC
  LIMIT 60;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_pro_profile(p_display_name text DEFAULT NULL::text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text, p_company_name text DEFAULT NULL::text, p_real_name text DEFAULT NULL::text, p_clear text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_existing RECORD;
  v_location_changing BOOLEAN := false;
  v_clear TEXT[] := COALESCE(p_clear, ARRAY[]::TEXT[]);
  v_col TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_existing IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00443 B3 : une fois APPROUVÉ, raison sociale et identité sont gelées —
  -- les renvoyer inchangées est permis, les changer passe par nous.
  IF v_existing.status = 'approved' THEN
    IF (p_company_name IS NOT NULL
        AND trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.company_name)
       OR (p_real_name IS NOT NULL
        AND trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.real_name) THEN
      RAISE EXCEPTION 'junto.pro_identity_locked';
    END IF;
  END IF;

  -- 00444 (1) : liste blanche des colonnes vidables. ≤ 7 entrées, toutes connues.
  IF array_length(v_clear, 1) > 7 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  FOREACH v_col IN ARRAY v_clear LOOP
    IF v_col IS NULL OR v_col NOT IN ('tagline', 'description', 'website', 'email', 'phone', 'instagram', 'facebook') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END LOOP;

  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00444 (2) : cooldown seulement pour une enseigne publique (approved).
    IF v_existing.status = 'approved'
       AND v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'junto.pro_location_cooldown';
    END IF;
    v_location_changing := true;
  END IF;

  IF p_display_name IS NOT NULL AND (char_length(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_real_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00499 (B11): a tappable link must be a web address (no javascript:, data:…).
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_primary_location_name) > 200) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET
    display_name = COALESCE(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g')), display_name),
    company_name = CASE WHEN p_company_name IS NOT NULL THEN trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) ELSE company_name END,
    real_name = CASE WHEN p_real_name IS NOT NULL THEN trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) ELSE real_name END,
    tagline = CASE WHEN 'tagline' = ANY(v_clear) THEN NULL
                   WHEN p_tagline IS NOT NULL THEN trim(regexp_replace(p_tagline, '<[^>]*>', '', 'g')) ELSE tagline END,
    description = CASE WHEN 'description' = ANY(v_clear) THEN NULL
                       WHEN p_description IS NOT NULL THEN trim(regexp_replace(p_description, '<[^>]*>', '', 'g')) ELSE description END,
    website = CASE WHEN 'website' = ANY(v_clear) THEN NULL ELSE COALESCE(p_website, website) END,
    email = CASE WHEN 'email' = ANY(v_clear) THEN NULL ELSE COALESCE(p_email, email) END,
    phone = CASE WHEN 'phone' = ANY(v_clear) THEN NULL ELSE COALESCE(p_phone, phone) END,
    instagram = CASE WHEN 'instagram' = ANY(v_clear) THEN NULL ELSE COALESCE(p_instagram, instagram) END,
    facebook = CASE WHEN 'facebook' = ANY(v_clear) THEN NULL ELSE COALESCE(p_facebook, facebook) END,
    primary_lng = CASE WHEN v_location_changing THEN p_primary_lng ELSE primary_lng END,
    primary_lat = CASE WHEN v_location_changing THEN p_primary_lat ELSE primary_lat END,
    primary_location = CASE WHEN v_location_changing
                            THEN ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography
                            ELSE primary_location END,
    primary_location_name = CASE WHEN v_location_changing THEN trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g')) ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$function$;


-- ---------- ID-3 : avatar dans son propre dossier ----------
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
  IF NEW.avatar_url NOT LIKE 'https://lvjlthzdydzatcvwwriu.supabase.co/storage/v1/object/public/avatars/' || NEW.id::text || '/%' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.check_avatar_url() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_users_avatar_url ON users;
CREATE TRIGGER trg_users_avatar_url BEFORE UPDATE OF avatar_url ON users
  FOR EACH ROW EXECUTE FUNCTION private.check_avatar_url();
