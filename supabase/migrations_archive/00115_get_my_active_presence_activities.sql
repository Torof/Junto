-- Migration 00115: helper RPC for the foreground geo watcher.
-- Returns activities the caller has joined (status accepted), that require
-- presence, are still pending validation, and whose start is inside the
-- geo window (T-10min → T+30min). The client polls this every 30s and
-- compares against the device location to fire a local "you're here" notif.

CREATE OR REPLACE FUNCTION get_my_active_presence_activities()
RETURNS TABLE (
  activity_id UUID,
  title TEXT,
  starts_at TIMESTAMPTZ,
  duration INTERVAL,
  start_lng FLOAT,
  start_lat FLOAT,
  meeting_lng FLOAT,
  meeting_lat FLOAT,
  end_lng FLOAT,
  end_lat FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    a.id AS activity_id,
    a.title,
    a.starts_at,
    a.duration,
    ST_X(a.location_start::geometry)::float AS start_lng,
    ST_Y(a.location_start::geometry)::float AS start_lat,
    ST_X(a.location_meeting::geometry)::float AS meeting_lng,
    ST_Y(a.location_meeting::geometry)::float AS meeting_lat,
    ST_X(a.location_end::geometry)::float AS end_lng,
    ST_Y(a.location_end::geometry)::float AS end_lat
  FROM activities a
  JOIN participations p ON p.activity_id = a.id
  WHERE p.user_id = v_user_id
    AND p.status = 'accepted'
    AND p.confirmed_present IS NULL
    AND a.requires_presence = TRUE
    AND a.deleted_at IS NULL
    AND a.status IN ('published', 'in_progress')
    AND now() >= a.starts_at - INTERVAL '10 minutes'
    AND now() <= a.starts_at + INTERVAL '30 minutes';
END;
$$;

REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities FROM anon;
GRANT EXECUTE ON FUNCTION get_my_active_presence_activities TO authenticated;
