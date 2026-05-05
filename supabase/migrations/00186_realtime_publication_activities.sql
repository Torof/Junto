-- Migration 00186: ensure activities is in supabase_realtime publication.
--
-- Slice 3 of the staged retry. Original 00180 was reverted but its DB-side
-- effect (activities in publication) survived; this migration is the
-- idempotent canonical record for that slice. Drives the nearby-map and
-- list views — when an activity is created, edited, or cancelled, the
-- map should refresh without a manual pan or app restart.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE activities;
  END IF;
END $$;
