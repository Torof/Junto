-- ============================================================================
-- 00359 — Realtime broadcast + batched push (brique 2, part 7 — lot ⑤).
--
-- One AFTER INSERT trigger on `messages` handles BOTH liveness channels:
--   • broadcast 'change' on topic conversation:<id>  (thread screens)
--   • broadcast 'inbox'  on topic user:<id>          (hub badge, per recipient)
--   • ONE batched net.http_post to send-push (user_ids[]) — recipients =
--     members − sender − members who blocked the sender (push suppressed,
--     message stays visible — the WhatsApp choice).
-- All side-channels are exception-swallowed (00202 doctrine: a broker or
-- queue hiccup must never abort the user's write).
-- postgres_changes on the old message tables is retired (publication drop);
-- `notifications` stays published (Demandes liveness).
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

  -- Thread liveness ping.
  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'messages', 'op', 'INSERT',
                         'conversation_id', NEW.conversation_id, 'message_id', NEW.id),
      'change',
      'conversation:' || NEW.conversation_id::text,
      true
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Recipients: members minus sender minus blockers-of-sender.
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

  -- Hub badge ping, per recipient (bounded by the 20-member group cap).
  FOREACH v_uid IN ARRAY v_recipients LOOP
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('conversation_id', NEW.conversation_id),
        'inbox',
        'user:' || v_uid::text,
        true
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;

  -- Batched push: one queue row, the edge function fans out to devices.
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

  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_messages_broadcast_push
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION broadcast_and_push_message();

-- ---------- topic policies ----------
-- Thread topics: members only. Text comparison (no ::uuid cast → malformed
-- topics simply match nothing instead of raising inside the policy).
DROP POLICY IF EXISTS "realtime_conversation_topics_read" ON realtime.messages;
CREATE POLICY "realtime_conversation_topics_read"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    realtime.topic() LIKE 'conversation:%'
    AND EXISTS (
      SELECT 1 FROM public.conversation_members cm
      WHERE cm.conversation_id::text = substring(realtime.topic(), 14)
        AND cm.user_id = auth.uid()
    )
  );

-- Personal inbox topic: strictly self.
DROP POLICY IF EXISTS "realtime_user_topic_read" ON realtime.messages;
CREATE POLICY "realtime_user_topic_read"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (realtime.topic() = 'user:' || auth.uid()::text);

-- ---------- retire postgres_changes on the legacy tables ----------
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE wall_messages;
EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE private_messages;
EXCEPTION WHEN OTHERS THEN NULL; END $$;
