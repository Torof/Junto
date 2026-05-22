-- Migration 00247: no-op.
--
-- Originally exposed is_recurring + recurrence_days on the four
-- activity views. Reverted by 00248 along with the rest of the
-- recurring-activity abstraction (see 00246's no-op note for the
-- product reasoning).
--
-- This migration was never applied to the remote DB. Reduced to a
-- no-op for the same reason as 00246. Original content preserved in
-- git history at commit fbded19.

SELECT 1 WHERE FALSE;
