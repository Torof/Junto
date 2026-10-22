-- Migration 00246: no-op.
--
-- Originally added is_recurring + recurrence_days params to
-- create_activity. The recurring-activity abstraction was reverted
-- shortly after (see 00248) because outdoor pros operate on demand
-- and indoor pros run scheduled classes — both belong in a catalog
-- (pro_offerings, migrations 00249+), not as scheduled activities.
--
-- This migration was never applied to the remote DB. Reduced to a
-- no-op so the migration sequence stays linear and fresh databases
-- skip work that 00248 would immediately undo. Original content
-- preserved in git history at commit 75adb68.

SELECT 1 WHERE FALSE;
