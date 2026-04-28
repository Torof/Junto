-- Migration 00142: auto-expire stale seat requests and contact requests.
--
-- Two categories of "stuck pending" requests existed in the messagerie
-- requests tab, with no mechanism to clear them out:
--
--   1. Seat requests for activities that already finished. The mutation
--      functions (accept/decline) reject when the activity isn't in
--      {published, in_progress}, but the row stayed pending forever and
--      cluttered the driver's UI.
--   2. Contact requests past their request_expires_at (NOW() + 30d at
--      creation). The conversations.status check constraint allows
--      pending_request | active | declined; nothing flipped expired
--      rows so they appeared pending indefinitely.
--
-- Fixes:
--   1. Trigger on activities status flip → flips pending seat_requests for
--      that activity to 'expired', emits seat_request_expired notif to
--      the requester (driver stays silent — they were the one who didn't
--      act).
--   2. Helper function expire_stale_contact_requests() that flips
--      pending_request → declined when request_expires_at < NOW().
--      Hooked into check_activity_transitions so it runs on app foreground
--      without needing pg_cron. No notifications either side.
--   3. Backfills both categories so the user's existing stuck rows clear
--      immediately.

-- ============================================================================
-- 1. Trigger: expire seat_requests when activity is no longer active
-- ============================================================================
CREATE OR REPLACE FUNCTION on_activity_finished_expire_seat_requests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_activity_title TEXT;
BEGIN
  -- Only fire when status flips OUT of an active state.
  IF NEW.status NOT IN ('completed', 'cancelled', 'expired') THEN
    RETURN NEW;
  END IF;
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT title INTO v_activity_title FROM activities WHERE id = NEW.id;

  FOR v_request IN
    SELECT id, requester_id
    FROM seat_requests
    WHERE activity_id = NEW.id AND status = 'pending'
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'expired' WHERE id = v_request.id;

    PERFORM create_notification(
      v_request.requester_id,
      'seat_request_expired',
      'Demande expirée',
      'Ta demande de covoiturage pour « ' || coalesce(v_activity_title, '?') || ' » a expiré sans réponse.',
      jsonb_build_object('activity_id', NEW.id, 'seat_request_id', v_request.id)
    );
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION on_activity_finished_expire_seat_requests FROM anon, authenticated;

DROP TRIGGER IF EXISTS trg_activity_finished_expire_seat_requests ON activities;
CREATE TRIGGER trg_activity_finished_expire_seat_requests
AFTER UPDATE OF status ON activities
FOR EACH ROW
EXECUTE FUNCTION on_activity_finished_expire_seat_requests();

-- Allow seat_requests.status = 'expired' if the existing CHECK rejects it.
-- The original constraint (mig 00074 / 00080 era) typically allows
-- pending|accepted|declined|cancelled. Add 'expired' if missing.
DO $$
BEGIN
  ALTER TABLE seat_requests DROP CONSTRAINT IF EXISTS seat_requests_status_check;
  ALTER TABLE seat_requests ADD CONSTRAINT seat_requests_status_check
    CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'expired'));
END $$;

-- ============================================================================
-- 2. Helper: expire stale contact requests (silent)
-- ============================================================================
CREATE OR REPLACE FUNCTION expire_stale_contact_requests()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE conversations
  SET status = 'declined', request_expires_at = NULL
  WHERE status = 'pending_request'
    AND request_expires_at IS NOT NULL
    AND request_expires_at < NOW();
END;
$$;

REVOKE EXECUTE ON FUNCTION expire_stale_contact_requests FROM anon, authenticated;

-- ============================================================================
-- 3. Hook into check_activity_transitions so it runs on app foreground
-- ============================================================================
CREATE OR REPLACE FUNCTION check_activity_transitions()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('activity_transitions')) THEN
    RETURN;
  END IF;

  PERFORM transition_statuses_only();
  PERFORM expire_stale_contact_requests();
END;
$$;

REVOKE EXECUTE ON FUNCTION check_activity_transitions FROM anon;
GRANT EXECUTE ON FUNCTION check_activity_transitions TO authenticated;

-- ============================================================================
-- 4. Backfill: clear currently-stuck rows
-- ============================================================================

-- Seat requests whose activity is already finished
DO $$
DECLARE
  v_request RECORD;
  v_activity_title TEXT;
BEGIN
  FOR v_request IN
    SELECT sr.id, sr.requester_id, sr.activity_id
    FROM seat_requests sr
    JOIN activities a ON a.id = sr.activity_id
    WHERE sr.status = 'pending'
      AND a.status IN ('completed', 'cancelled', 'expired')
  LOOP
    UPDATE seat_requests SET status = 'expired' WHERE id = v_request.id;

    SELECT title INTO v_activity_title FROM activities WHERE id = v_request.activity_id;
    PERFORM create_notification(
      v_request.requester_id,
      'seat_request_expired',
      'Demande expirée',
      'Ta demande de covoiturage pour « ' || coalesce(v_activity_title, '?') || ' » a expiré sans réponse.',
      jsonb_build_object('activity_id', v_request.activity_id, 'seat_request_id', v_request.id)
    );
  END LOOP;
END $$;

-- Contact requests past their expiry
SELECT expire_stale_contact_requests();

-- seat_request_expired falls through the default branch in
-- push_notification_to_device and therefore pushes — the requester is
-- typically not in the app when their request times out, which is the
-- whole point of pushing.
