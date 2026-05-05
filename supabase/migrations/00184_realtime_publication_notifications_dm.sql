-- Migration 00184: notifications + private_messages → supabase_realtime publication.
--
-- Slice 2 retry. The original 00179 added these tables but was git-reverted
-- after the launch-time crash; the DB-side ALTER PUBLICATION effects had
-- survived the revert (verified: still in publication today). This migration
-- is the canonical idempotent record so a fresh-rebuild environment matches.
--
-- The crash was NOT caused by adding these tables to the publication — it
-- was caused by putting the subscriptions inside the tab-icon components
-- whose wiggle Animated.sequence raced with the invalidation re-renders.
-- Slice 2 retry moves the subscriptions to the TabsLayout parent, so this
-- migration is just bookkeeping.
--
-- Both tables have RLS that lets the row owner see their own row, so
-- postgres_changes is the right primitive (no broadcast trigger needed).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'private_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_messages;
  END IF;
END $$;
