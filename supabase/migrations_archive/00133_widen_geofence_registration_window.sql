-- Migration 00133: get_my_active_presence_activities lower bound T-2h.
-- Background geofencing registers regions with the OS based on this RPC's
-- result. With a T-15min lower bound (same as validation), regions weren't
-- registered until 15 minutes before start — too late for users who walked
-- to the spot before opening the app at T-15min sharp.
--
-- Widening to T-2h matches the pre-warning notif timing: by the time the
-- "starts in 2h" notif fires, the app's next foreground refresh registers
-- the geofence. The user can then arrive at any point and the OS fires
-- the entry event. The TaskManager task still calls
-- confirm_presence_via_geo, which gates server-side at T-15min — so an
-- early entry just doesn't validate yet (acceptable; the user gets the
-- "you arrived" local notif anyway).
--
-- The foreground watcher (use-presence-geo-watcher) filters client-side
-- to T-15min → T+30min for action, so widening here is safe.

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
    AND now() >= a.starts_at - INTERVAL '2 hours'
    AND now() <= a.starts_at + INTERVAL '30 minutes';
END;
$$;

REVOKE EXECUTE ON FUNCTION get_my_active_presence_activities FROM anon;
GRANT EXECUTE ON FUNCTION get_my_active_presence_activities TO authenticated;
