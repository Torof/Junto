-- 00549 — the server-written texts say askandgo, not Junto (rename, Scott 2026-10-23).
--
-- Only two functions write the name in what users read:
--   - broadcast_and_push_message: the push title / name param when the sender
--     has no display name;
--   - delete_own_account: the notices « l'organisateur a quitté … » and
--     « le professionnel n'est plus sur … ».
-- Both rebuilt from their live definitions; only those literals change.
-- CREATE OR REPLACE keeps owners and grants.

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
    v_title := coalesce(v_sender_name, 'askandgo');
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
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'askandgo'),
                                     'context', (SELECT regexp_replace(a.title, '<[^>]*>', '', 'g') FROM activities a WHERE a.id = v_conv.activity_id),
                                     'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
              WHEN v_conv.name IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'askandgo'),
                                     'context', v_conv.name, 'preview', left(regexp_replace(NEW.content, '[[:cntrl:]]', ' ', 'g'), 140)))
              ELSE
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message', 'variant', 'dm',
                                   'params', jsonb_build_object('name', coalesce(v_sender_name, 'askandgo'),
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
$function$

;

CREATE OR REPLACE FUNCTION public.delete_own_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_channel RECORD;
  v_new_owner UUID;
  v_booking RECORD;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 2. Cancel all active activities created by user + notify participants
  FOR v_activity IN
    SELECT id, title FROM activities
    WHERE creator_id = v_user_id AND status IN ('published', 'in_progress')
  LOOP
    UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = v_activity.id;

    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = v_activity.id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_cancelled',
        'Sortie annulée',
        '« ' || v_activity.title || ' » — l''organisateur a quitté askandgo',
        jsonb_build_object('activity_id', v_activity.id, 'variant', 'creator_gone',
          'params', jsonb_build_object('title', v_activity.title))
      );
    END LOOP;
  END LOOP;

  -- 2b. Channels created by the user: hand the hub to the earliest remaining
  -- member so it keeps a moderator; if none remain, close it. Before the user
  -- delete so the created_by FK no longer references these rows.
  FOR v_channel IN
    SELECT conversation_id FROM channels WHERE created_by = v_user_id
  LOOP
    SELECT user_id INTO v_new_owner
    FROM conversation_members
    WHERE conversation_id = v_channel.conversation_id AND user_id != v_user_id
    ORDER BY joined_at ASC
    LIMIT 1;

    IF v_new_owner IS NOT NULL THEN
      UPDATE channels SET created_by = v_new_owner WHERE conversation_id = v_channel.conversation_id;
      UPDATE conversations SET created_by = v_new_owner WHERE id = v_channel.conversation_id;
    ELSE
      UPDATE channels SET closed_at = now()
      WHERE conversation_id = v_channel.conversation_id AND closed_at IS NULL;
    END IF;
  END LOOP;

  -- 2c. Réservations futures (00419 M1) : le CASCADE va les effacer sans un
  -- mot — prévenir la contrepartie AVANT. Miroir du bloc activités : pro
  -- supprimé → tout client (pending ou accepté) est prévenu ; client supprimé
  -- → le pro n'est prévenu que pour du confirmé (un pending qui disparaît
  -- reste silencieux, pattern cancel_booking).
  FOR v_booking IN
    SELECT b.id, b.day, b.pro_id, b.client_id, b.status, po.title
    FROM bookings b
    LEFT JOIN pro_offerings po ON po.id = b.offering_id
    WHERE (b.pro_id = v_user_id OR b.client_id = v_user_id)
      AND b.status IN ('pending', 'accepted')
      AND b.day >= private.today_paris()
  LOOP
    IF v_booking.pro_id = v_user_id THEN
      IF v_booking.client_id IS NOT NULL THEN
        PERFORM create_notification(
          v_booking.client_id,
          'booking_cancelled',
          'Sortie annulée',
          '« ' || coalesce(v_booking.title, 'Ta sortie') || ' » du '
            || to_char(v_booking.day, 'DD/MM') || ' est annulée — le professionnel n''est plus sur askandgo.',
          jsonb_build_object('booking_id', v_booking.id, 'by', 'pro', 'variant', 'pro_gone',
            'params', jsonb_build_object('title', coalesce(v_booking.title, 'Ta sortie'), 'date', to_char(v_booking.day, 'YYYY-MM-DD')))
        );
      END IF;
    ELSIF v_booking.status = 'accepted' THEN
      PERFORM create_notification(
        v_booking.pro_id,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_booking.title, 'une sortie') || ' » du '
          || to_char(v_booking.day, 'DD/MM') || ' a été annulée (compte supprimé).',
        jsonb_build_object('booking_id', v_booking.id, 'by', 'client', 'variant', 'client_gone',
          'params', jsonb_build_object('title', coalesce(v_booking.title, 'une sortie'), 'date', to_char(v_booking.day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;

  -- 3. Wall messages: anonymize (SET NULL handled by FK ON DELETE SET NULL)
  -- 4. Private messages: deleted by FK ON DELETE CASCADE
  -- 5. Conversations: deleted by FK ON DELETE CASCADE
  -- 6. Participations: deleted by FK ON DELETE CASCADE
  -- 7. Notifications: deleted by FK ON DELETE CASCADE
  -- 8. Blocked users: deleted by FK ON DELETE CASCADE
  -- 9. Reputation votes: deleted by FK ON DELETE CASCADE
  -- 10. Reports: reporter anonymisé (reporter_id → SET NULL depuis 00418 ;
  --     l'historique de modération survit sans identité)

  -- 11. Delete the user row — FKs handle cascading
  DELETE FROM users WHERE id = v_user_id;
END;
$function$

;
