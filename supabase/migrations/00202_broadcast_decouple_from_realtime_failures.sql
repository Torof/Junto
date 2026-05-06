-- Migration 00202: don't abort user writes when the realtime broker hiccups.
--
-- Audit pass 2 / M-3: broadcast_activity_change (00182 → 00183) calls
-- `PERFORM realtime.send(...)` inside an AFTER trigger without
-- exception handling. If realtime.send raises (broker connectivity
-- blip, schema lock during a Supabase platform window, etc.), the
-- trigger raises, the calling RPC fails, and the user's write —
-- gear update, seat acceptance, leave_activity, transport change —
-- aborts.
--
-- Realtime is a side-channel for UI liveness. Subscribers fall back
-- to TanStack stale-time refetches and to the periodic refetchInterval
-- on individual queries. A momentary broker outage shouldn't gate
-- the user's underlying action.
--
-- Fix: wrap realtime.send in a BEGIN/EXCEPTION/END block. On any
-- failure, swallow silently and let the trigger return normally.
-- Cost: rare missed pings. Gain: writes don't fail because of
-- realtime infrastructure availability.
--
-- Body otherwise identical to 00183.

CREATE OR REPLACE FUNCTION broadcast_activity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  v_activity_id := COALESCE(
    (CASE WHEN TG_OP <> 'DELETE' THEN NEW.activity_id END),
    (CASE WHEN TG_OP <> 'INSERT' THEN OLD.activity_id END)
  );
  IF v_activity_id IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP),
      'change',
      'activity:' || v_activity_id::text,
      true
    );
  EXCEPTION WHEN OTHERS THEN
    -- Realtime broker hiccup: better to lose the ping than to fail
    -- the user's write. Subscribers refetch on stale times anyway.
    NULL;
  END;

  RETURN NULL;
END;
$$;
