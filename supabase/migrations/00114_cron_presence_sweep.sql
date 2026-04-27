-- Migration 00114: schedule periodic presence sweep so notifications fire
-- regardless of user activity. The previous design depended on someone
-- opening the activity detail (lazy) or focusing the carte tab (global
-- sweeper) for transition_statuses_only to run — meaning a user who never
-- opens the app misses every reminder.
--
-- pg_cron runs every minute against transition_statuses_only(), which
-- itself self-locks via pg_try_advisory_xact_lock so duplicate ticks are
-- harmless.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Allow the postgres role (cron worker) to call our internal function
GRANT EXECUTE ON FUNCTION transition_statuses_only() TO postgres;

-- Replace any prior schedule with the same name
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'junto-presence-sweep') THEN
    PERFORM cron.unschedule('junto-presence-sweep');
  END IF;
END $$;

SELECT cron.schedule(
  'junto-presence-sweep',
  '* * * * *',  -- every minute
  $$SELECT public.transition_statuses_only();$$
);
