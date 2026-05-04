-- Migration 00181: ensure realtime publication membership (slice 1, recovery).
--
-- Background: migrations 00178/79/80 were git-reverted after a launch-time
-- crash on devices, but their DB-side ALTER PUBLICATION effects remained
-- applied on the live database. This migration is the canonical record of
-- which tables belong in supabase_realtime, written idempotently so it's
-- safe whether the environment already has the changes or not.
--
-- Slice 1 (this migration) covers the activity-coordination set:
-- wall_messages, participations, seat_requests, activity_gear. Slice 2
-- (notifications, private_messages) and slice 3 (activities) come back
-- in separate migrations once the slice 1 client subscription is
-- verified safe on two devices.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'wall_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE wall_messages;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'participations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE participations;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'seat_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE seat_requests;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'activity_gear'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE activity_gear;
  END IF;
END $$;
