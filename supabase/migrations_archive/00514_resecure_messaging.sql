-- ============================================================================
-- 00514 — Re-sécurisation, lot messagerie (audit neuf).
-- M1   Une demande de place ne crée ni ne réactive plus de conversation : seul
--      l'accord du conducteur le fait. Avant, demander puis annuler donnait
--      une conversation active, des droits d'ajout en groupe et d'invitation.
-- AB-12 create_group ne remet pas dans une copie du groupe quelqu'un qui en
--      est parti. Modération : un groupe renommé par l'admin reste figé ; une
--      discussion fermée ne se renomme plus et ses messages ne se réécrivent
--      plus ; reliquat « wall_message » retiré.
-- L4   Un compte suspendu ne lit plus aucune conversation (fonctions,
--      lecture directe, temps réel). Demandes de contact d'un suspendu masquées.
-- MS-3 Une invitation Découverte n'est pas renvoyée après un refus.
-- MS-6 / AB-11 Discussions bornées à 500 membres ; 10 appareils par compte.
-- ============================================================================

ALTER TABLE conversations ADD COLUMN IF NOT EXISTS moderated_at TIMESTAMPTZ;

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

  -- 00494 (BR-3): one seat per passenger and outing; a driver who carries
  -- passengers does not ride with someone else.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND driver_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';  -- 00496 (B-5): actionable, coded
  END IF;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  -- 00477 (DB-AC-2): test the id — the record has NULL columns, so the
  -- re-request branch was dead code and every re-request was refused.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    -- 00477 (AC-4 / AB-4): no request/cancel loop toward the same driver —
    -- 24 h after a refusal, 1 h after a cancellation or expiry.
    IF v_existing.status = 'declined' AND v_existing.created_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    IF v_existing.status IN ('cancelled', 'expired') AND v_existing.created_at > NOW() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
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

  -- 00514: a seat REQUEST never creates nor reactivates a conversation — only
  -- the driver's acceptance does (accept_seat_request). The seed message goes
  -- into an already active DM; otherwise the driver is notified only.
  IF v_conv_status IS DISTINCT FROM 'active' THEN
    v_conversation_id := NULL;
  END IF;

  IF v_conversation_id IS NOT NULL THEN
  v_seed_message := '🚗 Demande de place pour « ' || v_activity_title || ' »'
    || CASE WHEN v_pickup IS NOT NULL THEN E'\nDepuis : ' || v_pickup ELSE '' END
    || CASE WHEN v_message IS NOT NULL THEN E'\n\n' || v_message ELSE '' END;

  -- 00508: straight into the unified store (the legacy table and its mirror
  -- are gone). This writer notifies on its own: no generic message push.
  PERFORM set_config('junto.skip_message_push', 'true', true);
  INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, v_seed_message,
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

CREATE OR REPLACE FUNCTION public.create_group(p_name text, p_icon text, p_member_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- 00514 (AB-12): someone who left a group of this creator in the last 30
    -- days is not put into a fresh copy of it.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM conversation_departures d JOIN conversations c ON c.id = d.conversation_id
      WHERE d.user_id = v_target AND c.created_by = v_user_id AND d.at > now() - INTERVAL '30 days');
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
$function$;

