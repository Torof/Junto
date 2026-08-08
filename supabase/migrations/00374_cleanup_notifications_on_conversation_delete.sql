-- ============================================================================
-- 00374 — Audit M6: purge notifications when their conversation is deleted.
--
-- Notifications carry conversation_id in their `data` JSONB (not a FK column, so
-- no CASCADE). remove_connection (00372) and leave_group's last-member tombstone
-- (00364) delete conversations, leaving *_accepted / group_added notifications
-- deep-linking to a dead thread. An AFTER DELETE trigger cleans them. (The client
-- already degrades gracefully to the "unavailable" screen; this removes the dead
-- rows so they don't sit in the inbox until the 7-day purge.)
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_notifications_on_conversation_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM notifications WHERE data->>'conversation_id' = OLD.id::text;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_cleanup_notifications_on_conversation_delete ON conversations;
CREATE TRIGGER trg_cleanup_notifications_on_conversation_delete
  AFTER DELETE ON conversations
  FOR EACH ROW EXECUTE FUNCTION cleanup_notifications_on_conversation_delete();
