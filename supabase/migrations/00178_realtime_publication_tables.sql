-- Migration 00178: add coordination tables to supabase_realtime publication.
--
-- Discovered during the realtime invalidation audit: the supabase_realtime
-- publication had ZERO tables, despite the wall already being coded against
-- postgres_changes. Wall realtime has been silently broken since launch —
-- only the 30s refetchInterval poll kept messages fresh. Every other shared
-- multi-user surface (transport, gear, participations) had no fallback at
-- all and was the root cause of "I have to restart the app to see changes".
--
-- Tables added here are the four that drive live coordination on an active
-- activity. notifications, private_messages, activities, peer_validations,
-- reputation_votes are deferred — they're either single-user or change
-- slowly enough that remount + polling is sufficient.
--
-- Replica identity is left at DEFAULT — we don't parse change payloads on
-- the client, we just call queryClient.invalidateQueries on any event, so
-- DEFAULT (primary key only) is enough.

ALTER PUBLICATION supabase_realtime ADD TABLE wall_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE participations;
ALTER PUBLICATION supabase_realtime ADD TABLE seat_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE activity_gear;
