-- ============================================================================
-- 00519 — Contre-vérification de 00512-00518.
-- F1  Pas de remise par une copie de groupe, quel que soit l'auteur de la copie.
-- F2  Groupe retiré par la modération : en lecture seule (messages, partages,
--     éditions, ajouts).
-- F3  delete_own_account n'est plus appelable par l'app : seule la fonction
--     delete-account (rôle service, après vérification du jeton) l'exécute,
--     ce qui efface aussi la connexion et les fichiers.
-- F4  Erreurs lisibles avant les contrôles de table (liens, durée d'offre).
-- F5  Durée figée avec participants : hors du test de chevauchement.
-- F6  Plafond de 10 appareils : on garde les plus récemment utilisés.
-- ============================================================================

CREATE OR REPLACE FUNCTION private.offering_duration_ok(p text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN p::interval BETWEEN INTERVAL '15 minutes' AND INTERVAL '30 days';
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$function$;
REVOKE ALL ON FUNCTION private.offering_duration_ok(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_account_as(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Called only by the delete-account edge function (service role), after it
  -- verified the caller's JWT. Runs the deletion as that user.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  PERFORM delete_own_account();
END;
$function$;
REVOKE ALL ON FUNCTION public.delete_account_as(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_as(uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.delete_own_account() FROM PUBLIC, anon, authenticated;

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
    -- 00519: …from any group the creator belongs to, not only their own.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM conversation_departures d
      JOIN conversation_members cm ON cm.conversation_id = d.conversation_id AND cm.user_id = v_user_id
      WHERE d.user_id = v_target AND d.at > now() - INTERVAL '30 days');
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
  -- 00519: also a group of the adder's that this person left (not only
  -- this one), so a copy of the group cannot pull them back.
  IF EXISTS (SELECT 1 FROM conversation_departures d
             WHERE d.conversation_id = p_conversation_id AND d.user_id = p_user_id
               AND d.at > now() - INTERVAL '30 days')
     OR EXISTS (
      SELECT 1 FROM conversation_departures d
      JOIN conversation_members cm ON cm.conversation_id = d.conversation_id AND cm.user_id = v_user_id
      WHERE d.user_id = p_user_id AND d.at > now() - INTERVAL '30 days') THEN
    RAISE EXCEPTION 'junto.member_left_recently';
  END IF;

  -- 00519: a group taken down by moderation is read-only.
  IF EXISTS (SELECT 1 FROM conversations WHERE id = p_conversation_id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
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

CREATE OR REPLACE FUNCTION private.assert_can_send(p_conversation_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_conv RECORD;
  v_other UUID;
BEGIN
  SELECT id, type, status, user_1, user_2, activity_id INTO v_conv
  FROM conversations WHERE id = p_conversation_id;
  IF v_conv.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: a group taken down by moderation is read-only.
  IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conv.id AND moderated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT private.is_conversation_member(p_conversation_id, p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_conv.type = 'dm' THEN
    IF v_conv.status != 'active' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_other := CASE WHEN v_conv.user_1 = p_user_id THEN v_conv.user_2 ELSE v_conv.user_1 END;
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = p_user_id AND blocked_id = v_other)
         OR (blocker_id = v_other AND blocked_id = p_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = v_conv.activity_id AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  ELSIF v_conv.type = 'channel' THEN
    -- Ban is authoritative on the send path (defense against a join/remove race
    -- that could leave a banned user with a stale membership row).
    IF EXISTS (
      SELECT 1 FROM channel_bans
      WHERE conversation_id = p_conversation_id AND user_id = p_user_id
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;
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
  -- 00519: a group taken down by moderation is read-only.
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

CREATE OR REPLACE FUNCTION public.register_as_pro(p_display_name text, p_company_name text, p_real_name text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_clean_name TEXT;
  v_clean_tagline TEXT;
  v_clean_description TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Required-field validation
  IF p_display_name IS NULL OR char_length(trim(p_display_name)) < 1 OR char_length(p_display_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NULL OR char_length(trim(p_company_name)) < 2 OR char_length(p_company_name) > 120 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NULL OR char_length(trim(p_real_name)) < 2 OR char_length(p_real_name) > 120 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_lng IS NULL OR p_primary_lat IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_primary_location_name IS NULL OR char_length(trim(p_primary_location_name)) < 1 OR char_length(p_primary_location_name) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00519: same link rules as the table checks, with a readable error.
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF (p_facebook IS NOT NULL AND p_facebook ~* '^[a-z][a-z0-9+.-]*:' AND p_facebook !~* '^https?://')
     OR (p_instagram IS NOT NULL AND p_instagram ~* '^[a-z][a-z0-9+.-]*:' AND p_instagram !~* '^https?://') THEN
    RAISE EXCEPTION 'junto.pro_website_invalid';
  END IF;

  v_clean_name := regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g');
  v_clean_tagline := CASE WHEN p_tagline IS NOT NULL AND char_length(trim(p_tagline)) > 0
                          THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE NULL END;
  v_clean_description := CASE WHEN p_description IS NOT NULL AND char_length(trim(p_description)) > 0
                              THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE NULL END;

  INSERT INTO pro_profiles (
    user_id, display_name, company_name, real_name, status, tagline, description,
    website, email, phone, instagram, facebook,
    primary_lng, primary_lat, primary_location, primary_location_name
  )
  VALUES (
    v_user_id, v_clean_name,
    regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g'),
    regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g'),
    'pending', v_clean_tagline, v_clean_description,
    p_website, p_email, p_phone, p_instagram, p_facebook,
    p_primary_lng, p_primary_lat,
    ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography,
    trim(p_primary_location_name)
  );
  -- NB: tier stays 'free' — approve_pro flips it to 'pro'.
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
  -- 00519: same link rules as the table checks, with a readable error.
  IF p_website IS NOT NULL AND p_website !~* '^https?://[^[:space:]]+$' THEN RAISE EXCEPTION 'junto.pro_website_invalid'; END IF;
  IF (p_facebook IS NOT NULL AND p_facebook ~* '^[a-z][a-z0-9+.-]*:' AND p_facebook !~* '^https?://')
     OR (p_instagram IS NOT NULL AND p_instagram ~* '^[a-z][a-z0-9+.-]*:' AND p_instagram !~* '^https?://') THEN
    RAISE EXCEPTION 'junto.pro_website_invalid';
  END IF;
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

CREATE OR REPLACE FUNCTION public.create_pro_offering(p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_schedule_text text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_price_eur numeric DEFAULT NULL::numeric, p_price_unit text DEFAULT NULL::text, p_min_participants integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_offering_id UUID;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00519: duration between 15 min and 30 days, readable error.
  IF p_duration IS NOT NULL AND NOT private.offering_duration_ok(p_duration) THEN RAISE EXCEPTION 'junto.offering_duration'; END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND (p_min_participants < 1 OR p_min_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND p_max_participants IS NOT NULL
     AND p_min_participants > p_max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_eur IS NOT NULL AND (p_price_eur <= 0 OR p_price_eur > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_unit IS NOT NULL AND p_price_unit NOT IN ('person', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_price_eur IS NULL) <> (p_price_unit IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('create_offering:' || v_user_id::text));

  SELECT count(*) INTO v_count
  FROM pro_offerings
  WHERE pro_id = v_user_id;

  -- 12: covers the typical catalogue, forces curation, and keeps the
  -- permanent-pin density on the map under control (RA pins accumulate,
  -- UA pins expire). Raise later if real pros ask — never lower.
  IF v_count >= 12 THEN RAISE EXCEPTION 'junto.offering_cap'; END IF;

  INSERT INTO pro_offerings (
    pro_id, sport_id, title, description, level,
    location, location_name,
    duration, max_participants, schedule_text,
    distance_km, elevation_gain_m,
    price_eur, price_unit, min_participants,
    created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_clean_title, p_description, p_level,
    ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    v_clean_location_name,
    CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    p_max_participants,
    v_clean_schedule,
    p_distance_km,
    p_elevation_gain_m,
    p_price_eur,
    p_price_unit,
    p_min_participants,
    now(), now()
  ) RETURNING id INTO v_offering_id;

  RETURN v_offering_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_pro_offering(p_offering_id uuid, p_sport_id uuid, p_title text, p_description text, p_level text, p_location_lng double precision, p_location_lat double precision, p_location_name text, p_duration text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_schedule_text text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_price_eur numeric DEFAULT NULL::numeric, p_price_unit text DEFAULT NULL::text, p_min_participants integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00519: duration between 15 min and 30 days, readable error.
  IF p_duration IS NOT NULL AND NOT private.offering_duration_ok(p_duration) THEN RAISE EXCEPTION 'junto.offering_duration'; END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Ownership check
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Input validation (identical to create)
  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND (p_min_participants < 1 OR p_min_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_min_participants IS NOT NULL AND p_max_participants IS NOT NULL
     AND p_min_participants > p_max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_eur IS NOT NULL AND (p_price_eur <= 0 OR p_price_eur > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_unit IS NOT NULL AND p_price_unit NOT IN ('person', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_price_eur IS NULL) <> (p_price_unit IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_offerings SET
    sport_id = p_sport_id,
    title = v_clean_title,
    description = p_description,
    level = p_level,
    location = ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    location_name = v_clean_location_name,
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    max_participants = p_max_participants,
    schedule_text = v_clean_schedule,
    distance_km = p_distance_km,
    elevation_gain_m = p_elevation_gain_m,
    price_eur = p_price_eur,
    price_unit = p_price_unit,
    min_participants = p_min_participants
  WHERE id = p_offering_id;
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
  -- 00516: coordinates must be real places.
  IF NOT ((p_meeting_lng IS NULL AND p_meeting_lat IS NULL) OR (p_meeting_lng BETWEEN -180 AND 180 AND p_meeting_lat BETWEEN -90 AND 90)) THEN
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
  -- 00519: with accepted participants the duration is frozen by the trigger,
  -- so it must not take part in the conflict test.
  IF EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id <> v_user_id) THEN
    p_duration := NULL;
  END IF;
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
    -- 00516 (AC-7): requesters are told too — they must not be accepted
    -- into an outing that changed under them without knowing.
    WHERE activity_id = p_activity_id AND status IN ('accepted', 'pending') AND user_id != v_user_id
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
      DO UPDATE SET device_id = EXCLUDED.device_id, created_at = now();  -- 00519: last use
  ELSE
    INSERT INTO push_tokens (user_id, token)
      VALUES (v_user_id, p_token)
      ON CONFLICT (user_id, token) DO UPDATE SET created_at = now();  -- 00519: last use
  END IF;

  -- 00514 (AB-11): at most 10 devices per account (oldest dropped).
  DELETE FROM push_tokens WHERE user_id = v_user_id AND token NOT IN (
    SELECT token FROM push_tokens WHERE user_id = v_user_id ORDER BY created_at DESC LIMIT 10);

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$function$;
