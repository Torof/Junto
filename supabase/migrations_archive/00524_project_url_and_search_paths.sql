-- 00524 — migration readiness, done on the old project first (pre-mortem 2026-10-22).
--
--  1. The project host lives in app_config (project_url) instead of being
--     written into 7 functions: send-push calls and the storage URL checks
--     (avatars, pro photos, channel photos) read private.project_url().
--     FAIL-CLOSED: a missing or malformed value refuses every uploaded URL and
--     skips pushes — never accepts a foreign host.
--  2. The 6 functions that use PostGIS operators get `extensions` in their
--     search_path (no change while PostGIS is in public; required once it
--     lives in the extensions schema on the new project).
--  3. private.pro_photo_url_ok gets a pinned search_path and becomes STABLE
--     (it now reads app_config).

INSERT INTO public.app_config (name, value)
VALUES ('project_url', 'https://lvjlthzdydzatcvwwriu.supabase.co')
ON CONFLICT (name) DO NOTHING;

-- The project's public base URL, or NULL when missing / malformed (no
-- trailing slash, https only, plain host name).
CREATE OR REPLACE FUNCTION private.project_url()
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT value FROM app_config
  WHERE name = 'project_url' AND value ~ '^https://[a-z0-9-]+(\.[a-z0-9-]+)+$';
