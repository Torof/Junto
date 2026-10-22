-- Migration 00182: trigger-based realtime broadcasts for participations + seat_requests.
--
-- Why this exists: postgres_changes on these two tables doesn't propagate
-- correctly because their SELECT RLS policies are restrictive.
-- - participations: "auth.uid() = user_id" — only the row owner can see it,
--   so a new participant's INSERT never reaches the rest of the activity.
-- - seat_requests: works for the requester+driver pair (policy 1) but the
--   second policy uses an EXISTS subquery on participations.activity_id
--   that won't always evaluate during UPDATE events with REPLICA IDENTITY
--   DEFAULT.
--
-- Relaxing those RLS policies would expose creator-only columns
-- (left_reason, penalty_waived) to all activity members. So instead, we
-- use Supabase Realtime's broadcast channel: triggers call realtime.send()
-- with a no-payload "stale" ping addressed to topic activity:<id>.
-- Subscribers receive { table, op } and invalidate their query caches.
-- No row data is broadcast, no RLS is bypassed for actual data reads —
-- the client still goes through SECURITY DEFINER RPCs / RLS-protected
-- views to fetch fresh data.
--
-- activity_gear stays on postgres_changes (its RLS already allows
-- accepted activity members to see all rows for the activity).
-- wall_messages also stays on postgres_changes (handled by activity-wall.tsx).

CREATE OR REPLACE FUNCTION broadcast_activity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  -- COALESCE handles INSERT (NEW only) / UPDATE (both) / DELETE (OLD only).
  v_activity_id := COALESCE(
    (CASE WHEN TG_OP <> 'DELETE' THEN NEW.activity_id END),
    (CASE WHEN TG_OP <> 'INSERT' THEN OLD.activity_id END)
  );
  IF v_activity_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM realtime.send(
    jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP),
    'change',
    'activity:' || v_activity_id::text,
    false  -- public channel, payload carries no row data
  );

  RETURN NULL; -- AFTER trigger, return value ignored
END;
$$;

REVOKE EXECUTE ON FUNCTION broadcast_activity_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION broadcast_activity_change() FROM authenticated;
REVOKE EXECUTE ON FUNCTION broadcast_activity_change() FROM anon;
-- Trigger-only function, callers shouldn't invoke it directly.

DROP TRIGGER IF EXISTS trg_participations_broadcast ON participations;
CREATE TRIGGER trg_participations_broadcast
AFTER INSERT OR UPDATE OR DELETE ON participations
FOR EACH ROW EXECUTE FUNCTION broadcast_activity_change();

DROP TRIGGER IF EXISTS trg_seat_requests_broadcast ON seat_requests;
CREATE TRIGGER trg_seat_requests_broadcast
AFTER INSERT OR UPDATE OR DELETE ON seat_requests
FOR EACH ROW EXECUTE FUNCTION broadcast_activity_change();
