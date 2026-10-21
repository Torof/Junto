-- ============================================================================
-- 00522 — Contre-vérification de 00520-00521.
-- F1  Le message « une personne que tu as bloquée » seulement à la personne
--     qui rejoint ; un organisateur qui accepte reçoit le refus générique.
-- F2  Un blocage retire les demandes en attente qui ne pourraient plus être
--     acceptées (bloqueur et bloqué dans la même sortie).
-- F3  Plafond global des tracés : vraiment compté sur la journée.
-- F4  Plafond de stockage : par jour d'envoi (les photos remplacées restent
--     en stockage ; un compte actif n'est plus bloqué à vie).
-- F6  Une notification de renommage par pro et par jour.
-- F7  Deux « peu importe » : 50 km, pas tout le pays.
-- F8  Badge « organisateur » : présence validée, comme les trophées.
-- F10 Pas d'interblocage entre deux acceptations simultanées.
-- F11 Quitter une sortie / monter chez un conducteur efface tout le point de départ.
-- F14 Pas d'invitation impossible à accepter (blocage avec un membre).
-- F15 Un membre banni d'une discussion n'y publie jamais.
-- ============================================================================

CREATE INDEX IF NOT EXISTS snap_trail_calls_called_at_idx ON snap_trail_calls (called_at);

CREATE OR REPLACE FUNCTION private.check_shared_outing_block()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status NOT IN ('accepted', 'pending') THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;  -- system writes (demo seeding)
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = NEW.activity_id AND a.is_demo) THEN RETURN NEW; END IF;
  -- Someone already in the outing (organiser included) who BLOCKED the newcomer:
  -- generic refusal (never tell who blocks whom).
  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE b.blocked_id = NEW.user_id
      AND (b.blocker_id IN (SELECT p.user_id FROM participations p
                            WHERE p.activity_id = NEW.activity_id AND p.status = 'accepted' AND p.user_id <> NEW.user_id)
           OR b.blocker_id = (SELECT a.creator_id FROM activities a WHERE a.id = NEW.activity_id))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- The newcomer blocked someone already in it: they know it, say it.
  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE b.blocker_id = NEW.user_id
      AND b.blocked_id IN (SELECT p.user_id FROM participations p
                           WHERE p.activity_id = NEW.activity_id AND p.status = 'accepted' AND p.user_id <> NEW.user_id)
  ) THEN
    -- 00522 (F1): the coded message only to the person joining (it is about
    -- their own block) — an organiser accepting them gets the generic one.
    IF auth.uid() = NEW.user_id THEN RAISE EXCEPTION 'junto.blocked_member_present'; END IF;
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cascade_block_cleanup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 00522 (F2): a pending request of someone who is now in a block relation
  -- with an accepted member of that outing is withdrawn (it could never be
  -- accepted any more — the shared-outing rule would refuse it).
  UPDATE participations p
  SET status = 'withdrawn'
  WHERE p.status = 'pending'
    AND ((p.user_id = NEW.blocked_id AND EXISTS (SELECT 1 FROM participations q
            WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocker_id AND q.status = 'accepted'))
      OR (p.user_id = NEW.blocker_id AND EXISTS (SELECT 1 FROM participations q
            WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocked_id AND q.status = 'accepted')));

  -- Refuse pending join requests where blocker is creator and blocked is requester (or vice-versa)
  UPDATE participations p
  SET status = 'refused', refused_at = now()
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND ((a.creator_id = NEW.blocker_id AND p.user_id = NEW.blocked_id)
      OR (a.creator_id = NEW.blocked_id AND p.user_id = NEW.blocker_id));

  -- Cancel pending/accepted seat requests in both directions
  UPDATE seat_requests
  SET status = 'cancelled'
  WHERE status IN ('pending', 'accepted')
    AND ((requester_id = NEW.blocker_id AND driver_id = NEW.blocked_id)
      OR (requester_id = NEW.blocked_id AND driver_id = NEW.blocker_id));

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
  -- 00522 (F3): rows are kept a day (purged by the daily job) so the global
  -- daily ceiling really counts the day; the per-user limit counts the hour.
  SELECT count(*) INTO v_count FROM snap_trail_calls WHERE user_id = v_user AND called_at > now() - INTERVAL '1 hour';
  IF v_count >= 200 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  -- 00520 (AB-7): a global daily ceiling protects the shared routing quota.
  IF (SELECT count(*) FROM snap_trail_calls WHERE called_at > now() - INTERVAL '1 day') >= 1500 THEN
    RAISE EXCEPTION 'junto.rate_limited';
  END IF;
  INSERT INTO snap_trail_calls (user_id) VALUES (v_user);
