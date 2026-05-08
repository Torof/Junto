-- Migration 00213: REPLICA IDENTITY FULL on the 4 publication tables that
-- were missing it. Closes group B from the parallel security audit.
--
-- Background: tables in the supabase_realtime publication need every
-- column that any RLS policy references to be present in the WAL
-- payload for UPDATE/DELETE events. With REPLICA IDENTITY DEFAULT,
-- only the primary key is in the OLD payload — so any policy that
-- gates on user_id, conversation_id, deleted_at, status, etc. fails
-- to evaluate during realtime delivery and the broadcast is silently
-- dropped.
--
-- The same trap was caught and fixed for activity_gear in 00188. The
-- audit found 4 more tables in the same situation:
--   - wall_messages         (postgres_changes sub in activity-wall.tsx)
--   - notifications         (read_at flips never reach the badge)
--   - private_messages      (sub in conversation/[id].tsx + messagerie)
--   - activities            (sub in use-nearby-activities.ts)
--
-- participations + seat_requests stay at REPLICA IDENTITY DEFAULT
-- intentionally — they use trigger-based broadcast on the
-- activity:<id> topic (00182/00183), which doesn't depend on WAL
-- payload completeness.
--
-- Cost: REPLICA IDENTITY FULL roughly 2x's WAL volume for these
-- tables on UPDATE/DELETE. Acceptable for low-volume coordination
-- tables; revisit if write throughput becomes a concern.

ALTER TABLE wall_messages REPLICA IDENTITY FULL;
ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE private_messages REPLICA IDENTITY FULL;
ALTER TABLE activities REPLICA IDENTITY FULL;
