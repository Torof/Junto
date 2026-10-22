-- 00533 — pickup addresses do not outlive the seat request (audit 2026-10-23, L-2).
--
-- A driver kept passengers' home pickup addresses forever: a declined,
-- cancelled (including by a block) or expired request still carried
-- pickup_from / message / requested_pickup_at, readable by the driver — and the
-- read policy only honoured blocks made by the viewer, so someone you blocked
-- kept your address.
-- * the details are erased as soon as a request ends;
-- * accepted requests lose them when the outing is over;
-- * the read policy honours a block in either direction;
-- * existing rows are cleaned.

CREATE OR REPLACE FUNCTION private.seat_request_purge_details()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.status IN ('declined', 'cancelled', 'expired') AND OLD.status IS DISTINCT FROM NEW.status THEN
    NEW.pickup_from := NULL;
    NEW.message := NULL;
    NEW.requested_pickup_at := NULL;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.seat_request_purge_details() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_seat_requests_purge_details ON public.seat_requests;
CREATE TRIGGER trg_seat_requests_purge_details
  BEFORE UPDATE OF status ON public.seat_requests
  FOR EACH ROW EXECUTE FUNCTION private.seat_request_purge_details();

CREATE OR REPLACE FUNCTION public.on_activity_finished_expire_seat_requests()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- shows them as pending. No notification emission (00157 decision);
  -- the activity-status transition reaches the user through other
  -- channels.
  FOR v_request IN
    SELECT id
    FROM seat_requests
    WHERE activity_id = NEW.id AND status = 'pending'
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'expired' WHERE id = v_request.id;
  END LOOP;

  -- 00533: once the outing is over, nobody needs the pickup addresses any more.
  UPDATE seat_requests SET pickup_from = NULL, message = NULL, requested_pickup_at = NULL
  WHERE activity_id = NEW.id AND status = 'accepted'
    AND (pickup_from IS NOT NULL OR message IS NOT NULL OR requested_pickup_at IS NOT NULL);

  -- Same treatment for participation requests (mig 00263 — they were
  -- the forgotten sibling and ghosted the "En attente" tab forever).
  UPDATE participations
  SET status = 'expired'
  WHERE activity_id = NEW.id AND status = 'pending';

  RETURN NEW;
END;
$function$;

DROP POLICY IF EXISTS "Users see their own seat requests" ON public.seat_requests;
CREATE POLICY "Users see their own seat requests" ON public.seat_requests
  FOR SELECT TO authenticated
  USING ((requester_id = auth.uid() OR driver_id = auth.uid())
         AND NOT EXISTS (SELECT 1 FROM blocked_users b
                         WHERE (b.blocker_id = seat_requests.requester_id AND b.blocked_id = seat_requests.driver_id)
                            OR (b.blocker_id = seat_requests.driver_id AND b.blocked_id = seat_requests.requester_id)));

-- Existing rows.
UPDATE public.seat_requests SET pickup_from = NULL, message = NULL, requested_pickup_at = NULL
WHERE status IN ('declined', 'cancelled', 'expired')
  AND (pickup_from IS NOT NULL OR message IS NOT NULL OR requested_pickup_at IS NOT NULL);
UPDATE public.seat_requests sr SET pickup_from = NULL, message = NULL, requested_pickup_at = NULL
FROM public.activities a
WHERE a.id = sr.activity_id AND sr.status = 'accepted' AND a.status IN ('completed', 'cancelled', 'expired')
  AND (sr.pickup_from IS NOT NULL OR sr.message IS NOT NULL OR sr.requested_pickup_at IS NOT NULL);
