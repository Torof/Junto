-- Migration 00157: stop emitting seat_request_expired when an activity ends.
--
-- The trigger from mig 00142 fired a notification (and via the default push
-- routing, a push) whenever an activity's status flipped to one of
-- {completed, cancelled, expired} and the user had a pending seat request
-- on it. In practice the user always learns about the activity's end via
-- other channels:
--
--   - cancelled  → activity_cancelled push (gated to <48h, but still louder
--                  than the seat-request-expired post-hoc notice)
--   - completed  → user was either there or knew they weren't going
--   - expired    → activity passed without happening; user has moved on
--
-- Sending an extra "your seat request expired" notification at that point
-- is noise — it told the user something they already knew, hours after the
-- fact. Kept the seat_request status cleanup (pending → expired) so the
-- requester's UI no longer shows the row as pending. Only the notification
-- emission is dropped.

CREATE OR REPLACE FUNCTION on_activity_finished_expire_seat_requests()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
BEGIN
  IF NEW.status NOT IN ('completed', 'cancelled', 'expired') THEN
    RETURN NEW;
  END IF;
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Cleanup only — flip pending requests to expired so the UI no longer
  -- shows them as pending. No notification emission; the activity-status
  -- transition is communicated to the user through other channels.
  FOR v_request IN
    SELECT id
    FROM seat_requests
    WHERE activity_id = NEW.id AND status = 'pending'
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'expired' WHERE id = v_request.id;
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION on_activity_finished_expire_seat_requests FROM anon, authenticated;

-- The trigger itself stays bound to the same function name, no DROP/CREATE
-- needed. Trigger from mig 00142 already references this function.
