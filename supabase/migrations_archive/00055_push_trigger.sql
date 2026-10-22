-- Migration 00055: HTTP trigger on notifications → edge function → Expo Push

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- The edge function URL and anon key are stored as database-level settings.
-- Set them after deploying the edge function:
--
--   ALTER DATABASE postgres SET app.edge_url = 'https://<project-ref>.supabase.co/functions/v1/send-push';
--   ALTER DATABASE postgres SET app.anon_key = '<anon-key>';

CREATE OR REPLACE FUNCTION trigger_send_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_edge_url TEXT := current_setting('app.edge_url', true);
  v_anon_key TEXT := current_setting('app.anon_key', true);
BEGIN
  IF v_edge_url IS NULL OR v_edge_url = '' THEN
    RETURN NEW; -- not configured yet, silently skip
  END IF;

  PERFORM net.http_post(
    url := v_edge_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon_key, '')
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body,
      'data', NEW.data
    )
  );

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION trigger_send_push FROM anon, authenticated;

DROP TRIGGER IF EXISTS on_notification_insert_push ON notifications;
CREATE TRIGGER on_notification_insert_push
  AFTER INSERT ON notifications
  FOR EACH ROW EXECUTE FUNCTION trigger_send_push();
