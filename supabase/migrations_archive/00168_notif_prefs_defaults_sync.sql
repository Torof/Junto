-- Migration 00168: sync notification_preferences DEFAULT with the current
-- live notification spine. The DEFAULT JSONB in mig 00119 still listed
-- presence_reminder + presence_last_call (deleted in mig 00148/00159) and
-- was missing all types added since (presence_pre_warning_10min,
-- presence_validate_warning, presence_validate_overdue, presence_confirmed,
-- badge_unlocked, seat_request_expired).
--
-- New users: column DEFAULT now matches the actual emitted set.
-- Existing users: backfill new keys as TRUE so they show in the settings
-- toggle UI; existing user choices are preserved via the
-- (full_defaults || existing) merge pattern.
--
-- Note: presence_validate_now is intentionally NOT in the new set —
-- mig 00165 dropped the caller, mig 00166 dropped the function. Existing
-- users who had it set retain the (now-meaningless) entry; new users
-- never see it.

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
    "presence_pre_warning_10min": true,
    "presence_validate_warning": true,
    "presence_validate_overdue": true,
    "presence_confirmed": true,
    "badge_unlocked": true,
    "qr_create_reminder": true,
    "peer_review_closing": true,
    "seat_request": true,
    "seat_request_accepted": true,
    "seat_request_declined": true,
    "seat_request_expired": true,
    "driver_left": true,
    "contact_request": true,
    "contact_request_accepted": true,
    "alert_match": true
  }'::jsonb;

-- Backfill: add missing keys as TRUE for every existing user, preserving
-- existing user choices via the (full_defaults || existing) merge.
-- Trigger whitelist allows notification_preferences updates so no
-- bypass_lock needed for that column specifically — but we set it
-- defensively for any incidental column changes.
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
    "presence_pre_warning_10min": true,
    "presence_validate_warning": true,
    "presence_validate_overdue": true,
    "presence_confirmed": true,
    "badge_unlocked": true,
    "qr_create_reminder": true,
    "peer_review_closing": true,
    "seat_request": true,
    "seat_request_accepted": true,
    "seat_request_declined": true,
    "seat_request_expired": true,
    "driver_left": true,
    "contact_request": true,
    "contact_request_accepted": true,
    "alert_match": true
  }'::jsonb;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET notification_preferences = v_full_defaults || COALESCE(notification_preferences, '{}'::jsonb)
  WHERE notification_preferences IS NULL
     OR NOT (notification_preferences ?& ARRAY[
       'presence_pre_warning_10min',
       'presence_validate_warning',
       'presence_validate_overdue',
       'presence_confirmed',
       'badge_unlocked',
       'seat_request_expired'
     ]);
END $$;
