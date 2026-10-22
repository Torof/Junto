-- ============================================================================
-- 00426 — Audit adverse n°2 du flux Contacter / Inviter (Scott 2026-09-30,
-- « on répare tout »). Six volets, chaque base = version vivante vérifiée
-- (send_contact_request/invite_users_to_activity=00350, send_discovery_invite=
-- 00409, send_activity_invitations=00365, accept=00411, decline=00355,
-- expire=00142, get_conversation_state_with=00351, get_discovery_cards=00425 —
-- aucune surcharge : signatures inchangées partout).
--
-- (1) RIDEAU DÉMO CÔTÉ ÉCRITURE : un compte démo ne reçoit JAMAIS de vraie
--     demande/invitation (garde is_demo absolue, admin en mode démo compris —
--     même règle que join_activity). Trou trouvé indépendamment par deux
--     auditeurs : send_contact_request + les deux boucles d'invitation.
-- (2) PARITÉ DU CAP-10 (oracle) : pending et declined comptent désormais tous
--     deux sur la même fenêtre created_at+30j — la parité ne dépend plus du
--     sweeper lazy (un pending non balayé sortait du compte côté declined
--     seulement, sondable en REST à J+30).
-- (3) REFUS NON PERPÉTUEL (arbitrage délégué) : les demandes mortes (declined,
--     ou pending expirée) sont SUPPRIMÉES par le sweeper à created_at+30j —
--     même échéance que l'expiration d'une pending ignorée, donc le refus
--     silencieux reste indistinguable ; la paire redevient contactable ensuite.
--     Avant l'échéance, la partie qui N'A PAS envoyé (refuseur ou destinataire
--     d'une demande expirée) peut rouvrir la paire immédiatement avec sa propre
--     demande (elle connaît déjà son propre refus : zéro fuite ; l'expéditeur
--     d'origine, lui, reste verrouillé jusqu'au balayage).
-- (4) ÉTAT DIRECTIONNEL : le destinataire d'une demande en cours voit
--     'pending_received' (sa liste Demandes la lui montre déjà — zéro oracle) ;
--     l'expéditeur voit 'pending' pour pending ET declined, comme avant.
-- (5) RACES : accept/decline prennent la ligne FOR UPDATE (un refus ne peut
--     plus être ressuscité en actif par un accept concurrent, plus de double
--     message d'amorce) ; accept refuse une demande expirée ; les envois
--     passent en ON CONFLICT DO NOTHING (plus de 23505 brut sur envoi croisé) ;
--     p_source whitelisté ('profile'|'discovery' — les valeurs internes
--     'invite'/'request_reply'/'booking' ne sont plus maquillables).
-- (6) INVITATION MORTE : accepter une invitation dont la sortie a été annulée
--     notifie désormais l'accepteur (« Cette sortie n'est plus disponible »)
--     au lieu d'un silence total.
-- ============================================================================

-- ---------- 1. send_contact_request (base 00350) ----------
CREATE OR REPLACE FUNCTION send_contact_request(
  p_target_user_id UUID,
  p_message TEXT,
  p_source TEXT DEFAULT 'profile'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_clean_message TEXT;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Le client n'envoie que ces deux valeurs ; le reste de l'enum ('invite',
  -- 'request_reply', 'booking'…) est réservé aux écritures internes — un
  -- appelant ne doit pas pouvoir déguiser une demande profil en invitation.
  IF p_source IS NULL OR p_source NOT IN ('profile', 'discovery') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rideau démo côté écriture : garde ABSOLUE (admin en mode démo compris),
  -- comme join_activity — un compte démo ne reçoit jamais de vraie demande.
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

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  -- Lock AVANT l'examen de la paire : le reset (DELETE) et l'INSERT restent
  -- atomiques vis-à-vis d'un double-tap du même émetteur.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT * INTO v_conv FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;
  IF v_conv.id IS NOT NULL THEN
    IF v_conv.status = 'active' THEN RETURN v_conv.id; END IF;
    -- Demande morte (refusée, ou pending au-delà de ses 30 jours) : la partie
    -- qui NE l'a PAS envoyée peut rouvrir la paire avec sa propre demande.
    -- L'expéditeur d'origine reste verrouillé jusqu'au balayage à
    -- created_at+30j — même échéance qu'une pending ignorée, donc le refus
    -- silencieux reste inobservable de son côté.
    IF v_user_id IS DISTINCT FROM v_conv.request_sender_id
       AND (v_conv.status = 'declined'
            OR (v_conv.status = 'pending_request' AND v_conv.request_expires_at < NOW())) THEN
      DELETE FROM conversations WHERE id = v_conv.id;
    ELSE
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- Parité anti-oracle : les DEUX statuts comptent sur la même fenêtre de
  -- 30 jours (une pending non balayée ne sort plus du compte avant une
  -- declined) — le cap ne peut pas servir de sonde à refus.
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

  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_message := regexp_replace(trim(p_message), '<[^>]*>', '', 'g');

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'pending_request', p_source, v_user_id, v_clean_message, NOW() + INTERVAL '30 days', NOW(), NOW())
  ON CONFLICT (user_1, user_2) DO NOTHING
  RETURNING id INTO v_conversation_id;
  -- Course d'envoi croisé perdue (la paire a gagné une ligne entre l'examen et
  -- l'insert) : même générique que tout chemin « paire existante ».
  IF v_conversation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' souhaite te contacter',
    '',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION send_contact_request(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_contact_request(UUID, TEXT, TEXT) TO authenticated;

-- ---------- 2. send_discovery_invite (base 00409) ----------
CREATE OR REPLACE FUNCTION send_discovery_invite(
  p_target_user_id UUID,
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
      ON tgt.user_id = p_target_user_id AND tgt.is_active
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (me.radius_km IS NULL OR tgt.radius_km IS NULL
           OR ST_DWithin(me.base, tgt.base, (me.radius_km + tgt.radius_km) * 1000.0))
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

  SELECT s.key INTO v_sport_key FROM sports s WHERE s.id = v_activity.sport_id;

  -- Match the chosen activity against the target's ACTIVE dispo (sport + date).
  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active
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
    v_clean_title,
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'activity_id', p_activity_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION send_discovery_invite(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_discovery_invite(UUID, UUID) TO authenticated;

-- ---------- 3. invite_users_to_activity (base 00350) : garde is_demo dans la
-- boucle + parité du cap. Corps vivant repris à l'identique par ailleurs. ----------
CREATE OR REPLACE FUNCTION invite_users_to_activity(p_activity_id UUID, p_user_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_can_share BOOLEAN;
  v_recent INTEGER;   -- shared_activity messages in the last hour (60 cap)
  v_pending INTEGER;  -- caller's pending connection requests (10 cap)
  v_n INTEGER;
  v_target UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_conv RECORD;
  v_content TEXT;
  v_sender_name TEXT;
  v_secret TEXT;
  v_count INTEGER := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_n := array_length(p_user_ids, 1);
  IF p_user_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_n > 20 THEN RAISE EXCEPTION 'junto.invite_cap'; END IF;

  SELECT id, title, visibility, deleted_at, creator_id, status INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Share gate (mirror share_activity_message): public → anyone; private →
  -- creator only; approval → any accepted/pending participant.
  v_can_share := v_activity.visibility = 'public'
    OR v_activity.creator_id = v_user_id
    OR (
      v_activity.visibility = 'approval'
      AND EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = p_activity_id AND user_id = v_user_id
          AND status IN ('accepted', 'pending')
      )
    );
  IF NOT v_can_share THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_content := 'Je t''invite sur cette sortie 🙌' || E'\n« ' || v_activity.title || ' »';
  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  -- Serialize the caller so the two caps + inserts stay atomic. Same lock key as
  -- send_contact_request so the shared 10-pending cap can't be raced across the
  -- two functions.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT count(*) INTO v_recent FROM private_messages
    WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
      AND created_at > now() - INTERVAL '1 hour';
  -- Same decline-blind, sender-only predicate as send_contact_request (00350).
  SELECT count(*) INTO v_pending FROM conversations
    WHERE request_sender_id = v_user_id
      AND status IN ('pending_request', 'declined')
      AND created_at > now() - INTERVAL '30 days';

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL AND is_demo = false);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );

    IF v_user_id < v_target THEN v_u1 := v_user_id; v_u2 := v_target;
    ELSE v_u1 := v_target; v_u2 := v_user_id; END IF;
    SELECT id, status INTO v_conv FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2;

    IF v_conv.id IS NOT NULL AND v_conv.status = 'active' THEN
      -- Already connected → drop the tappable activity card (respect the 60/hr
      -- cap + 24h per-target dedup).
      CONTINUE WHEN v_recent >= 60;
      CONTINUE WHEN EXISTS (
        SELECT 1 FROM private_messages
        WHERE sender_id = v_user_id AND receiver_id = v_target
          AND metadata->>'type' = 'shared_activity'
          AND (metadata->>'activity_id')::uuid = p_activity_id
          AND created_at > now() - INTERVAL '24 hours'
      );
      INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
        VALUES (v_conv.id, v_user_id, v_target, v_content,
                jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id), now());
      UPDATE conversations SET last_message_at = now() WHERE id = v_conv.id;
      v_recent := v_recent + 1;
      IF v_secret IS NOT NULL THEN
        PERFORM net.http_post(
          url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
          body := jsonb_build_object(
            'user_id', v_target,
            'title', coalesce(v_sender_name, 'Junto'),
            'body', '📍 ' || v_activity.title,
            'data', jsonb_build_object('conversation_id', v_conv.id, 'activity_id', p_activity_id, 'type', 'shared_activity'),
            'collapseId', 'message-' || v_conv.id::text
          )
        );
      END IF;
      v_count := v_count + 1;

    ELSIF v_conv.id IS NULL THEN
      -- Not connected yet → send a gated connection request carrying the
      -- invitation (respect the 10-pending cap). The notifications INSERT is
      -- what fires the target's push (via the notifications→send-push trigger).
      CONTINUE WHEN v_pending >= 10;
      INSERT INTO conversations
        (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_user_id, 'pending_request', 'invite', v_user_id, v_content, now() + INTERVAL '30 days', now(), now())
        ON CONFLICT (user_1, user_2) DO NOTHING;
      IF FOUND THEN
        v_pending := v_pending + 1;
        INSERT INTO notifications (user_id, type, title, body, data, created_at)
          VALUES (
            v_target, 'contact_request',
            coalesce(v_sender_name, 'Quelqu''un') || ' t''invite sur une sortie', '',
            jsonb_build_object('type', 'contact_request', 'from_user_id', v_user_id),
            now()
          );
        v_count := v_count + 1;
      END IF;

    -- else: a pending_request / declined conversation exists → skip (00072).
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ---------- 4. send_activity_invitations (base 00365) : garde is_demo dans
-- la boucle (défense en profondeur — is_messaging_eligible gate déjà). ----------
CREATE OR REPLACE FUNCTION send_activity_invitations(
  p_activity_id UUID,
  p_user_ids UUID[],
  p_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à rejoindre',
      v_clean_title, jsonb_build_object('activity_id', p_activity_id, 'type', 'activity_invitation')
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION invite_users_to_activity(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION invite_users_to_activity(UUID, UUID[]) TO authenticated;

REVOKE ALL ON FUNCTION send_activity_invitations(UUID, UUID[], TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_activity_invitations(UUID, UUID[], TEXT) TO authenticated;

-- ---------- 5. accept_contact_request (base 00411) : FOR UPDATE + refus d'une
-- demande expirée + UPDATE conditionnel + notification « sortie morte ». ----------
CREATE OR REPLACE FUNCTION accept_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    coalesce(v_name, 'Quelqu''un') || ' a accepté ta demande',
    '',
    jsonb_build_object('conversation_id', p_conversation_id)
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
       AND v_act.status IN ('published', 'in_progress') THEN

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
          coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à rejoindre',
          regexp_replace(v_act.title, '<[^>]*>', '', 'g'),
          jsonb_build_object('activity_id', v_act.id, 'type', 'activity_invitation')
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
        coalesce(regexp_replace(v_act.title, '<[^>]*>', '', 'g'), ''),
        jsonb_build_object('conversation_id', p_conversation_id)
      );
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations SET pending_activity_id = NULL WHERE id = p_conversation_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION accept_contact_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION accept_contact_request(UUID) TO authenticated;

-- ---------- 6. decline_contact_request (base 00355) : FOR UPDATE. ----------
CREATE OR REPLACE FUNCTION decline_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id FOR UPDATE;
  IF v_conv.id IS NULL OR v_conv.type != 'dm' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_conv.status = 'pending_request' THEN
    UPDATE conversations SET status = 'declined' WHERE id = p_conversation_id;
  ELSIF v_conv.status = 'declined' THEN
    NULL; -- double-tap safe, indistinguishable
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION decline_contact_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION decline_contact_request(UUID) TO authenticated;

-- ---------- 7. expire_stale_contact_requests (base 00142) : les demandes
-- mortes sont SUPPRIMÉES à created_at+30j (avant : flip pending→declined et la
-- ligne restait à vie — verrou de paire perpétuel). Une pending ignorée et une
-- declined meurent à la MÊME échéance (request_expires_at = created+30j par
-- construction), donc rien n'est observable ; la paire redevient contactable.
-- Cascades propres : messages/membres en ON DELETE CASCADE, une DM non-active
-- n'a jamais de messages. ----------
CREATE OR REPLACE FUNCTION expire_stale_contact_requests()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM conversations
  WHERE type = 'dm'
    AND status IN ('pending_request', 'declined')
    AND created_at < NOW() - INTERVAL '30 days';
END;
$$;
REVOKE ALL ON FUNCTION expire_stale_contact_requests() FROM PUBLIC, anon, authenticated;

-- ---------- 8. get_conversation_state_with (base 00351) : état directionnel.
-- Expéditeur : 'pending' pour pending ET declined (anti-oracle inchangé).
-- Destinataire : 'pending_received' pour une demande VIVANTE uniquement (sa
-- liste Demandes la montre déjà — zéro information nouvelle) ; une declined ou
-- une pending expirée ne rend AUCUNE ligne côté destinataire (= none, cohérent
-- avec son droit de réouverture). ----------
CREATE OR REPLACE FUNCTION get_conversation_state_with(p_other_user_id UUID)
RETURNS TABLE (id UUID, state TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id,
         CASE
           WHEN c.status = 'active' THEN 'active'
           WHEN c.request_sender_id = auth.uid() THEN 'pending'
           ELSE 'pending_received'
         END AS state
  FROM conversations c
  WHERE auth.uid() IS NOT NULL
    AND p_other_user_id IS NOT NULL
    AND c.user_1 = LEAST(auth.uid(), p_other_user_id)
    AND c.user_2 = GREATEST(auth.uid(), p_other_user_id)
    AND (
      c.status = 'active'
      OR c.request_sender_id = auth.uid()
      OR (c.status = 'pending_request' AND c.request_expires_at > NOW())
    )
$$;
REVOKE ALL ON FUNCTION get_conversation_state_with(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_conversation_state_with(UUID) TO authenticated;

-- ---------- 9. get_discovery_cards (base 00425) : même directionnalité sur
-- contact_state ('none'|'pending'|'pending_received'|'connected'). Signature et
-- colonnes inchangées → CREATE OR REPLACE (pas de DROP, pas de surcharge). ----------
CREATE OR REPLACE FUNCTION get_discovery_cards()
RETURNS TABLE (
  user_id UUID, display_name TEXT, avatar_url TEXT, reliability_tier TEXT,
  sport_keys TEXT[], levels JSONB, transport_modes TEXT[], radius_km INTEGER,
  window_start TIMESTAMPTZ, window_end TIMESTAMPTZ, intent TEXT[],
  distance_km DOUBLE PRECISION, sorties_count INTEGER, about TEXT,
  contact_state TEXT, conversation_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
         (ST_Distance(d.base, v_base) / 1000.0) AS distance_km,
         (SELECT count(*)::int FROM participations p
          WHERE p.user_id = d.user_id AND p.status = 'accepted') AS sorties_count,
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
         ) AS conversation_id
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (v_radius IS NULL OR d.radius_km IS NULL
         OR ST_DWithin(d.base, v_base, (v_radius + d.radius_km) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  ORDER BY pp.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$$;
REVOKE ALL ON FUNCTION get_discovery_cards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_discovery_cards() TO authenticated;
