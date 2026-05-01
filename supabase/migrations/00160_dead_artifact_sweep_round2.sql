-- Migration 00160: dead-artifact sweep, round 2.
--
-- Round 1 (mig 00159) caught the badge alignment + obvious orphans the
-- notification audit surfaced. Round 2 is the leftovers a second pass
-- found:
--
--  A. Stale confirm_presence notification rows. transition_single_activity
--     last emitted this type in mig 00104; the mig 00136 rewrite dropped
--     the emission. Old rows still in the table render with the default
--     Bell icon and a body the user no longer needs to act on.
--
--  B. Orphan functions with zero callers (client, edge functions, other
--     DB functions). Each was checked individually:
--       - confirm_presence(UUID, UUID[]): creator-flip presence API from
--         mig 00033, replaced by the peer-validation system (mig 00140+).
--       - mark_notification_read / mark_all_notifications_read: client
--         uses direct UPDATE on notifications (RLS allows it). RPCs are
--         redundant.
--       - cancel_contact_request: never wired.
--       - create_or_get_conversation: mig 00083 neutered it (returns
--         existing only, can't create), and the lookup itself has no
--         caller — conversations come from send_/accept_contact_request.
--       - edit_wall_message: no wall-edit UI exists.
--
--  Note: revoke_push_token is also orphan but kept — wiring it into
--  the push-perm-denied + sign-out paths is a follow-up (behavioural
--  change, not artifact cleanup).

-- ============================================================================
-- A. Stale notification rows
-- ============================================================================

DELETE FROM notifications
WHERE type = 'confirm_presence';

-- ============================================================================
-- B. Orphan functions
-- ============================================================================

DROP FUNCTION IF EXISTS confirm_presence(UUID, UUID[]);
DROP FUNCTION IF EXISTS mark_notification_read(UUID);
DROP FUNCTION IF EXISTS mark_all_notifications_read();
DROP FUNCTION IF EXISTS cancel_contact_request(UUID);
DROP FUNCTION IF EXISTS create_or_get_conversation(UUID);
DROP FUNCTION IF EXISTS edit_wall_message(UUID, TEXT, BOOLEAN);
