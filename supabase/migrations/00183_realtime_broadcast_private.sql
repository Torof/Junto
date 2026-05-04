-- Migration 00183: switch broadcast to private + add Realtime RLS policy.
--
-- 00182's trigger wrote messages with private=false and clients
-- subscribed without { config: { private: true } }. Messages landed
-- in realtime.messages but were never delivered to subscribers.
-- Supabase's documented broadcast-from-Postgres pattern uses private
-- broadcasts plus an RLS policy on realtime.messages — that's what
-- this migration switches to.

CREATE OR REPLACE FUNCTION broadcast_activity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  v_activity_id := COALESCE(
    (CASE WHEN TG_OP <> 'DELETE' THEN NEW.activity_id END),
    (CASE WHEN TG_OP <> 'INSERT' THEN OLD.activity_id END)
  );
  IF v_activity_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM realtime.send(
    jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP),
    'change',
    'activity:' || v_activity_id::text,
    true  -- private channel; payload is just { table, op }, no row data
  );

  RETURN NULL;
END;
$$;

-- Realtime Authorization: any authenticated user can read broadcasts on
-- activity:* topics. We don't fine-grain by activity membership here
-- because the payload has no sensitive data ({ table, op } only) and
-- because the activity ID alone isn't useful without already knowing it.
-- A future hardening pass can tighten this to "user is participant of
-- activity_id parsed from topic" — for now, the permissive form gets
-- realtime working without leaking row content.
DROP POLICY IF EXISTS "realtime_activity_topics_read" ON realtime.messages;
CREATE POLICY "realtime_activity_topics_read"
  ON realtime.messages
  FOR SELECT
  TO authenticated
  USING (
    realtime.topic() LIKE 'activity:%'
  );
