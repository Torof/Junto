-- Migration 00119: notification preferences defaults catch up with the
-- types we added in 00117 (presence_*, qr_create_reminder, alert_match,
-- peer_review_closing, seat_*, contact_*, driver_left, rate_participants).
--
-- Two changes:
--  (1) New users: JSONB default reflects locked decision J (default-OFF
--      for participant_joined, participant_left, activity_updated) and
--      includes every type we currently emit so the settings UI renders
--      a toggle for each.
--  (2) Existing users: backfill missing keys as TRUE so they get the new
--      toggles without retroactively flipping their existing preferences.
--      The 3 default-off types stay TRUE for users who already had them
--      set — we don't surprise existing users by silencing things.

ALTER TABLE users
  ALTER COLUMN notification_preferences SET DEFAULT '{
    "join_request": true,
    "participant_joined": false,
    "request_accepted": true,
    "request_refused": true,
    "participant_removed": true,
    "participant_left": false,
    "participant_left_late": true,
    "activity_cancelled": true,
    "activity_updated": false,
    "rate_participants": true,
    "presence_pre_warning": true,
    "presence_reminder": true,
    "presence_last_call": true,
    "qr_create_reminder": true,
    "peer_review_closing": true,
    "seat_request": true,
    "seat_request_accepted": true,
    "seat_request_declined": true,
    "driver_left": true,
    "contact_request": true,
    "contact_request_accepted": true,
    "alert_match": true
  }'::jsonb;

-- Backfill: add missing keys as TRUE for every existing user, preserving
-- whatever they already chose. The COALESCE guards against NULL.
DO $$
DECLARE
  v_full_defaults JSONB := '{
    "join_request": true,
    "participant_joined": true,
    "request_accepted": true,
    "request_refused": true,
    "participant_removed": true,
    "participant_left": true,
    "participant_left_late": true,
    "activity_cancelled": true,
    "activity_updated": true,
    "rate_participants": true,
    "presence_pre_warning": true,
    "presence_reminder": true,
    "presence_last_call": true,
    "qr_create_reminder": true,
    "peer_review_closing": true,
    "seat_request": true,
    "seat_request_accepted": true,
    "seat_request_declined": true,
    "driver_left": true,
    "contact_request": true,
    "contact_request_accepted": true,
    "alert_match": true
  }'::jsonb;
BEGIN
  -- Bypass the whitelist trigger: notification_preferences is allowed but
  -- updated_at would still bump. We only want to merge missing keys, not
  -- overwrite user choices, so use the v_full_defaults || existing pattern
  -- which keeps existing keys' values and only fills in gaps.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET notification_preferences = v_full_defaults || COALESCE(notification_preferences, '{}'::jsonb)
  WHERE notification_preferences IS NULL
     OR NOT (notification_preferences ?& ARRAY[
       'rate_participants','presence_pre_warning','presence_reminder',
       'presence_last_call','qr_create_reminder','peer_review_closing',
       'seat_request','seat_request_accepted','seat_request_declined',
       'driver_left','contact_request','contact_request_accepted',
       'alert_match','participant_left_late'
     ]);
END $$;
