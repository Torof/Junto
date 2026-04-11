-- Migration 00016: automatic activity status transitions
-- Runs periodically to update: published → in_progress → completed, published → expired

CREATE OR REPLACE FUNCTION transition_activity_status()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Bypass activity update trigger
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- published → in_progress (starts_at reached)
  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published'
    AND starts_at <= now();

  -- in_progress → completed (starts_at + duration reached)
  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress'
    AND starts_at + duration <= now();

  -- published → expired (starts_at + 2h passed, no participants besides creator)
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;
END;
$$;

-- Internal function: not callable by clients
REVOKE EXECUTE ON FUNCTION transition_activity_status() FROM anon, authenticated;

-- Schedule with pg_cron: run every 10 minutes
-- Note: pg_cron may not be available on all Supabase plans
-- If not available, this can be called via a Supabase Edge Function on a cron schedule
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'transition-activity-status',
      '*/10 * * * *',
      'SELECT transition_activity_status()'
    );
  END IF;
END $$;
