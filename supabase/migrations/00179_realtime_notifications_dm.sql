-- Migration 00179: extend supabase_realtime publication to notifications + DMs.
--
-- Slice 2 of the realtime invalidation pass (00178 covered activity-scoped
-- coordination tables). These two drive the persistent tab-bar badges:
--   - notifications → bell icon + count
--   - private_messages → DM tab dot + per-conversation message stream
--
-- The DM conversation screen already has a postgres_changes subscription on
-- private_messages that's been silently failing since launch — adding it to
-- the publication fixes it without any client change.
--
-- No table filter on the publication side — RLS gates event delivery on the
-- server, so the listener only receives events for rows it can SELECT.

ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE private_messages;