CREATE OR REPLACE FUNCTION public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_found BOOLEAN := false;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF p_target_type NOT IN ('activity', 'message', 'group', 'channel', 'pro_review', 'offering_review') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  IF p_target_type = 'activity' THEN
    UPDATE activities SET deleted_at = now(), updated_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'message' THEN
    -- Unified store: reads come from `messages`. 'wall_message' kept for
    -- migrated ids (id is shared), 'message' for post-rebuild content.
    UPDATE messages SET deleted_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'group' THEN
    UPDATE conversations SET name = '[Groupe retiré]', icon = NULL, moderated_at = now()
    WHERE id = p_target_id AND type = 'group';
    v_found := FOUND;
  ELSIF p_target_type = 'channel' THEN
    -- 00507: a reported channel is closed (read-only, out of search).
    UPDATE channels SET closed_at = now()
    WHERE conversation_id = p_target_id AND closed_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'pro_review' THEN
    DELETE FROM pro_reviews WHERE id = p_target_id;
    v_found := FOUND;
  ELSIF p_target_type = 'offering_review' THEN
    DELETE FROM offering_reviews WHERE id = p_target_id;
    v_found := FOUND;
  END IF;

  IF NOT v_found THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM log_admin_action(v_admin, 'remove_content', p_target_type, p_target_id, v_reason, NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rename_group(p_conversation_id uuid, p_name text, p_icon text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Creator only (MVP), and the creator must still be a member.
  IF NOT EXISTS (
    SELECT 1 FROM conversations
    WHERE id = p_conversation_id AND type = 'group' AND created_by = v_user_id
      AND moderated_at IS NULL  -- 00514: a group renamed by moderation stays so
  ) OR NOT private.is_conversation_member(p_conversation_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := regexp_replace(trim(COALESCE(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_clean_name) < 1 OR char_length(v_clean_name) > 60 THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;
  IF p_icon IS NOT NULL AND (char_length(p_icon) < 1 OR char_length(p_icon) > 8 OR p_icon ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'junto.group_name_invalid';
  END IF;

  UPDATE conversations SET name = v_clean_name, icon = p_icon
  WHERE id = p_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rename_channel(p_conversation_id uuid, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00514: a closed discussion (by its creator or by moderation) is frozen.
  IF NOT EXISTS (SELECT 1 FROM channels WHERE conversation_id = p_conversation_id AND created_by = v_user_id AND closed_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_clean := NULLIF(trim(regexp_replace(COALESCE(p_name, ''), '<[^>]*>', '', 'g')), '');
  IF v_clean IS NULL OR char_length(v_clean) > 60 THEN RAISE EXCEPTION 'junto.channel_name'; END IF;
  UPDATE conversations SET name = v_clean WHERE id = p_conversation_id;
END;
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

  -- Must still be a member; for activity messages the activity must be alive
  -- (wall edit parity 00177).
  IF NOT private.is_conversation_member(v_conv_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_type = 'activity' AND NOT EXISTS (
    SELECT 1 FROM activities a WHERE a.id = v_activity_id
      AND a.deleted_at IS NULL AND a.status IN ('published', 'in_progress')
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00514: no rewriting in a closed discussion.
  IF v_type = 'channel' AND EXISTS (SELECT 1 FROM channels WHERE conversation_id = v_conv_id AND closed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00474 (counter-audit F5): keep the first version for moderation (internal
  -- table, no client grant) — an edit can no longer launder a thread.
  INSERT INTO message_original_content (message_id, content)
  SELECT id, content FROM messages WHERE id = p_message_id
  ON CONFLICT (message_id) DO NOTHING;

  UPDATE messages SET content = trim(p_content), edited_at = now()
  WHERE id = p_message_id;
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

CREATE OR REPLACE FUNCTION public.get_pending_contact_requests()
 RETURNS TABLE(id uuid, user_1 uuid, user_2 uuid, request_sender_id uuid, initiated_from text, request_message text, created_at timestamp with time zone, sender_name text, sender_avatar text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.id, c.user_1, c.user_2, c.request_sender_id, c.initiated_from,
         c.request_message, c.created_at,
         COALESCE(pp.display_name, '?') AS sender_name,
         pp.avatar_url AS sender_avatar
  FROM conversations c
  LEFT JOIN public_profiles pp ON pp.id = c.request_sender_id
  WHERE auth.uid() IS NOT NULL
    AND c.status = 'pending_request'
    AND (c.user_1 = auth.uid() OR c.user_2 = auth.uid())
    AND c.request_sender_id IS DISTINCT FROM auth.uid()
    AND NOT private.user_is_suspended(c.request_sender_id)  -- 00514
    AND (c.request_expires_at IS NULL OR c.request_expires_at > NOW())
  ORDER BY c.created_at DESC
$function$;

CREATE OR REPLACE FUNCTION public.join_channel(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_ch RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Serialize against remove_channel_member so a ban-check + INSERT can't
  -- interleave with a DELETE + ban INSERT (no member+banned state).
  PERFORM pg_advisory_xact_lock(hashtext(p_conversation_id::text || '_channel_members'));

  SELECT c.conversation_id, c.closed_at INTO v_ch
  FROM channels c WHERE c.conversation_id = p_conversation_id;
  IF v_ch.conversation_id IS NULL OR v_ch.closed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM channel_bans WHERE conversation_id = p_conversation_id AND user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00514 (MS-6): bounded discussions (each message fans out to every member).
  IF (SELECT count(*) FROM conversation_members WHERE conversation_id = p_conversation_id) >= 500 THEN
    RAISE EXCEPTION 'junto.channel_full';
  END IF;

  INSERT INTO conversation_members (conversation_id, user_id, added_by, joined_at)
  VALUES (p_conversation_id, v_user_id, NULL, now())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_device_id text DEFAULT NULL::text)
 RETURNS void
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

  IF p_token IS NULL OR char_length(p_token) < 20 OR char_length(p_token) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_token !~ '^Exp(o|onent)PushToken\[.+\]$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM push_tokens WHERE token = p_token AND user_id != v_user_id;

  IF p_device_id IS NOT NULL THEN
    DELETE FROM push_tokens
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND token != p_token;
    INSERT INTO push_tokens (user_id, token, device_id)
      VALUES (v_user_id, p_token, p_device_id)
      ON CONFLICT (user_id, token)
      DO UPDATE SET device_id = EXCLUDED.device_id;
  ELSE
    INSERT INTO push_tokens (user_id, token)
      VALUES (v_user_id, p_token)
      ON CONFLICT (user_id, token) DO NOTHING;
  END IF;

  -- 00514 (AB-11): at most 10 devices per account (oldest dropped).
  DELETE FROM push_tokens WHERE user_id = v_user_id AND token NOT IN (
    SELECT token FROM push_tokens WHERE user_id = v_user_id ORDER BY created_at DESC LIMIT 10);

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.is_conversation_member(p_conversation_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id
  )
  -- 00514: a suspended account reads no conversation any more.
  AND NOT private.user_is_suspended(p_user_id);
$function$;

ALTER POLICY realtime_activity_topics_read ON realtime.messages USING ((((realtime.topic() ~~ 'activity:%'::text) AND ((EXISTS ( SELECT 1
   FROM participations p
  WHERE (((p.activity_id)::text = "substring"(realtime.topic(), 10)) AND (p.user_id = auth.uid()) AND (p.status = 'accepted'::text)))) OR (EXISTS ( SELECT 1
   FROM activities a
  WHERE (((a.id)::text = "substring"(realtime.topic(), 10)) AND (a.creator_id = auth.uid()))))))) AND NOT private.user_is_suspended(auth.uid()));
ALTER POLICY realtime_conversation_topics_read ON realtime.messages USING ((((realtime.topic() ~~ 'conversation:%'::text) AND (EXISTS ( SELECT 1
   FROM conversation_members cm
  WHERE (((cm.conversation_id)::text = "substring"(realtime.topic(), 14)) AND (cm.user_id = auth.uid())))))) AND NOT private.user_is_suspended(auth.uid()));
