-- ============================================================================
-- 00448 — Notifications multilingues, lot B : contacts, invitations, groupes.
-- Même principe que 00447 : title/body FR = secours, data.params (+ variant)
-- pour la composition dans la langue du lecteur. Copy FR alignée sur l'audit :
-- « X veut rejoindre ta sortie » / « Titre », « X t'invite à une sortie »
-- (plus « à rejoindre » suspendu), « a accepté ta demande de contact »,
-- « t'ajoute au groupe », guillemets systématiques sur le titre.
-- Rituel live-version : chaque fonction reconstruite depuis sa dernière
-- définition ; seuls les appels de notification changent ; grants conservés.
--   send_contact_request         ← 00426
--   accept_contact_request       ← 00426
--   send_discovery_invite        ← 00426
--   invite_users_to_activity     ← 00426
--   send_activity_invitations    ← 00426
--   accept_activity_invitation   ← 00365
--   join_activity                ← 00397
--   create_group                 ← 00364
--   add_group_member             ← 00364
-- ============================================================================

-- ---------- send_contact_request (base 00426) ----------
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
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id,
      'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un')))
  );

  RETURN v_conversation_id;
END;
$$;

-- ---------- accept_contact_request (base 00426) ----------
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
$$;

-- ---------- send_discovery_invite (base 00426) ----------
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
    '« ' || v_clean_title || ' »',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'activity_id', p_activity_id,
      'variant', 'invite', 'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
  );

  RETURN v_conversation_id;
END;
$$;

-- ---------- invite_users_to_activity (base 00426) ----------
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
            coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
            '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
            jsonb_build_object('type', 'contact_request', 'from_user_id', v_user_id, 'variant', 'invite',
              'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g'))),
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

-- ---------- send_activity_invitations (base 00426) ----------
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
      coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
      '« ' || v_clean_title || ' »', jsonb_build_object('activity_id', p_activity_id, 'type', 'activity_invitation',
        'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
    );
  END LOOP;
END;
$$;

-- ---------- accept_activity_invitation (base 00365) ----------
CREATE OR REPLACE FUNCTION accept_activity_invitation(p_activity_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_row RECORD;
  v_count INTEGER;
  v_updated INTEGER;
  v_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, deleted_at, max_participants, title INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id INTO v_row FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_count FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
  WHERE id = v_row.id AND status = 'invited';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  -- Row vanished between the SELECT and the UPDATE (concurrent decline / block
  -- cascade, which don't take the activity lock) → no phantom success/push.
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id, 'invitation_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ton invitation',
    '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
    jsonb_build_object('activity_id', p_activity_id,
      'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
  );
END;
$$;

-- ---------- join_activity (base 00397) ----------
CREATE OR REPLACE FUNCTION join_activity(p_activity_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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

  SELECT id, status, refused_at INTO v_existing
  FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
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
$$;

-- ---------- create_group (base 00364) ----------
CREATE OR REPLACE FUNCTION create_group(p_name TEXT, p_icon TEXT, p_member_ids UUID[])
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_n INTEGER;
  v_daily INTEGER;
  v_target UUID;
  v_retained UUID[] := '{}';
  v_conv_id UUID;
  v_caller_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := regexp_replace(trim(COALESCE(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_clean_name) < 1 OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;
  IF p_icon IS NOT NULL AND (char_length(p_icon) < 1 OR char_length(p_icon) > 8 OR p_icon ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;

  v_n := array_length(p_member_ids, 1);
  IF p_member_ids IS NULL OR v_n IS NULL OR v_n < 2 THEN
    RAISE EXCEPTION 'junto.group_min_members';  -- min 3 total (creator + 2)
  END IF;
  IF v_n > 19 THEN RAISE EXCEPTION 'junto.group_cap'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_group'));
  SELECT count(*) INTO v_daily FROM conversations
  WHERE type = 'group' AND created_by = v_user_id
    AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 5 THEN RAISE EXCEPTION 'junto.group_rate_limit'; END IF;

  FOR v_target IN SELECT DISTINCT unnest(p_member_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users bu
      JOIN unnest(v_retained) AS r(id) ON TRUE
      WHERE (bu.blocker_id = v_target AND bu.blocked_id = r.id)
         OR (bu.blocker_id = r.id AND bu.blocked_id = v_target)
    );
    v_retained := array_append(v_retained, v_target);
  END LOOP;

  -- ≥2 retained → group of ≥3 with the creator. A 1-retained result would be a
  -- DM-equivalent 2-person group; refuse (count only — no cause leaked).
  IF array_length(v_retained, 1) IS NULL OR array_length(v_retained, 1) < 2 THEN
    RAISE EXCEPTION 'junto.group_min_members';
  END IF;

  INSERT INTO conversations (type, status, name, icon, created_by, created_at, last_message_at)
  VALUES ('group', 'active', v_clean_name, p_icon, v_user_id, now(), now())
  RETURNING id INTO v_conv_id;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (v_conv_id, v_user_id, NULL, now());
  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  SELECT v_conv_id, r.id, v_user_id, now() FROM unnest(v_retained) AS r(id);

  SELECT display_name INTO v_caller_name FROM public_profiles WHERE id = v_user_id;
  FOR v_target IN SELECT unnest(v_retained) LOOP
    PERFORM create_notification(
      v_target, 'group_added',
      coalesce(v_caller_name, 'Quelqu''un') || ' t''ajoute au groupe',
      v_clean_name, jsonb_build_object('conversation_id', v_conv_id,
        'params', jsonb_build_object('name', coalesce(v_caller_name, 'Quelqu''un'), 'group', v_clean_name))
    );
  END LOOP;

  RETURN v_conv_id;
END;
$$;

-- ---------- add_group_member (base 00364) ----------
CREATE OR REPLACE FUNCTION add_group_member(p_conversation_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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
$$;
