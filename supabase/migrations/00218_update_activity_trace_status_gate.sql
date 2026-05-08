-- Migration 00218: update_activity_trace requires the activity to be
-- still active. Closes group G from the parallel security audit.
--
-- Before: the existence check only required `creator_id = v_user_id
-- AND deleted_at IS NULL`. A creator could rewrite the recorded
-- trace_geojson on a `cancelled`, `completed`, or `expired`
-- activity — retroactively altering history that other participants
-- and reliability scoring may have read.
--
-- Fix: extend the existence check with `status IN ('published',
-- 'in_progress')`. Mirrors the standard auth-chain pattern used by
-- every other write RPC (set_activity_gear, set_participation_transport,
-- request_seat, etc.).
--
-- Body otherwise identical to 00096.

CREATE OR REPLACE FUNCTION update_activity_trace(
  p_activity_id UUID,
  p_trace_geojson JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND creator_id = v_user_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson, updated_at = now()
  WHERE id = p_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_activity_trace FROM anon;
GRANT EXECUTE ON FUNCTION update_activity_trace TO authenticated;