END;
$function$;

CREATE OR REPLACE FUNCTION public.purge_throttle_tables()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  DELETE FROM map_broadcasts WHERE at < now() - INTERVAL '1 day';
  DELETE FROM rate_events WHERE at < now() - INTERVAL '2 days';
  DELETE FROM snap_trail_calls WHERE called_at < now() - INTERVAL '1 day';  -- 00522
$function$;

CREATE OR REPLACE FUNCTION private.storage_object_quota()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_folder TEXT := (storage.foldername(NEW.name))[1];
  -- 00522 (F4): uploads per DAY, not files kept — replaced photos stay as
  -- orphans in storage, so a lifetime count would lock active pros out.
  v_cap INTEGER := CASE NEW.bucket_id WHEN 'avatars' THEN 20 WHEN 'pro-photos' THEN 100 WHEN 'channel-photos' THEN 30 ELSE NULL END;
BEGIN
  IF v_cap IS NULL OR auth.uid() IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('storage:' || NEW.bucket_id || ':' || coalesce(v_folder, '')));
  IF (SELECT count(*) FROM storage.objects o
      WHERE o.bucket_id = NEW.bucket_id AND (storage.foldername(o.name))[1] = v_folder
        AND o.created_at > now() - INTERVAL '1 day') >= v_cap THEN
    RAISE EXCEPTION 'junto.storage_quota';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_pro_renamed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID;
BEGIN
  IF NEW.status <> 'approved' OR NEW.display_name IS NOT DISTINCT FROM OLD.display_name THEN RETURN NULL; END IF;
  FOR v_admin IN SELECT id FROM users WHERE is_admin AND suspended_at IS NULL LOOP
    -- 00522 (F6): one notice per pro and admin a day (rename loops).
    CONTINUE WHEN EXISTS (SELECT 1 FROM notifications n WHERE n.user_id = v_admin AND n.type = 'pro_renamed'
                          AND n.data->>'pro_id' = NEW.user_id::text AND n.created_at > now() - INTERVAL '1 day');
    PERFORM create_notification(v_admin, 'pro_renamed', 'Vitrine pro renommée',
      sanitize_notif_text(coalesce(OLD.display_name, '?')) || ' → ' || sanitize_notif_text(coalesce(NEW.display_name, '?')),
      jsonb_build_object('pro_id', NEW.user_id,
        'params', jsonb_build_object('old', sanitize_notif_text(coalesce(OLD.display_name, '?')), 'new', sanitize_notif_text(coalesce(NEW.display_name, '?')))));
  END LOOP;
  RETURN NULL;
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
            AND p.confirmed_present = true /* 00521: validated presence only */
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
         ST_DWithin(d.base, v_base, (CASE WHEN v_radius IS NULL AND d.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(v_radius, 0) + coalesce(d.radius_km, 0) END) * 1000.0))
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
         ST_DWithin(d.base, v_base, (CASE WHEN p_radius_km IS NULL AND d.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(p_radius_km, 0) + coalesce(d.radius_km, 0) END) * 1000.0))
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
         ST_DWithin(t.base, v_base, (CASE WHEN v_radius IS NULL AND t.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(v_radius, 0) + coalesce(t.radius_km, 0) END) * 1000.0));
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
         ST_DWithin(me.base, tgt.base, (CASE WHEN me.radius_km IS NULL AND tgt.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(me.radius_km, 0) + coalesce(tgt.radius_km, 0) END) * 1000.0))
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
         ST_DWithin(me.base, tgt.base, (CASE WHEN me.radius_km IS NULL AND tgt.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(me.radius_km, 0) + coalesce(tgt.radius_km, 0) END) * 1000.0))
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

