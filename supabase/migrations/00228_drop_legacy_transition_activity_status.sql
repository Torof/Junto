-- Migration 00228: drop legacy transition_activity_status().
--
-- Last redefined in 00035 — superseded by:
--   - transition_statuses_only() (cron-scheduled in 00114, every minute)
--   - transition_single_activity(p_activity_id) (lazy, called from
--     activity-detail screen)
--
-- The function has no client callers (only a stale entry in
-- src/types/supabase.ts which the next type-regen will drop), no
-- internal SECURITY DEFINER callers, and is no longer attached to
-- any cron job (00114 replaced its schedule). The legacy
-- REVOKE EXECUTE chain (00018) ensured it was uncallable since
-- before the supersession anyway.
--
-- Removes the last function still on `public, extensions` for
-- non-PostGIS reasons (now down to 6 legitimate PostGIS callers).

DROP FUNCTION IF EXISTS public.transition_activity_status();
