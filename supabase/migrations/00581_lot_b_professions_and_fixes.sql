-- ============================================================================
-- 00581 — Lot B de l'audit global (2026-11-04, chaînes validées par Scott).
--
--   1. Métiers d'un pro validé : un ajout devient une demande validée par un
--      admin dans l'app (pending_professions, e-mail, notification).
--   3. Couple bloqué : « Départ confirmé » et l'annulation automatique ne
--      portent plus le nom du pro (comme cancel_booking_pro, 00580).
--   4. trace_geojson_ok : étapes comparées sans conversion, caractères
--      invisibles refusés dans leurs noms.
--   5. presence_end_reminder rejoint l'index anti-doublon des rappels.
--   6. Rappels quotidiens : une ligne en erreur n'annule plus les autres.
--   7. Liens d'agenda : noms des clients masqués par défaut (nouveaux liens).
--
-- Chaque fonction reconstruite part de sa définition LIVE (2026-11-04).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Métiers d'un pro validé : un ajout passe par une demande (Scott 2026-11-04)
--
-- Un pro validé peut retirer ou réordonner ses métiers librement, mais un
-- métier AJOUTÉ part dans pending_professions : invisible sur sa page tant
-- qu'un admin ne l'a pas validé dans l'app (Modération › Pros). La demande
-- envoie un e-mail à askandgo (même canal que les demandes pro, 00561) ; la
-- décision notifie le pro. Un pro en attente / refusé garde l'ancien
-- comportement : sa demande entière est revue d'un bloc.

ALTER TABLE public.pro_profiles ADD COLUMN pending_professions text[] NOT NULL DEFAULT '{}'::text[];
ALTER TABLE public.pro_profiles ADD CONSTRAINT pro_profiles_pending_professions_check CHECK (
  pending_professions <@ ARRAY[
    'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
    'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
    'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other'
  ]::text[]
  AND cardinality(pending_professions) <= 13
);
-- Pas de GRANT SELECT : le pro lit ses demandes via get_my_pending_professions,
-- l'admin via admin_get_pro_profession_requests. Personne d'autre.