CREATE OR REPLACE FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER;
  v_tier TEXT;
  v_inserted UUID;
  v_label TEXT;
BEGIN
  -- Joined activities (where the user wasn't the creator)
  SELECT count(*) INTO v_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present = true /* 00521: validated presence only */  -- 00495 (PR-7)
    AND a.status = 'completed'
    AND a.creator_id != p_user_id
    AND a.deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'joined', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('joined', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'joined', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Created activities
  SELECT count(*) INTO v_count
  FROM activities
  WHERE creator_id = p_user_id
    AND status = 'completed'
    AND deleted_at IS NULL
    -- 00522 (F8): same rule as the trophies — the organiser's presence validated.
    AND EXISTS (SELECT 1 FROM participations cp WHERE cp.activity_id = activities.id
                AND cp.user_id = p_user_id AND cp.confirmed_present = true);
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'created', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('created', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'created', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
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

  -- 00522 (F10): take the person's schedule lock BEFORE the row lock — the
  -- schedule trigger takes it too, and withdraws overlapping rows: same order
  -- everywhere, no deadlock between two organisers accepting at once.
  PERFORM pg_advisory_xact_lock(hashtext('schedule:' || coalesce((SELECT user_id::text FROM participations WHERE id = p_participation_id), '')));

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

CREATE OR REPLACE FUNCTION public.leave_activity(p_activity_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
  v_reason TEXT;
  v_was_driver BOOLEAN;
  v_passenger RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

  SELECT p.id, p.status, p.transport_type, p.transport_seats, p.accepted_at, p.accepted_via
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  -- Block creator from leaving their own activity (would orphan the activity)
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00477 (PR-5): only leaving an ACCEPTED place late is a late cancel;
  -- withdrawing a request nobody answered is not.
  v_is_late := v_participation.status = 'accepted'
               AND v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now())
               -- 00517: a REQUEST the organiser accepted inside the 12-hour line
               -- is not a late cancel when left (the trap) — a place one took
               -- oneself, at any time, still is.
               AND NOT (v_participation.accepted_via = 'organiser'
                        AND v_participation.accepted_at >= v_activity.starts_at - INTERVAL '12 hours')
               -- 00516: nobody is penalised for leaving a suspended organiser's outing.
               AND NOT private.user_is_suspended(v_activity.creator_id);

  v_was_driver := v_participation.transport_type IN ('car', 'carpool');

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL,
      transport_from_lat = NULL, transport_from_lng = NULL, transport_from_locality = NULL  -- 00522 (F11)
  WHERE id = v_participation.id;

  -- 00478 (PR-4): the late cancel goes to its own ledger, which no rejoin,
  -- re-invitation, declined invitation or block cascade can erase. A new late
  -- cancel on the same outing re-arms a previous waiver.
  IF v_is_late THEN
    INSERT INTO late_cancels (user_id, activity_id, at, waived)
    VALUES (v_user_id, p_activity_id, now(), false)
    ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now(), waived = false;
  END IF;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  -- 00477/00478 (AB-1): at most one notification of EACH type per participant
  -- and outing per 24 h — an early leave never hides a later late one.
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END
      AND data->>'participation_id' = v_participation.id::text
      AND created_at > now() - INTERVAL '24 hours'
  ) THEN
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté « ' || v_activity.title || ' »',
    CASE
      WHEN v_is_late THEN 'Départ tardif — pénalité de fiabilité appliquée, tu peux la lever depuis la sortie.'
      ELSE coalesce(v_reason, '')
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late,
      'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title, 'reason', coalesce(v_reason, '')))
  );
  END IF;

  -- If the leaver was offering rides, cancel their pending/accepted seat_requests
  -- and notify each affected requester so they can find another ride.
  IF v_was_driver THEN
    FOR v_passenger IN
      SELECT id, requester_id FROM seat_requests
      WHERE activity_id = p_activity_id AND driver_id = v_user_id
        AND status IN ('pending', 'accepted')
    LOOP
      UPDATE seat_requests SET status = 'cancelled' WHERE id = v_passenger.id;
      PERFORM create_notification(
        v_passenger.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_user_name, 'Le conducteur') || ' a quitté « ' || v_activity.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', p_activity_id, 'driver_id', v_user_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Le conducteur'), 'title', v_activity.title))
      );
    END LOOP;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_seat_request(p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_updated_count INTEGER;
  v_skip_seed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'junto.seats_exhausted';
  END IF;

  -- 00494 (BR-3): a passenger already seated with another driver of this
  -- outing does not take a second seat (two drivers accepting at once are
  -- serialised on the passenger).
  PERFORM pg_advisory_xact_lock(hashtext('seat_passenger:' || v_req.activity_id::text || ':' || v_req.requester_id::text));
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
               AND status = 'accepted' AND id <> p_request_id) THEN
    RAISE EXCEPTION 'junto.passenger_already_seated';
  END IF;
  -- 00496 (BR-3): a passenger who carries passengers does not ride elsewhere,
  -- and a driver who is seated in someone else's car takes nobody.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND driver_id = v_req.requester_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00496 (B-4): the passenger's other pending requests on this outing are
  -- withdrawn (other drivers no longer see a request they cannot accept).
  UPDATE seat_requests SET status = 'cancelled'
  WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
    AND status = 'pending' AND id <> p_request_id;

  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL,
      transport_from_lat = NULL, transport_from_lng = NULL, transport_from_locality = NULL, transport_departs_at = NULL  -- 00522 (F11)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_req.driver_id AND blocked_id = v_req.requester_id)
       OR (blocker_id = v_req.requester_id AND blocked_id = v_req.driver_id)
  ) OR EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_req.requester_id AND u.suspended_at IS NOT NULL
  ) INTO v_skip_seed;

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (retag 'transport' à la
  -- réactivation, purge des champs de requête). Plus d'unique_violation brute.
  SELECT id, status INTO v_conversation_id, v_conv_status
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF NOT v_skip_seed THEN
    IF v_conversation_id IS NULL THEN
      BEGIN
        INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
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

    v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
      || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
      || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

    -- 00508: unified store directly; this writer notifies on its own.
    PERFORM set_config('junto.skip_message_push', 'true', true);
    INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
    VALUES (
      v_conversation_id, v_req.driver_id, v_message,
      jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
      NOW()
    );

    UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  ELSIF v_conv_status IS DISTINCT FROM 'active' THEN
    -- Seed sauté (blocage/suspension) : ne pas pointer la notif vers un fil
    -- non actif.
    v_conversation_id := NULL;
  END IF;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );

  RETURN v_conversation_id;
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
    -- 00522 (F14): not someone in a block relation with an accepted member
    -- (the invitation could never be accepted).
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users b JOIN participations q ON q.activity_id = p_activity_id AND q.status = 'accepted'
      WHERE (b.blocker_id = q.user_id AND b.blocked_id = v_target) OR (b.blocker_id = v_target AND b.blocked_id = q.user_id));
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
    -- 00522 (F15): a banned member never posts (membership is removed on ban,
    -- this is the belt-and-braces check the edit / share paths already have).
    IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = v_conv.id AND user_id = v_user_id) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
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
