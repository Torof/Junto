-- Migration 00137: backfill missed 'rate_participants' notifs.
-- Activities that completed via the cron sweep before migration 00136 never
-- got their per-participant notif. For any activity whose peer-review
-- window is still open (completed less than 24 hours ago), emit the notif
-- to every accepted participant who doesn't already have one.

DO $$
DECLARE
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  FOR v_activity IN
    SELECT id, title, starts_at, duration
    FROM activities
    WHERE status = 'completed'
      AND deleted_at IS NULL
      AND starts_at + duration + INTERVAL '24 hours' > now()
  LOOP
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = v_activity.id AND status = 'accepted'
    LOOP
      -- Skip if a rate_participants row already exists for this user+activity
      IF EXISTS (
        SELECT 1 FROM notifications
        WHERE user_id = v_participant.user_id
          AND type = 'rate_participants'
          AND (data->>'activity_id')::uuid = v_activity.id
      ) THEN CONTINUE; END IF;

      PERFORM create_notification(
        v_participant.user_id,
        'rate_participants',
        'Évalue tes co-participants',
        'Comment s''est passé ' || v_activity.title || ' ?',
        jsonb_build_object('activity_id', v_activity.id)
      );
    END LOOP;
  END LOOP;
END $$;
