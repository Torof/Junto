-- ============================================================================
-- 00437 — Les messages d'un fil d'ACTIVITÉ mènent au chat de l'activité
-- (Scott 2026-10-05 : « quand on clique sur la messagerie du chat d'une
-- activité, ça nous envoie sur la page info, pas sur le chat »).
--
-- Le défaut avait deux visages. Côté client, la ligne de la messagerie et le
-- lien poussaient /activity/{id} sans onglet → « info » par défaut (corrigé par
-- un paramètre ?tab=chat, même OTA). Côté serveur — ce fichier — le push
-- « nouveau message » d'un fil d'activité ne portait QUE conversation_id : le
-- routeur l'envoyait sur /conversation/{id}, l'écran DM/groupe, qui ne sait pas
-- afficher un fil d'activité. Pire que l'onglet info : une impasse.
--
-- Fix : le payload push porte activity_id quand le fil est de type 'activity'.
-- DM et groupes inchangés. Un client non mis à jour ignore simplement le champ
-- et garde son ancien comportement.
--
-- Base vivante vérifiée : broadcast_and_push_message = 00366 (redéfinitions :
-- 00359, 00360, 00366). Corps repris à l'identique, seule la ligne 'data'
-- change. Signature inchangée (trigger). Contrôle du nombre de fonctions
-- créées : 1.
-- ============================================================================

CREATE OR REPLACE FUNCTION broadcast_and_push_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
            'body', left(NEW.content, 140),
            -- 00437 : pour un fil d'ACTIVITÉ, on ajoute activity_id. Sans lui, le
            -- routeur push ouvrait /conversation/{id} — l'écran DM/groupe, qui ne
            -- sait pas afficher un fil d'activité (le mur vit dans l'onglet chat de
            -- l'écran d'activité). Les DM et groupes gardent le payload d'origine.
            'data', CASE
              WHEN v_conv.type = 'activity' AND v_conv.activity_id IS NOT NULL THEN
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message',
                                   'activity_id', v_conv.activity_id)
              ELSE
                jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message')
            END,
            'collapseId', 'message-' || NEW.conversation_id::text
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

