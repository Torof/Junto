-- ============================================================================
-- 00366 — Post-code audit: no double push via the mirror bridge.
--
-- The three legacy writers (invite card branch, request_seat, accept_seat_
-- request) push through their OWN path (inline http_post / create_notification).
-- The 00361 mirror then copies their private_messages row into `messages`, which
-- fires broadcast_and_push_message → a SECOND push. Fix: the mirror sets a
-- txn-local flag; the message trigger keeps the realtime broadcasts (so the new
-- client sees the message live) but skips its push leg when the flag is set.
-- Disappears when the legacy writers are ported and the mirror dropped (Brique 3).
-- ============================================================================

CREATE OR REPLACE FUNCTION mirror_private_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Legacy writer already pushed; suppress the mirrored row's push leg.
  PERFORM set_config('junto.skip_message_push', 'true', true);
  INSERT INTO messages (id, conversation_id, sender_id, content, metadata,
                        reply_to_message_id, edited_at, deleted_at, created_at)
  VALUES (NEW.id, NEW.conversation_id, NEW.sender_id, NEW.content, NEW.metadata,
          NEW.reply_to_message_id, NEW.edited_at, NEW.deleted_at, NEW.created_at)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

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
            'data', jsonb_build_object('conversation_id', NEW.conversation_id, 'type', 'new_message'),
            'collapseId', 'message-' || NEW.conversation_id::text
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
