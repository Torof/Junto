-- ============================================================================
-- 00517 — Affinage de 00516 : l'exemption d'annulation tardive ne vaut que
-- pour une DEMANDE acceptée par l'organisateur à moins de 12 h du départ
-- (le piège). Rejoindre soi-même au dernier moment puis partir reste une
-- annulation tardive. Colonne participations.accepted_via (self / organiser /
-- invitation), tenue par le déclencheur.
-- ============================================================================

ALTER TABLE participations ADD COLUMN IF NOT EXISTS accepted_via TEXT
  CHECK (accepted_via IS NULL OR accepted_via IN ('self', 'organiser', 'invitation'));

CREATE OR REPLACE FUNCTION private.stamp_accepted_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'accepted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'accepted') THEN
    NEW.accepted_at := now();
    NEW.accepted_via := CASE
      WHEN TG_OP = 'UPDATE' AND OLD.status = 'pending' THEN 'organiser'
      WHEN TG_OP = 'UPDATE' AND OLD.status = 'invited' THEN 'invitation'
      ELSE 'self' END;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.accepted_at := CASE WHEN NEW.status = 'accepted' THEN OLD.accepted_at END;
    NEW.accepted_via := CASE WHEN NEW.status = 'accepted' THEN OLD.accepted_via END;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.leave_activity(p_activity_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
  v_reason TEXT;
  v_was_driver BOOLEAN;
  v_passenger RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

  SELECT p.id, p.status, p.transport_type, p.transport_seats, p.accepted_at, p.accepted_via
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  -- Block creator from leaving their own activity (would orphan the activity)
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00477 (PR-5): only leaving an ACCEPTED place late is a late cancel;
  -- withdrawing a request nobody answered is not.
  v_is_late := v_participation.status = 'accepted'
               AND v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now())
               -- 00517: a REQUEST the organiser accepted inside the 12-hour line
               -- is not a late cancel when left (the trap) — a place one took
               -- oneself, at any time, still is.
               AND NOT (v_participation.accepted_via = 'organiser'
                        AND v_participation.accepted_at >= v_activity.starts_at - INTERVAL '12 hours')
               -- 00516: nobody is penalised for leaving a suspended organiser's outing.
               AND NOT private.user_is_suspended(v_activity.creator_id);

  v_was_driver := v_participation.transport_type IN ('car', 'carpool');

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL
  WHERE id = v_participation.id;

  -- 00478 (PR-4): the late cancel goes to its own ledger, which no rejoin,
  -- re-invitation, declined invitation or block cascade can erase. A new late
  -- cancel on the same outing re-arms a previous waiver.
  IF v_is_late THEN
    INSERT INTO late_cancels (user_id, activity_id, at, waived)
    VALUES (v_user_id, p_activity_id, now(), false)
    ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now(), waived = false;
  END IF;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  -- 00477/00478 (AB-1): at most one notification of EACH type per participant
  -- and outing per 24 h — an early leave never hides a later late one.
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END
      AND data->>'participation_id' = v_participation.id::text
      AND created_at > now() - INTERVAL '24 hours'
  ) THEN
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté « ' || v_activity.title || ' »',
    CASE
      WHEN v_is_late THEN 'Départ tardif — pénalité de fiabilité appliquée, tu peux la lever depuis la sortie.'
      ELSE coalesce(v_reason, '')
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late,
      'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title, 'reason', coalesce(v_reason, '')))
  );
  END IF;

  -- If the leaver was offering rides, cancel their pending/accepted seat_requests
  -- and notify each affected requester so they can find another ride.
  IF v_was_driver THEN
    FOR v_passenger IN
      SELECT id, requester_id FROM seat_requests
      WHERE activity_id = p_activity_id AND driver_id = v_user_id
        AND status IN ('pending', 'accepted')
    LOOP
      UPDATE seat_requests SET status = 'cancelled' WHERE id = v_passenger.id;
      PERFORM create_notification(
        v_passenger.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_user_name, 'Le conducteur') || ' a quitté « ' || v_activity.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', p_activity_id, 'driver_id', v_user_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Le conducteur'), 'title', v_activity.title))
      );
    END LOOP;
  END IF;
END;
$function$;
