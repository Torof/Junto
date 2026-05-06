-- Migration 00205: auto-expire pending seat requests after 48h idle.
--
-- Audit follow-up: pending seat requests previously sat at 'pending'
-- until the activity itself transitioned to a terminal state — which
-- could be weeks. Drivers forget; requesters block on a phantom
-- "En attente" with no signal that the request is rotting. UX win to
-- expire pending after 48h of no driver action.
--
-- Notification: send to the requester only ("Demande non répondue").
-- Driver side stays silent — they got the original notif and a
-- "you missed a request" reminder reads as scolding for a forgivable
-- inattention. The expired-on-activity-end flow (00157) still skips
-- notifications because the user already learns the activity ended
-- through other channels.
--
-- Hooked into check_activity_transitions (00142) which runs on app
-- foreground via a client RPC call, so this fires opportunistically
-- without needing a dedicated cron schedule. Advisory lock on the
-- outer function already prevents concurrent execution.

CREATE OR REPLACE FUNCTION expire_idle_seat_requests()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_activity_title TEXT;
BEGIN
  FOR v_request IN
    SELECT sr.id, sr.requester_id, sr.activity_id
    FROM seat_requests sr
    JOIN activities a ON a.id = sr.activity_id
    WHERE sr.status = 'pending'
      AND sr.created_at < NOW() - INTERVAL '48 hours'
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
    FOR UPDATE OF sr
  LOOP
    UPDATE seat_requests SET status = 'expired'
    WHERE id = v_request.id AND status = 'pending';

    SELECT title INTO v_activity_title FROM activities WHERE id = v_request.activity_id;

    PERFORM create_notification(
      v_request.requester_id,
      'seat_request_expired',
      'Demande non répondue',
      'Ta demande de covoiturage pour « ' || coalesce(v_activity_title, '?') || ' » a expiré sans réponse du conducteur.',
      jsonb_build_object('activity_id', v_request.activity_id, 'seat_request_id', v_request.id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION expire_idle_seat_requests FROM anon, authenticated;

-- Hook into the existing transitions sweep so we don't need a
-- separate schedule. expire_stale_contact_requests is the precedent.

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
  PERFORM expire_idle_seat_requests();
END;
$$;

REVOKE EXECUTE ON FUNCTION check_activity_transitions FROM anon;
GRANT EXECUTE ON FUNCTION check_activity_transitions TO authenticated;