-- Garde-fou : aucun chemin (update_pro_profile.p_profession, futur code) ne
-- peut ajouter un métier à un pro validé, sauf admin_decide_pro_profession
-- (junto.profession_grant). Nommé pour passer APRÈS
-- pro_profiles_sync_professions_trg (ordre alphabétique des triggers).
CREATE FUNCTION private.pro_profiles_profession_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF OLD.status = 'approved' AND NEW.status = 'approved'
     AND NOT (NEW.professions <@ OLD.professions)
     AND current_setting('junto.profession_grant', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Un métier acquis n'est jamais aussi « en attente ».
  IF NEW.pending_professions && NEW.professions THEN
    NEW.pending_professions := ARRAY(SELECT x FROM unnest(NEW.pending_professions) x
                                     WHERE x <> ALL (NEW.professions));
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.pro_profiles_profession_guard() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pro_profiles_zz_profession_guard BEFORE UPDATE ON public.pro_profiles
  FOR EACH ROW EXECUTE FUNCTION private.pro_profiles_profession_guard();

-- set_pro_professions : renvoie désormais la liste en attente (void → text[]).
DROP FUNCTION public.set_pro_professions(text[]);

CREATE FUNCTION public.set_pro_professions(p_professions text[])
RETURNS text[]
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_list text[];
  v_status TEXT;
  v_current text[];
  v_pending_old text[];
  v_kept text[];
  v_new text[];
  v_secret TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  SELECT status, professions, pending_professions INTO v_status, v_current, v_pending_old
  FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Dédoublonné en gardant l'ordre (le premier = mis en avant).
  SELECT coalesce(array_agg(x ORDER BY first_pos), '{}'::text[]) INTO v_list
  FROM (SELECT x, min(ord) AS first_pos
        FROM unnest(coalesce(p_professions, '{}'::text[])) WITH ORDINALITY AS t(x, ord)
        GROUP BY x) d;

  IF NOT (v_list <@ ARRAY[
    'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
    'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
    'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other'
  ]::text[]) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Demande pas encore validée : revue d'un bloc, liste libre.
  IF v_status <> 'approved' THEN
    UPDATE pro_profiles SET professions = v_list, pending_professions = '{}'::text[] WHERE user_id = v_user_id;
    RETURN '{}'::text[];
  END IF;

  -- Pro validé : acquis (ordre choisi) / nouveaux (en attente).
  v_kept := ARRAY(SELECT x FROM unnest(v_list) WITH ORDINALITY AS t(x, o) WHERE x = ANY (v_current) ORDER BY o);
  v_new := ARRAY(SELECT x FROM unnest(v_list) WITH ORDINALITY AS t(x, o) WHERE x <> ALL (v_current) ORDER BY o);
  IF cardinality(v_kept) = 0 THEN RAISE EXCEPTION 'junto.profession_keep_one'; END IF;

  UPDATE pro_profiles SET professions = v_kept, pending_professions = v_new WHERE user_id = v_user_id;

  -- E-mail à askandgo pour une demande nouvelle (pas pour un retrait),
  -- 3 par pro et par 24 h. Ne bloque jamais l'enregistrement.
  IF EXISTS (SELECT 1 FROM unnest(v_new) x WHERE x <> ALL (v_pending_old)) THEN
    BEGIN
      IF (SELECT count(*) FROM rate_events
          WHERE user_id = v_user_id AND kind = 'pro_profession_mail'
            AND at > now() - interval '24 hours') < 3 THEN
        SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
        IF v_secret IS NOT NULL AND private.project_url() IS NOT NULL THEN
          INSERT INTO rate_events (user_id, kind) VALUES (v_user_id, 'pro_profession_mail');
          PERFORM net.http_post(
            url := private.project_url() || '/functions/v1/notify-pro-application',
            headers := jsonb_build_object('Content-Type', 'application/json',
                                          'x-junto-push-secret', v_secret),
            body := jsonb_build_object('user_id', v_user_id, 'kind', 'professions')
          );
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'set_pro_professions mail: %', SQLERRM;
    END;
  END IF;

  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION public.set_pro_professions(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pro_professions(text[]) TO authenticated;

CREATE FUNCTION public.get_my_pending_professions()
RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_list text[];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN '{}'::text[]; END IF;
  IF private.user_is_suspended(v_user_id) THEN RETURN '{}'::text[]; END IF;
  SELECT pending_professions INTO v_list FROM pro_profiles WHERE user_id = v_user_id;
  RETURN coalesce(v_list, '{}'::text[]);
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_pending_professions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_pending_professions() TO authenticated;

CREATE FUNCTION public.admin_get_pro_profession_requests()
RETURNS TABLE(user_id uuid, display_name text, company_name text, real_name text,
              professions text[], pending_professions text[], updated_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.professions, pp.pending_professions, pp.updated_at
  FROM pro_profiles pp
  WHERE pp.status = 'approved' AND cardinality(pp.pending_professions) > 0
  ORDER BY pp.updated_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_get_pro_profession_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_pro_profession_requests() TO authenticated;

CREATE FUNCTION public.admin_decide_pro_profession(p_pro uuid, p_profession text, p_approve boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_approve IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM 1 FROM pro_profiles
  WHERE user_id = p_pro AND status = 'approved' AND p_profession = ANY (pending_professions)
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_approve THEN
    PERFORM set_config('junto.profession_grant', 'true', true);
    UPDATE pro_profiles
    SET professions = professions || p_profession,
        pending_professions = array_remove(pending_professions, p_profession)
    WHERE user_id = p_pro;
    PERFORM set_config('junto.profession_grant', 'false', true);
  ELSE
    UPDATE pro_profiles SET pending_professions = array_remove(pending_professions, p_profession)
    WHERE user_id = p_pro;
  END IF;

  PERFORM create_notification(
    p_pro,
    CASE WHEN p_approve THEN 'pro_profession_approved' ELSE 'pro_profession_rejected' END,
    CASE WHEN p_approve THEN 'Nouveau métier validé' ELSE 'Nouveau métier refusé' END,
    CASE WHEN p_approve THEN 'Il apparaît maintenant sur ta page pro.'
         ELSE 'Le métier demandé n’a pas été validé. Écris-nous à contact@askandgo.io pour en savoir plus.' END,
    jsonb_build_object('pro_id', p_pro, 'params', jsonb_build_object('profession', p_profession))
  );

  PERFORM log_admin_action(v_admin,
    CASE WHEN p_approve THEN 'approve_pro_profession' ELSE 'reject_pro_profession' END,
    'pro_profile', p_pro, p_profession, NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_decide_pro_profession(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_decide_pro_profession(uuid, text, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Couple bloqué : pas de nom du pro

CREATE OR REPLACE FUNCTION private.mark_outing_confirmed(p_pro uuid, p_offering uuid, p_day date, p_period text, p_session uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_min INTEGER;
  v_n INTEGER;
  v_title TEXT;
  v_pro_name TEXT;
  v_bk RECORD;
BEGIN
  v_min := private.outing_min(p_offering, p_session);
  IF v_min IS NULL THEN RETURN false; END IF;
  IF p_reason = 'minimum' AND private.outing_total(p_offering, p_day, p_period, p_session) < v_min THEN
    RETURN false;
  END IF;

  -- 00580 (SESSIONS-A): « Maintenir » wins over « minimum reached » — an
  -- existing minimum confirmation becomes the pro's (clients were already told).
  IF p_reason = 'pro' THEN
    UPDATE private.outing_confirmations c SET reason = 'pro'
    WHERE c.reason <> 'pro'
      AND ((p_session IS NOT NULL AND c.session_id = p_session)
        OR (p_session IS NULL AND c.session_id IS NULL AND c.offering_id = p_offering
            AND c.day = p_day AND c.period = p_period));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN RETURN true; END IF;
  END IF;

  INSERT INTO private.outing_confirmations (pro_id, offering_id, day, period, session_id, reason)
  VALUES (p_pro, p_offering, p_day, p_period, p_session, p_reason)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN false; END IF;

  SELECT title INTO v_title FROM pro_offerings WHERE id = p_offering;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = p_pro;
  FOR v_bk IN
    SELECT b.id, b.client_id FROM bookings b
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND ((p_session IS NOT NULL AND b.session_id = p_session)
        OR (p_session IS NULL AND b.session_id IS NULL
            AND b.offering_id = p_offering AND b.day = p_day AND b.period = p_period))
  LOOP
    PERFORM create_notification(
      v_bk.client_id,
      'booking_confirmed',
      'Départ confirmé',
      'Le départ de « ' || coalesce(v_title, 'ta sortie') || ' » du ' || to_char(p_day, 'DD/MM') || ' est confirmé.',
      jsonb_build_object('booking_id', v_bk.id,
        -- 00581: no pro name between a blocked pair (the template has none).
        'params', jsonb_build_object('name', CASE WHEN private.blocked_either_way(p_pro, v_bk.client_id)
                                                  THEN NULL ELSE coalesce(v_pro_name, 'Le professionnel') END,
                                     'title', coalesce(v_title, 'ta sortie'),
                                     'date', to_char(p_day, 'YYYY-MM-DD'), 'period', p_period))
    );
  END LOOP;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION private.auto_cancel_outing_bookings(p_pro uuid, p_offering uuid, p_day date, p_period text, p_session uuid, p_title text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_bk RECORD;
  v_pro_name TEXT;
  v_n INTEGER := 0;
  v_blocked BOOLEAN;
BEGIN
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = p_pro;
  FOR v_bk IN
    SELECT b.id, b.client_id, b.status FROM bookings b
    WHERE b.status IN ('pending', 'accepted')
      AND ((p_session IS NOT NULL AND b.session_id = p_session)
        OR (p_session IS NULL AND b.session_id IS NULL AND b.pro_id = p_pro
            AND b.offering_id = p_offering AND b.day = p_day AND b.period = p_period))
    FOR UPDATE
  LOOP
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = CASE WHEN v_bk.status = 'accepted' THEN 'cancelled_pro' ELSE 'declined' END
    WHERE id = v_bk.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_n := v_n + 1;
    CONTINUE WHEN v_bk.client_id IS NULL;

    -- 00581: blocked either way → no pro name (as cancel_booking_pro, 00580).
    v_blocked := private.blocked_either_way(p_pro, v_bk.client_id);
    IF v_bk.status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        '« ' || coalesce(p_title, 'Ta sortie') || ' » du ' || to_char(p_day, 'DD/MM')
          || ' est annulée : pas assez de participants.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'auto', 'variant', 'auto_minimum',
          'params', jsonb_build_object('name', CASE WHEN v_blocked THEN NULL ELSE coalesce(v_pro_name, 'Le professionnel') END,
                                       'title', coalesce(p_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    ELSIF v_blocked THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_declined',
        'Créneau indisponible',
        'Le créneau demandé pour « ' || coalesce(p_title, 'ta sortie') || ' » le '
          || to_char(p_day, 'DD/MM') || ' n’est pas disponible.',
        jsonb_build_object('booking_id', v_bk.id, 'offering_id', p_offering, 'variant', 'neutral',
          'params', jsonb_build_object('title', coalesce(p_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    ELSE
      PERFORM create_notification(
        v_bk.client_id,
        'booking_declined',
        'Créneau indisponible',
        coalesce(v_pro_name, 'Le professionnel') || ' n’est pas disponible pour « '
          || coalesce(p_title, 'ta sortie') || ' » le ' || to_char(p_day, 'DD/MM') || '.',
        jsonb_build_object('booking_id', v_bk.id, 'offering_id', p_offering,
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(p_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Traces : étapes

CREATE OR REPLACE FUNCTION public.trace_geojson_ok(p_geojson jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  w jsonb;
BEGIN
  -- 00484: never NULL — callers write `IF NOT trace_geojson_ok(x)`.
  IF p_geojson IS NULL OR jsonb_typeof(p_geojson) <> 'object' THEN RETURN false; END IF;
  IF pg_column_size(p_geojson) > 1000000 THEN RETURN false; END IF;
  IF NOT (p_geojson ? 'type' AND p_geojson ? 'coordinates') THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_geojson) k WHERE k NOT IN ('type', 'coordinates', 'waypoints')) THEN
    RETURN false;
  END IF;
  IF p_geojson->>'type' IS DISTINCT FROM 'LineString'
     OR jsonb_typeof(p_geojson->'coordinates') <> 'array'
     OR jsonb_array_length(p_geojson->'coordinates') NOT BETWEEN 2 AND 10000 THEN
    RETURN false;
  END IF;
  -- Same per-point rules as before (00470), evaluated in C by jsonpath.
  IF jsonb_path_exists(p_geojson, 'strict $.coordinates[*] ? (
         @.type() != "array"
      || @.size() < 2 || @.size() > 4
      || @[0].type() != "number" || @[1].type() != "number"
      || @[0] < -180 || @[0] > 180 || @[1] < -90 || @[1] > 90
      || (@.size() >= 3 && @[2].type() != "number" && @[2].type() != "null")
      || (@.size() >= 3 && @[2].type() == "number" && (@[2] < -100000 || @[2] > 100000))
      || (@.size() == 4 && @[3].type() != "number" && @[3].type() != "null")
      || (@.size() == 4 && @[3].type() == "number" && (@[3] < -1e13 || @[3] > 1e13))
      || (@[0] != 0 && @[0] > -1e-300 && @[0] < 1e-300)
      || (@[1] != 0 && @[1] > -1e-300 && @[1] < 1e-300)
      || (@.size() >= 3 && @[2].type() == "number" && @[2] != 0 && @[2] > -1e-300 && @[2] < 1e-300)
      || (@.size() == 4 && @[3].type() == "number" && @[3] != 0 && @[3] > -1e-300 && @[3] < 1e-300)
    )', '{}', true) THEN
    RETURN false;
  END IF;

  IF p_geojson ? 'waypoints' THEN
    IF jsonb_typeof(p_geojson->'waypoints') <> 'array' OR jsonb_array_length(p_geojson->'waypoints') > 30 THEN
      RETURN false;
    END IF;
    FOR w IN SELECT value FROM jsonb_array_elements(p_geojson->'waypoints') LOOP
      IF jsonb_typeof(w) <> 'object' THEN RETURN false; END IF;
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(w) k WHERE k NOT IN ('lng', 'lat', 'kind', 'name')) THEN
        RETURN false;
      END IF;
      IF jsonb_typeof(w->'lng') IS DISTINCT FROM 'number' OR jsonb_typeof(w->'lat') IS DISTINCT FROM 'number' THEN
        RETURN false;
      END IF;
      -- 00581: compared as JSON numbers, never cast — 1e400 used to raise
      -- « out of range » instead of returning false (and skip the callers'
      -- rate counters). Same subnormal guard as the coordinates.
      IF jsonb_path_exists(w, 'strict $ ? (
             @.lng < -180 || @.lng > 180 || @.lat < -90 || @.lat > 90
          || (@.lng != 0 && @.lng > -1e-300 && @.lng < 1e-300)
          || (@.lat != 0 && @.lat > -1e-300 && @.lat < 1e-300)
        )', '{}', true) THEN
        RETURN false;
      END IF;
      IF w->>'kind' IS NULL OR w->>'kind' NOT IN
         ('refuge', 'camp', 'water', 'viewpoint', 'food', 'parking', 'summit', 'danger', 'other') THEN
        RETURN false;
      END IF;
      IF w ? 'name' AND (
           jsonb_typeof(w->'name') <> 'string'
           OR char_length(w->>'name') NOT BETWEEN 1 AND 60
           OR w->>'name' ~ '[<>[:cntrl:]]'
           -- 00581: invisible / direction characters (the 00532 class).
           OR w->>'name' ~ '[\u00AD\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]') THEN
        RETURN false;
      END IF;
    END LOOP;
  END IF;
  RETURN true;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Index anti-doublon des rappels de présence (+ presence_end_reminder)

DROP INDEX public.idx_notif_presence_dedup;
CREATE UNIQUE INDEX idx_notif_presence_dedup ON public.notifications USING btree (user_id, type, ((data ->> 'activity_id'::text)))
  WHERE (type = ANY (ARRAY['presence_pre_warning'::text, 'presence_pre_warning_10min'::text, 'presence_validate_warning'::text,
                           'presence_validate_overdue'::text, 'presence_validate_final'::text, 'qr_create_reminder'::text,
                           'peer_review_closing'::text, 'rate_participants'::text, 'presence_end_reminder'::text]));

-- ---------------------------------------------------------------------------
-- 6. Rappels quotidiens : chaque envoi isolé

CREATE OR REPLACE FUNCTION private.notify_booking_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_bk RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 18 THEN RETURN; END IF;

  FOR v_bk IN
    -- 00580 (BOOKINGS-R4): no pro name between a blocked pair.
    SELECT b.id, b.client_id, b.day, b.period, po.title,
           CASE WHEN private.blocked_either_way(b.pro_id, b.client_id) THEN NULL ELSE pp.display_name END AS pro_name,
           (coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
            + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
            AND private.filled_count(b.participant_info) < b.party_size) AS forms_missing
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    LEFT JOIN public_profiles pp ON pp.id = b.pro_id
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND b.day = private.today_paris() + 1
  LOOP
    -- 00581: one failing row never cancels the others' reminders.
    BEGIN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_reminder',
        'C’est demain',
        '« ' || coalesce(v_bk.title, 'Ta sortie') || ' » demain, '
          || CASE v_bk.period WHEN 'am' THEN 'matin' ELSE 'après-midi' END
          || CASE WHEN v_bk.forms_missing THEN ' · pense à remplir tes fiches participants.' ELSE '.' END,
        jsonb_build_object('booking_id', v_bk.id,
          'variant', CASE WHEN v_bk.forms_missing THEN 'forms' WHEN v_bk.pro_name IS NULL THEN 'plain' ELSE NULL END,
          'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                       'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notify_booking_reminders %: %', v_bk.id, SQLERRM;
    END;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_booking_forms_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_bk RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 18 THEN RETURN; END IF;

  FOR v_bk IN
    -- 00580 (BOOKINGS-R4): no pro name between a blocked pair.
    SELECT b.id, b.client_id, b.day, b.period, po.title,
           CASE WHEN private.blocked_either_way(b.pro_id, b.client_id) THEN NULL ELSE pp.display_name END AS pro_name
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    LEFT JOIN public_profiles pp ON pp.id = b.pro_id
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND b.day = private.today_paris() + 3
      AND coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
          + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
      AND private.filled_count(b.participant_info) < b.party_size
  LOOP
    -- 00581: one failing row never cancels the others' reminders.
    BEGIN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_forms_reminder',
        'Fiche du groupe à compléter',
        CASE WHEN v_bk.pro_name IS NULL THEN 'Remplis les infos de ton groupe pour « '
             ELSE v_bk.pro_name || ' attend les infos de ton groupe pour « ' END
          || coalesce(v_bk.title, 'ta sortie') || ' » (' || to_char(v_bk.day, 'DD/MM') || ').',
        jsonb_build_object('booking_id', v_bk.id,
          'variant', CASE WHEN v_bk.pro_name IS NULL THEN 'plain' ELSE NULL END,
          'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                       'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notify_booking_forms_reminders %: %', v_bk.id, SQLERRM;
    END;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_booking_forms_missing()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_row RECORD;
  v_min_low BOOLEAN;
  v_body TEXT;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN; END IF;

  FOR v_row IN
    WITH outings AS (
      SELECT b.pro_id, b.offering_id, b.day, b.period, b.session_id,
             sum(CASE WHEN coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
                         + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
                      THEN greatest(b.party_size - private.filled_count(b.participant_info), 0)
                      ELSE 0 END)::INTEGER AS missing,
             sum(b.party_size)::INTEGER AS total
      FROM bookings b
      JOIN pro_offerings po ON po.id = b.offering_id
      WHERE b.status = 'accepted' AND b.day = private.today_paris() + 2
      GROUP BY b.pro_id, b.offering_id, b.day, b.period, b.session_id
    ), sess AS (
      SELECT s.id, s.pro_id, s.offering_id, s.start_day AS day, s.start_period AS period, s.min_participants
      FROM pro_sessions s
      WHERE s.status = 'scheduled' AND s.start_day = private.today_paris() + 2
        AND s.min_participants IS NOT NULL
    ), joined AS (
      SELECT coalesce(o.pro_id, s.pro_id) AS pro_id, coalesce(o.offering_id, s.offering_id) AS offering_id,
             coalesce(o.day, s.day) AS day, coalesce(o.period, s.period) AS period,
             coalesce(s.id, o.session_id) AS session_id,
             coalesce(o.missing, 0) AS missing, coalesce(o.total, 0) AS total,
             coalesce(s.min_participants, CASE WHEN o.session_id IS NULL THEN po.min_participants END) AS min,
             po.title, po.auto_cancel
      FROM outings o
      FULL JOIN sess s ON s.id = o.session_id
      JOIN pro_offerings po ON po.id = coalesce(o.offering_id, s.offering_id)
    )
    SELECT j.*,
           (j.min IS NOT NULL AND j.total < j.min
            AND NOT private.outing_confirmed(j.offering_id, j.day, j.period, j.session_id)) AS is_short
    FROM joined j
  LOOP
    -- 00581: one failing row never cancels the others' reminders.
    BEGIN
      v_min_low := v_row.is_short;
      CONTINUE WHEN v_row.missing = 0 AND NOT v_min_low;
      v_body := '« ' || coalesce(v_row.title, 'Ta sortie') || ' » (' || to_char(v_row.day, 'DD/MM') || ') : ';
      IF v_row.missing > 0 THEN
        v_body := v_body || v_row.missing || ' fiche' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
          || ' participant' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
          || ' manquante' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END;
        IF v_min_low THEN v_body := v_body || ', et ';
        ELSE v_body := v_body || ' sur ' || v_row.total; END IF;
      END IF;
      IF v_min_low THEN
        -- 00578 (SESSIONS-2): « annulée demain » only when the pro chose it.
        v_body := v_body || v_row.total || '/' || v_row.min || ' inscrits'
          || CASE WHEN v_row.auto_cancel THEN '. Maintiens-la, sinon elle sera annulée demain à 9 h'
                  ELSE ', minimum ' || v_row.min || ' pour partir' END;
      END IF;
      PERFORM create_notification(
        v_row.pro_id,
        'booking_forms_missing',
        CASE WHEN v_row.missing > 0 THEN 'Il manque des infos' ELSE 'Minimum pas atteint' END,
        v_body || '.',
        jsonb_build_object('offering_id', v_row.offering_id,
          'variant', CASE WHEN v_min_low AND v_row.missing > 0 THEN CASE WHEN v_row.auto_cancel THEN 'both_auto' ELSE 'both' END
                          WHEN v_min_low THEN CASE WHEN v_row.auto_cancel THEN 'minimum_auto' ELSE 'minimum' END
                          ELSE NULL END,
          'params', jsonb_build_object('title', coalesce(v_row.title, ''), 'date', to_char(v_row.day, 'YYYY-MM-DD'),
                                       'period', v_row.period, 'count', v_row.missing, 'total', v_row.total,
                                       'min', v_row.min))
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notify_booking_forms_missing %: %', v_row.offering_id, SQLERRM;
    END;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_pending_booking_requests()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_row RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN; END IF;

  FOR v_row IN
    SELECT b.pro_id, count(*)::INTEGER AS n
    FROM bookings b
    WHERE b.status = 'pending'
      AND b.created_at < now() - INTERVAL '24 hours'
      AND b.day >= private.today_paris()
    GROUP BY b.pro_id
  LOOP
    -- 00581: one failing row never cancels the others' reminders.
    BEGIN
      PERFORM create_notification(
        v_row.pro_id,
        'booking_requests_waiting',
        'Demandes en attente',
        v_row.n || CASE WHEN v_row.n > 1 THEN ' demandes attendent' ELSE ' demande attend' END || ' ta réponse.',
        jsonb_build_object('params', jsonb_build_object('count', v_row.n))
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notify_pending_booking_requests %: %', v_row.pro_id, SQLERRM;
    END;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Agenda externe : noms masqués par défaut pour les nouveaux liens

ALTER TABLE private.pro_calendar_links ALTER COLUMN hide_names SET DEFAULT true;
