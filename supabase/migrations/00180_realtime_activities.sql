-- Migration 00180: extend supabase_realtime publication to activities.
--
-- Slice 3 of the realtime invalidation pass. Drives the nearby map / list
-- views — when an activity is created, edited, or cancelled, every user
-- viewing the area should see the change without re-panning the map.
--
-- Note: there's no per-user filtering on the publication side. The client
-- subscribes to all activities changes and invalidates the ['activities']
-- query key, which TanStack treats as a prefix match (covers all bounds
-- variants of ['activities', 'nearby', bounds] plus any ['activities']
-- invalidations from action flows).
--
-- Pre-launch this is fine — low traffic. Post-launch we may want
-- geographic filtering, which would push routing to the server (Broadcast
-- channels with PostGIS bbox subscriptions). Out of scope here.

ALTER PUBLICATION supabase_realtime ADD TABLE activities;
