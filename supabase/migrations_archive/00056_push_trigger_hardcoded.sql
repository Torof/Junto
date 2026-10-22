-- Migration 00056: inline edge function URL + anon key (ALTER DATABASE not allowed on hosted Supabase)

CREATE OR REPLACE FUNCTION trigger_send_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx2amx0aHpkeWR6YXRjdnd3cml1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU4MjUyNTMsImV4cCI6MjA5MTQwMTI1M30.cxBoxTF1eVNvA8kd_PhoLMmkdEbLvfyocm5kAWefEjM'
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
