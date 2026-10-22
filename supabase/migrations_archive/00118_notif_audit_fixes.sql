-- Migration 00118: post-overhaul audit fixes for the notification system.
-- Three findings from auditing 00117:
--  (1) purge_old_notifications would delete unread actionable notifs that the
--      user hasn't responded to yet. Preserve them.
--  (2) check_alerts_for_activity 3/day cap had a race window between the
--      count and the insert — concurrent activity inserts could bypass it.
--      Wrap each per-alert decision in a per-user advisory lock.

-- ============================================================================
-- 1. purge_old_notifications — preserve unread actionable notifs from purge
-- ============================================================================
CREATE OR REPLACE FUNCTION purge_old_notifications()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM notifications
  WHERE created_at < now() - INTERVAL '7 days'
    AND (
      read_at IS NOT NULL
      OR type NOT IN (
        'join_request',
        'seat_request',
        'contact_request',
        'peer_review_closing'
      )
    );
$$;

REVOKE EXECUTE ON FUNCTION purge_old_notifications FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION purge_old_notifications TO postgres;

-- ============================================================================
-- 2. check_alerts_for_activity — advisory lock around 3/UTC-day cap
-- ============================================================================
CREATE OR REPLACE FUNCTION check_alerts_for_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
  v_alert RECORD;
  v_today_count INTEGER;
BEGIN
  SELECT a.id, a.creator_id, a.title, a.location_start, a.location_meeting,
         a.starts_at, a.level, a.status, a.deleted_at, s.key AS sport_key
  INTO v_activity
  FROM activities a JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'published' OR v_activity.deleted_at IS NOT NULL THEN
    RETURN;
  END IF;

  v_sport_key := v_activity.sport_key;
  v_activity_date := v_activity.starts_at::date;

  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.levels IS NULL OR v_activity.level = ANY(a.levels))
      AND (a.starts_on IS NULL OR v_activity_date >= a.starts_on)
      AND (a.ends_on IS NULL OR v_activity_date <= a.ends_on)
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_activity.creator_id AND b.blocked_id = a.user_id)
           OR (b.blocker_id = a.user_id AND b.blocked_id = v_activity.creator_id)
      )
      AND (
        ST_DWithin(a.location, v_activity.location_start, a.radius_km * 1000)
        OR (v_activity.location_meeting IS NOT NULL
            AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000))
      )
  LOOP
    -- Per-user advisory lock so the count+insert is atomic vs. concurrent
    -- alert checks for the same user (multiple activities published in parallel).
    PERFORM pg_advisory_xact_lock(hashtext('alert_match_' || v_alert.user_id::text));

    SELECT count(*) INTO v_today_count
    FROM notifications
    WHERE user_id = v_alert.user_id
      AND type = 'alert_match'
      AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC');

    IF v_today_count >= 3 THEN CONTINUE; END IF;

    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle activité',
      v_activity.title || ' correspond à ton alerte',
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION check_alerts_for_activity FROM anon, authenticated;