$function$;
REVOKE ALL ON FUNCTION private.project_url() FROM PUBLIC, anon, authenticated;

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
  IF private.project_url() IS NULL  -- 00524: fail-closed without a project URL
     OR NEW.avatar_url NOT LIKE private.project_url() || '/storage/v1/object/public/avatars/' || NEW.id::text || '/%'
     OR NEW.avatar_url ~* '(\.\.|%2e|%2f|%5c|\\)' THEN  -- 00503: no climbing out of the folder
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN NEW;
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
       OR private.project_url() IS NULL  -- 00524: fail-closed without a project URL
       OR v_photo NOT LIKE private.project_url() || '/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
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
       OR private.project_url() IS NULL  -- 00524: fail-closed without a project URL
       OR v_photo NOT LIKE private.project_url() || '/storage/v1/object/public/channel-photos/' || v_user_id::text || '/%'
       OR v_photo ~* '(\.\.|%2e|%2f|%5c|\\)'  -- 00503
     ) THEN
    RAISE EXCEPTION 'junto.channel_photo';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE channels SET photo_url = v_photo WHERE conversation_id = p_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.pro_photo_url_ok(p_url text, p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT p_url IS NOT NULL
     AND char_length(p_url) BETWEEN 1 AND 500
     -- 00524: host from app_config; NULL (missing URL) counts as refused.
     AND coalesce(p_url LIKE private.project_url() || '/storage/v1/object/public/pro-photos/' || p_uid::text || '/%', false)
     -- 00501 (PO-8): no path climbing out of the own folder (« .. », encoded or not).
     AND p_url !~* '(\.\.|%2e|%2f|%5c|\\)';
$function$;

CREATE OR REPLACE FUNCTION public.push_notification_to_device()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_should_push BOOLEAN := TRUE;
  v_collapse_id TEXT;
  v_activity_starts TIMESTAMPTZ;
  v_changes JSONB;
  v_secret TEXT;
  v_activity_id TEXT;
  v_presence_count INT;
  v_title TEXT := NEW.title;
  v_forwarded_data JSONB;
  v_allowed_keys TEXT[] := ARRAY[
    'activity_id',
    'conversation_id',
    'seat_request_id',
    'driver_id',
    'requester_id',
    'from_user_id',
    -- 00472 (audit M7): send-push composes the text in the recipient's
    -- language from these (lots A-F, 00447-00450). Display names, titles,
    -- dates only — the same facts the French body already carries.
    'params',
    'variant',
    -- 00523: routing keys for bookings, reviews and pro pages (ids only).
    'by',
    'pro_id',
    'offering_id',
    'booking_id'
  ];
BEGIN
  IF (NEW.data ? 'skip_push') AND ((NEW.data->>'skip_push')::boolean IS TRUE) THEN
    RETURN NEW;
  END IF;

  CASE NEW.type
    WHEN 'rate_participants', 'request_refused' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

    WHEN 'badge_unlocked' THEN
      v_collapse_id := 'badge-' || NEW.user_id::text
                       || '-' || to_char(NEW.created_at, 'YYYY-MM-DD');

    WHEN 'presence_pre_warning', 'presence_validate_now', 'presence_validate_warning' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
        SELECT count(*) INTO v_presence_count
        FROM notifications
        WHERE user_id = NEW.user_id
          AND type IN ('presence_pre_warning', 'presence_validate_now', 'presence_validate_warning')
          AND (data->>'activity_id') = v_activity_id
          AND created_at > NOW() - INTERVAL '24 hours';
        IF v_presence_count > 1 THEN
          v_title := v_title || ' (×' || v_presence_count || ')';
        END IF;
      END IF;

    WHEN 'presence_confirmed' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
      END IF;

    WHEN 'activity_cancelled' THEN
      SELECT starts_at INTO v_activity_starts
      FROM activities WHERE id = (NEW.data->>'activity_id')::uuid;
      v_should_push := v_activity_starts IS NULL
                       OR (v_activity_starts - now() < INTERVAL '48 hours');

    WHEN 'activity_updated' THEN
      v_changes := NEW.data->'changes';
      v_should_push := v_changes IS NOT NULL AND (
        v_changes ? 'starts_at' OR v_changes ? 'duration'
        OR v_changes ? 'location_meeting'
        OR v_changes ? 'max_participants' OR v_changes ? 'level'
        OR v_changes ? 'trace'  -- 00475: route changed after sign-up
      );

    ELSE
      v_should_push := TRUE;
  END CASE;

  IF NOT v_should_push THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL OR private.project_url() IS NULL THEN RETURN NEW; END IF;  -- 00524

  -- Strict allow-list — anything not in v_allowed_keys is dropped
  -- before the payload leaves the DB. `type` is always added (the
  -- client routes on it).
  SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb)
    INTO v_forwarded_data
  FROM jsonb_each(COALESCE(NEW.data, '{}'::jsonb))
  WHERE key = ANY(v_allowed_keys);

  v_forwarded_data := v_forwarded_data || jsonb_build_object('type', NEW.type);

  PERFORM net.http_post(
    url := private.project_url() || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', v_title,
      'body', NEW.body,
      'data', v_forwarded_data,
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
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
    IF v_secret IS NOT NULL AND private.project_url() IS NOT NULL THEN  -- 00524
      BEGIN
        PERFORM net.http_post(
          url := private.project_url() || '/functions/v1/send-push',
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

CREATE OR REPLACE FUNCTION public.notify_participant_joined(p_creator_id uuid, p_activity_id uuid, p_joiner_name text, p_activity_title text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_existing RECORD;
  v_count INTEGER;
  v_recent_names JSONB;
  v_clean_name TEXT;
  v_clean_title TEXT;
  v_body TEXT;
  v_secret TEXT;
  v_names_arr TEXT[];
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_joiner_name, 'Quelqu''un'));
  v_clean_title := sanitize_notif_text(coalesce(p_activity_title, ''));

  SELECT id, data INTO v_existing
  FROM notifications
  WHERE user_id = p_creator_id
    AND type = 'participant_joined'
    AND (data->>'activity_id')::uuid = p_activity_id
    AND read_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_existing IS NULL THEN
    PERFORM create_notification(
      p_creator_id,
      'participant_joined',
      'Nouveau participant',
      v_clean_name || ' a rejoint « ' || v_clean_title || ' »',
      jsonb_build_object(
        'activity_id', p_activity_id,
        'count', 1,
        'recent_names', jsonb_build_array(v_clean_name),
        'params', jsonb_build_object('name', v_clean_name, 'title', v_clean_title)
      )
    );
    RETURN;
  END IF;

  v_count := COALESCE((v_existing.data->>'count')::int, 1) + 1;
  v_recent_names := COALESCE(v_existing.data->'recent_names', '[]'::jsonb)
                    || jsonb_build_array(v_clean_name);
  -- Keep at most last 3 names
  IF jsonb_array_length(v_recent_names) > 3 THEN
    v_recent_names := jsonb_path_query_array(v_recent_names, '$[1 to last]');
  END IF;

  SELECT array_agg(value) INTO v_names_arr
  FROM jsonb_array_elements_text(v_recent_names) WITH ORDINALITY;

  IF v_count = 2 THEN
    v_body := v_names_arr[1] || ' et ' || v_names_arr[2] || ' ont rejoint ' || v_clean_title;
  ELSE
    v_body := v_names_arr[array_upper(v_names_arr, 1)]
              || ' et ' || (v_count - 1)::text || ' autres ont rejoint ' || v_clean_title;
  END IF;

  UPDATE notifications
  SET body = v_body,
      data = jsonb_set(
        jsonb_set(v_existing.data, '{count}', to_jsonb(v_count)),
        '{recent_names}', v_recent_names
      ),
      created_at = now(),
      read_at = NULL
  WHERE id = v_existing.id;

  -- AFTER INSERT trigger doesn't fire on UPDATE, so push manually with collapseId
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL AND private.project_url() IS NOT NULL THEN  -- 00524
    PERFORM net.http_post(
      url := private.project_url() || '/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', p_creator_id,
        'title', 'Nouveau participant',
        'body', v_body,
        'data', jsonb_build_object(
          'activity_id', p_activity_id,
          'count', v_count,
          'type', 'participant_joined'
        ),
        'collapseId', 'joined-' || p_activity_id::text
      )
    );
  END IF;
END;
$function$;

-- PostGIS operators resolve through search_path: ready for the extensions schema.
ALTER FUNCTION public.get_activity_detail(uuid) SET search_path = public, extensions;
ALTER FUNCTION public.get_activity_by_invite_token(uuid) SET search_path = public, extensions;
ALTER FUNCTION public.register_as_pro(text, text, text, text, text, text, text, text, text, text, double precision, double precision, text) SET search_path = public, extensions;
ALTER FUNCTION public.update_pro_profile(text, text, text, text, text, text, text, text, double precision, double precision, text, text, text, text[]) SET search_path = public, extensions;
ALTER FUNCTION public.handle_activity_update() SET search_path = public, extensions;
ALTER FUNCTION public.broadcast_map_activity() SET search_path = public, extensions;
