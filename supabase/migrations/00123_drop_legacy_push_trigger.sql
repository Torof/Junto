-- Migration 00123: drop the legacy push trigger from 00055.
-- Migration 00117 added the new push trigger (trg_notification_push +
-- push_notification_to_device) without dropping the older one
-- (on_notification_insert_push + trigger_send_push from 00055). Both fire
-- AFTER INSERT on notifications, producing a duplicate push per row.

DROP TRIGGER IF EXISTS on_notification_insert_push ON notifications;
DROP FUNCTION IF EXISTS trigger_send_push();
