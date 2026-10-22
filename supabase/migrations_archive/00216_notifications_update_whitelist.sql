-- Migration 00216: pin notification fields to OLD on client UPDATE.
-- Closes group E from the parallel security audit.
--
-- Before: notifications table had `notifications_update_own` policy
-- (auth.uid() = user_id) with no whitelist trigger. Per SECURITY.md
-- only `read_at` should be client-modifiable; the user could in
-- principle rewrite their own notifications' `type`, `title`, `body`,
-- `data`, `created_at` directly via PostgREST `.update(...)`.
--
-- Realistic abuse: spoof a "Place confirmée" body and screenshot
-- to defraud, or rewrite `type`/`data` to confuse client routing
-- on tap. Low real-world impact in isolation but a plain principle
-- violation per CLAUDE.md ("All business rules at DB level").
--
-- Fix: BEFORE UPDATE trigger that pins everything except `read_at`
-- and `updated_at` (the latter doesn't exist — only `read_at` is
-- writable). SECURITY DEFINER functions creating notifications
-- always go through INSERT, not UPDATE, so no bypass needed —
-- there is no junto.bypass_lock branch and no SECURITY DEFINER
-- function should ever need to UPDATE a notification's content
-- after creation. If one ever does, add the bypass branch then.

CREATE OR REPLACE FUNCTION handle_notification_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- read_at is the only client-writable column. Everything else
  -- pins to OLD.
  NEW.id := OLD.id;
  NEW.user_id := OLD.user_id;
  NEW.type := OLD.type;
  NEW.title := OLD.title;
  NEW.body := OLD.body;
  NEW.data := OLD.data;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION handle_notification_update() FROM anon, authenticated;

DROP TRIGGER IF EXISTS on_notification_update ON notifications;
CREATE TRIGGER on_notification_update
  BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION handle_notification_update();
