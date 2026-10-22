-- 00523 — final pre-migration pass (functional bugs found by the last audit).
--
--  1. Carpool seats follow the people: a passenger who leaves or is removed
--     frees their seat (driver notified, new type seat_passenger_left); a
--     driver who leaves or is removed releases their passengers (driver_left).
--     Every accepted seat that ends (cancel, block, leave, removal) gives the
--     seat back through ONE trigger on seat_requests — cancel_accepted_seat no
--     longer increments by hand, leave_activity no longer loops.
--  2. (dropped before apply — sport levels: Scott 2026-10-22, decision pending)
--  3. A presence validated after the end of the outing (QR at the car park,
--     offline geo replay) awards the trip badges then.
--  4. Calendar days are Paris days (private.today_paris) in every booking,
--     availability, alert and purge rule; the pending-booking cap ignores
--     past days.
--  5. Push taps: by / pro_id / offering_id / booking_id are forwarded.
--  6. Withdrawn or expired join requests take their unread organiser
--     notification with them; join_request carries requester_id.
--  7. Scott 2026-10-22 (F2): when a block withdraws someone's pending request,
--     the organiser is told (new type join_request_blocked) — never who.
--  8. Received invitations no longer count in the invitee's hourly join cap;
--     no invitation to an outing already locked to newcomers.
--  9. A carpool message brings a hidden conversation back.
-- 10. Message edits and deletions are broadcast live.
-- 11. Scott 2026-10-22: « sortie modifiée » notifications on by default.


-- ==========================================================================
-- 0. Helpers
-- ==========================================================================

CREATE OR REPLACE FUNCTION private.today_paris()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT (now() AT TIME ZONE 'Europe/Paris')::date;
$function$;
REVOKE ALL ON FUNCTION private.today_paris() FROM PUBLIC, anon, authenticated;



-- ==========================================================================
-- 1. Carpool seats follow the people
-- ==========================================================================

-- Every accepted seat that ends gives the seat back to a driver still
-- driving on this outing (capped by the CHECK).
CREATE OR REPLACE FUNCTION private.seat_release_on_end()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'accepted' AND NEW.status IN ('cancelled', 'expired') THEN
    UPDATE participations
    SET transport_seats = LEAST(COALESCE(transport_seats, 0) + 1, 8)
    WHERE activity_id = NEW.activity_id AND user_id = NEW.driver_id
      AND status = 'accepted' AND transport_type = 'car';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.seat_release_on_end() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_seat_requests_release ON public.seat_requests;
CREATE TRIGGER trg_seat_requests_release
  AFTER UPDATE OF status ON public.seat_requests
  FOR EACH ROW EXECUTE FUNCTION private.seat_release_on_end();

-- Someone who stops being an accepted participant (leave, removal, any
-- future exit path) takes their carpool links with them.
CREATE OR REPLACE FUNCTION private.seat_cleanup_on_participation_loss()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_act RECORD;
  v_req RECORD;
  v_name TEXT;
BEGIN
  IF NOT (OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted') THEN
    RETURN NEW;
  END IF;
  SELECT id, title, status, deleted_at INTO v_act FROM activities WHERE id = NEW.activity_id;
  SELECT display_name INTO v_name FROM public_profiles WHERE id = NEW.user_id;

  -- As a passenger: pending requests withdrawn; the accepted seat freed
  -- (seat given back by trg_seat_requests_release) and its driver told.
  FOR v_req IN
    SELECT id, driver_id, status FROM seat_requests
    WHERE activity_id = NEW.activity_id AND requester_id = NEW.user_id
      AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'cancelled' WHERE id = v_req.id;
    IF v_req.status = 'accepted' AND v_act.status IN ('published', 'in_progress') AND v_act.deleted_at IS NULL THEN
      PERFORM create_notification(
        v_req.driver_id,
        'seat_passenger_left',
        'Place libérée',
        coalesce(v_name, 'Ton passager') || ' ne participe plus à « ' || v_act.title || ' » — sa place dans ta voiture est libérée',
        jsonb_build_object('activity_id', NEW.activity_id,
          'params', jsonb_build_object('name', coalesce(v_name, 'Ton passager'), 'title', v_act.title))
      );
    END IF;
  END LOOP;

  -- As a driver: every passenger (pending or seated) is released and told.
  FOR v_req IN
    SELECT id, requester_id FROM seat_requests
    WHERE activity_id = NEW.activity_id AND driver_id = NEW.user_id
      AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    UPDATE seat_requests SET status = 'cancelled' WHERE id = v_req.id;
    IF v_act.status IN ('published', 'in_progress') AND v_act.deleted_at IS NULL THEN
      PERFORM create_notification(
        v_req.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_name, 'Le conducteur') || ' a quitté « ' || v_act.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', NEW.activity_id, 'driver_id', NEW.user_id,
          'params', jsonb_build_object('name', coalesce(v_name, 'Le conducteur'), 'title', v_act.title))
      );
    END IF;
  END LOOP;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.seat_cleanup_on_participation_loss() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_participations_seat_cleanup ON public.participations;
CREATE TRIGGER trg_participations_seat_cleanup
  AFTER UPDATE OF status ON public.participations
  FOR EACH ROW EXECUTE FUNCTION private.seat_cleanup_on_participation_loss();

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


  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL,
      transport_from_lat = NULL, transport_from_lng = NULL, transport_from_locality = NULL  -- 00522 (F11)
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

  -- 00523: carpool links (as driver or passenger) are released by
  -- trg_participations_seat_cleanup on the status change above.
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_accepted_seat(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_updated_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, requester_id, driver_id, activity_id, status
  INTO v_request
  FROM seat_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.requester_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_request.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_request.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  UPDATE seat_requests SET status = 'cancelled'
  WHERE id = p_request_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00523: the seat is given back by trg_seat_requests_release.
END;
$function$;


-- ==========================================================================
-- 3. A presence validated after the end awards the badges then
-- ==========================================================================

CREATE OR REPLACE FUNCTION private.award_on_late_presence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.confirmed_present IS TRUE AND OLD.confirmed_present IS DISTINCT FROM TRUE
     AND NEW.status = 'accepted'
     AND EXISTS (SELECT 1 FROM activities a WHERE a.id = NEW.activity_id
                 AND a.status = 'completed' AND a.deleted_at IS NULL) THEN
    PERFORM award_badge_progression(NEW.user_id, false);
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.award_on_late_presence() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_participations_late_presence_award ON public.participations;
CREATE TRIGGER trg_participations_late_presence_award
  AFTER UPDATE OF confirmed_present ON public.participations
  FOR EACH ROW EXECUTE FUNCTION private.award_on_late_presence();


-- ==========================================================================
-- 4. Calendar days are Paris days
-- ==========================================================================

-- 22 occurrences of current_date (UTC day) in 17 functions → private.today_paris().

CREATE OR REPLACE FUNCTION public.accept_booking(p_booking_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_pro_name TEXT;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_updated INTEGER;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00418 : le verbe ACCEPT exige un pro encore approuvé (un pro révoqué garde
  -- cancel, perd accept) — inclut le check suspension.
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.status != 'pending' OR v_bk.client_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.pro_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
       OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'accepted' WHERE id = p_booking_id AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE v_bk.period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  IF v_bk.client_id < v_user_id THEN v_u1 := v_bk.client_id; v_u2 := v_user_id;
  ELSE v_u1 := v_user_id; v_u2 := v_bk.client_id; END IF;

  SELECT id INTO v_conversation_id FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES ('dm', v_u1, v_u2, v_user_id, 'active', 'booking', now(), now())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      -- Course avec un autre créateur de DM : récupérer la ligne fraîche.
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  END IF;

  -- 00418 H2 : la réactivation d'une ligne existante RETAGUE en logistique.
  -- Une demande sociale pending/declined ne devient JAMAIS un contact via le
  -- booking : initiated_from='booking' + purge des champs de requête. Le
  -- double consentement frais (demande client + accept pro) ne couvre que
  -- l'ouverture du fil, pas la classification sociale (invariant 00372).
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations
  SET status = 'active',
      initiated_from = CASE
        WHEN status != 'active' THEN 'booking'
        ELSE initiated_from
      END,
      request_sender_id = CASE WHEN status != 'active' THEN NULL ELSE request_sender_id END,
      request_message   = CASE WHEN status != 'active' THEN NULL ELSE request_message END,
      pending_activity_id = CASE WHEN status != 'active' THEN NULL ELSE pending_activity_id END,
      request_expires_at = NULL,
      last_message_at = now()
  WHERE id = v_conversation_id;
  -- Ré-afficher le fil chez les deux parties (un fil masqué doit resurgir
  -- avec la confirmation).
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (
    v_conversation_id, v_user_id,
    '📆 Réservation confirmée — « ' || coalesce(v_off_title, 'Sortie') || ' », le '
      || to_char(v_bk.day, 'DD/MM') || ' ' || v_period_label
      || ' (' || v_bk.party_size || ' pers.). Paiement sur place.',
    jsonb_build_object('type', 'booking_accepted', 'booking_id', v_bk.id,
                       'offering_id', v_bk.offering_id)
  );
  UPDATE conversations SET last_message_at = now() WHERE id = v_conversation_id;

  PERFORM create_notification(
    v_bk.client_id,
    'booking_accepted',
    'Réservation confirmée !',
    coalesce(v_pro_name, 'Le professionnel') || ' a confirmé « '
      || coalesce(v_off_title, 'ta sortie') || ' » le ' || to_char(v_bk.day, 'DD/MM')
      || ', ' || v_period_label || '. Paiement sur place.',
    jsonb_build_object('booking_id', v_bk.id, 'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'ta sortie'),
                                   'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
  );

  RETURN v_conversation_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_suspend_user(p_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_bk RECORD;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF p_user_id = v_admin THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- An admin cannot suspend another admin — admin status is managed at SQL level.
  IF EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET suspended_at = now() WHERE id = p_user_id AND suspended_at IS NULL;

  -- 00420 D1 : les réservations futures du suspendu s'annulent (2 sens) et les
  -- contreparties sont prévenues — copy neutre, la suspension n'est pas
  -- révélée. Miroir du bloc delete_own_account (00419 M1) : pro suspendu →
  -- tout client est prévenu ; client suspendu → le pro seulement pour du
  -- confirmé (un pending qui disparaît reste silencieux).
  FOR v_bk IN
    SELECT b.id AS b_id, b.pro_id AS b_pro, b.client_id AS b_client,
           b.status AS b_status, b.day AS b_day, po.title AS b_title
    FROM bookings b
    LEFT JOIN pro_offerings po ON po.id = b.offering_id
    WHERE (b.pro_id = p_user_id OR b.client_id = p_user_id)
      AND b.status IN ('pending', 'accepted')
      AND b.day >= private.today_paris()
    FOR UPDATE OF b
  LOOP
    UPDATE bookings
    SET status = CASE WHEN v_bk.b_pro = p_user_id THEN 'cancelled_pro' ELSE 'cancelled' END
    WHERE id = v_bk.b_id;

    IF v_bk.b_pro = p_user_id THEN
      IF v_bk.b_client IS NOT NULL THEN
        PERFORM create_notification(
          v_bk.b_client,
          'booking_cancelled',
          'Sortie annulée',
          '« ' || coalesce(v_bk.b_title, 'Ta sortie') || ' » du '
            || to_char(v_bk.b_day, 'DD/MM') || ' a été annulée.',
          jsonb_build_object('booking_id', v_bk.b_id, 'by', 'pro',
            'params', jsonb_build_object('title', coalesce(v_bk.b_title, 'Ta sortie'), 'date', to_char(v_bk.b_day, 'YYYY-MM-DD')))
        );
      END IF;
    ELSIF v_bk.b_status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.b_pro,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_bk.b_title, 'une sortie') || ' » du '
          || to_char(v_bk.b_day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.b_id, 'by', 'client', 'variant', 'client_gone',
          'params', jsonb_build_object('title', coalesce(v_bk.b_title, 'une sortie'), 'date', to_char(v_bk.b_day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM log_admin_action(v_admin, 'suspend_user', 'user', p_user_id, v_reason, NULL);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_client_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00420 D1 : un suspendu n'annule plus lui-même — ses réservations ont été
  -- auto-annulées à la suspension (admin_suspend_user).
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  -- 00443 B2 : IS DISTINCT FROM — sur une résa MANUELLE (client_id NULL),
  -- `!=` valait NULL et le IF ne levait pas : n'importe quel compte connaissant
  -- l'id pouvait l'annuler. Une manuelle n'a pas de client côté app : refus.
  IF v_bk IS NULL OR v_bk.client_id IS DISTINCT FROM v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'cancelled'
  WHERE id = p_booking_id AND status IN ('pending', 'accepted');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Le pro n'est prévenu que si c'était CONFIRMÉ (un pending annulé disparaît).
  IF v_bk.status = 'accepted' THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
    PERFORM create_notification(
      v_bk.pro_id,
      'booking_cancelled',
      'Réservation annulée',
      coalesce(v_client_name, 'Un client') || ' a annulé « '
        || coalesce(v_off_title, 'une sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM') || '.',
      jsonb_build_object('booking_id', v_bk.id, 'by', 'client', 'variant', 'by_client',
        'params', jsonb_build_object('name', coalesce(v_client_name, 'Un client'), 'title', coalesce(v_off_title, 'une sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cancel_booking_pro(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_pro_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00420 D1 : idem côté pro.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.pro_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'cancelled_pro'
  WHERE id = p_booking_id AND status IN ('pending', 'accepted');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_bk.client_id IS NOT NULL AND v_bk.status = 'accepted' THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
    PERFORM create_notification(
      v_bk.client_id,
      'booking_cancelled',
      'Sortie annulée',
      coalesce(v_pro_name, 'Le professionnel') || ' a annulé « '
        || coalesce(v_off_title, 'ta sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM')
        || '. Contacte-le pour reprogrammer.',
      jsonb_build_object('booking_id', v_bk.id, 'by', 'pro', 'variant', 'by_pro',
        'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'ta sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text DEFAULT NULL::text, p_levels text[] DEFAULT NULL::text[], p_starts_on date DEFAULT NULL::date, p_ends_on date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_alert_count INTEGER;
  v_alert_id UUID;
  v_allowed_levels TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
  v_level TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00499 (DC-6): validated inputs.
  IF p_lng IS NULL OR p_lat IS NULL OR p_lng NOT BETWEEN -180 AND 180 OR p_lat NOT BETWEEN -90 AND 90
     OR p_radius_km IS NULL OR p_radius_km NOT BETWEEN 5 AND 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_sport_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = p_sport_key AND s.is_active) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Serialise the cap.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_alerts'));

  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'junto.alert_limit_reached';
  END IF;

  IF p_levels IS NOT NULL THEN
    IF array_length(p_levels, 1) IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    FOREACH v_level IN ARRAY p_levels LOOP
      IF NOT (v_level = ANY(v_allowed_levels)) THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
    END LOOP;
  END IF;

  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < private.today_paris() THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;

  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, levels, starts_on, ends_on, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_levels,
    p_starts_on,
    p_ends_on,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_msg TEXT;
  v_existing RECORD;
  v_booking_id UUID;
  v_client_name TEXT;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT po.id, po.pro_id, po.title, po.max_participants, pp.is_demo
    INTO v_off
  FROM pro_offerings po
  JOIN pro_profiles pp ON pp.user_id = po.pro_id
  JOIN users u ON u.id = po.pro_id
  WHERE po.id = p_offering_id
    AND pp.status = 'approved'
    AND u.suspended_at IS NULL
    AND u.tier = 'pro'
  -- 00518 (L4): the offering cannot be deleted while this booking is created.
  FOR SHARE OF po;
  IF v_off IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.is_demo = true AND NOT demo_content_visible() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_off.pro_id)
       OR (blocker_id = v_off.pro_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_day IS NULL OR p_day < private.today_paris() OR p_day > private.today_paris() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_availabilities
    WHERE pro_id = v_off.pro_id AND day = p_day AND period = p_period
  ) THEN
    RAISE EXCEPTION 'junto.booking_slot_unavailable';
  END IF;

  IF p_party_size IS NULL
     OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  v_msg := nullif(regexp_replace(trim(coalesce(p_message, '')), '<[^>]*>', '', 'g'), '');
  IF v_msg IS NOT NULL AND char_length(v_msg) > 500 THEN
    RAISE EXCEPTION 'junto.booking_message';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND status = 'pending'
        AND day >= private.today_paris()) >= 5 THEN  -- 00523: past days never block
    RAISE EXCEPTION 'junto.booking_pending_cap';
  END IF;
  -- Cap quotidien inchangé : le trou H1 (cycles annuler/recréer sur la même
  -- ligne) est fermé par le cooldown 1 h + le plafond 5 soumissions/ligne
  -- ci-dessous — sans surcompter les soumissions anciennes d'une ligne réactivée.
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND created_at > now() - INTERVAL '24 hours') >= 10 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  SELECT * INTO v_existing FROM bookings
  WHERE offering_id = p_offering_id AND client_id = v_user_id
    AND day = p_day AND period = p_period
  FOR UPDATE;

  IF v_existing.id IS NOT NULL THEN  -- 00477: a RECORD with any NULL field is never « IS NOT NULL »
    IF v_existing.status IN ('pending', 'accepted') THEN
      RAISE EXCEPTION 'junto.booking_already';
    END IF;
    -- Anti-spam (00418 H1) : cooldown 1 h entre soumissions du même créneau,
    -- plafond 5 soumissions par créneau à vie.
    IF v_existing.last_submitted_at > now() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    IF v_existing.submitted_count >= 5 THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'pending', party_size = p_party_size, message = v_msg,
        created_at = now(),
        -- 00505: a re-submitted request takes the current price.
        price_eur = (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
        price_unit = (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id),
        submitted_count = v_existing.submitted_count + 1,
        last_submitted_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      -- 00501 (PO-5): the price the client asked at is kept with the booking.
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message, price_eur, price_unit)
      VALUES (p_offering_id, v_off.pro_id, v_user_id, p_day, p_period, p_party_size, v_msg,
              (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
              (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id))
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE p_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  PERFORM create_notification(
    v_off.pro_id,
    'booking_request',
    'Nouvelle demande de réservation',
    coalesce(v_client_name, 'Un membre') || ' · « ' || v_off.title || ' » · '
      || to_char(p_day, 'DD/MM') || ', ' || v_period_label
      || ' · ' || p_party_size || ' pers.',
    jsonb_build_object('booking_id', v_booking_id, 'offering_id', p_offering_id,
      'params', jsonb_build_object('name', coalesce(v_client_name, 'Un membre'), 'title', v_off.title,
                                   'date', to_char(p_day, 'YYYY-MM-DD'), 'period', p_period, 'count', p_party_size))
  );

  RETURN v_booking_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_name TEXT;
  v_phone TEXT;
  v_booking_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT po.id, po.max_participants INTO v_off
  FROM pro_offerings po WHERE po.id = p_offering_id AND po.pro_id = v_user_id;
  IF v_off IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Le pro peut saisir sur n'importe quel jour futur (même non marqué dispo) :
  -- c'est SON agenda, source de vérité y compris pour l'hors-app.
  IF p_day IS NULL OR p_day < private.today_paris() OR p_day > private.today_paris() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF p_party_size IS NULL OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  v_name := nullif(regexp_replace(trim(coalesce(p_name, '')), '<[^>]*>', '', 'g'), '');
  IF v_name IS NULL OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.booking_manual_name';
  END IF;
  v_phone := nullif(regexp_replace(trim(coalesce(p_phone, '')), '<[^>]*>', '', 'g'), '');
  IF v_phone IS NOT NULL AND char_length(v_phone) NOT BETWEEN 3 AND 30 THEN
    RAISE EXCEPTION 'junto.booking_manual_name';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_manual_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE pro_id = v_user_id AND client_id IS NULL
        AND created_at > now() - INTERVAL '24 hours') >= 30 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  INSERT INTO bookings (offering_id, pro_id, client_id, manual_name, manual_phone,
                        day, period, party_size, status)
  VALUES (p_offering_id, v_user_id, NULL, v_name, v_phone, p_day, p_period, p_party_size, 'accepted')
  RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_own_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_channel RECORD;
  v_new_owner UUID;
  v_booking RECORD;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 2. Cancel all active activities created by user + notify participants
  FOR v_activity IN
    SELECT id, title FROM activities
    WHERE creator_id = v_user_id AND status IN ('published', 'in_progress')
  LOOP
    UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = v_activity.id;

    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = v_activity.id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_cancelled',
        'Sortie annulée',
        '« ' || v_activity.title || ' » — l''organisateur a quitté Junto',
        jsonb_build_object('activity_id', v_activity.id, 'variant', 'creator_gone',
          'params', jsonb_build_object('title', v_activity.title))
      );
    END LOOP;
  END LOOP;

  -- 2b. Channels created by the user: hand the hub to the earliest remaining
  -- member so it keeps a moderator; if none remain, close it. Before the user
  -- delete so the created_by FK no longer references these rows.
  FOR v_channel IN
    SELECT conversation_id FROM channels WHERE created_by = v_user_id
  LOOP
    SELECT user_id INTO v_new_owner
    FROM conversation_members
    WHERE conversation_id = v_channel.conversation_id AND user_id != v_user_id
    ORDER BY joined_at ASC
    LIMIT 1;

    IF v_new_owner IS NOT NULL THEN
      UPDATE channels SET created_by = v_new_owner WHERE conversation_id = v_channel.conversation_id;
      UPDATE conversations SET created_by = v_new_owner WHERE id = v_channel.conversation_id;
    ELSE
      UPDATE channels SET closed_at = now()
      WHERE conversation_id = v_channel.conversation_id AND closed_at IS NULL;
    END IF;
  END LOOP;

  -- 2c. Réservations futures (00419 M1) : le CASCADE va les effacer sans un
  -- mot — prévenir la contrepartie AVANT. Miroir du bloc activités : pro
  -- supprimé → tout client (pending ou accepté) est prévenu ; client supprimé
  -- → le pro n'est prévenu que pour du confirmé (un pending qui disparaît
  -- reste silencieux, pattern cancel_booking).
  FOR v_booking IN
    SELECT b.id, b.day, b.pro_id, b.client_id, b.status, po.title
    FROM bookings b
    LEFT JOIN pro_offerings po ON po.id = b.offering_id
    WHERE (b.pro_id = v_user_id OR b.client_id = v_user_id)
      AND b.status IN ('pending', 'accepted')
      AND b.day >= private.today_paris()
  LOOP
    IF v_booking.pro_id = v_user_id THEN
      IF v_booking.client_id IS NOT NULL THEN
        PERFORM create_notification(
          v_booking.client_id,
          'booking_cancelled',
          'Sortie annulée',
          '« ' || coalesce(v_booking.title, 'Ta sortie') || ' » du '
            || to_char(v_booking.day, 'DD/MM') || ' est annulée — le professionnel n''est plus sur Junto.',
          jsonb_build_object('booking_id', v_booking.id, 'by', 'pro', 'variant', 'pro_gone',
            'params', jsonb_build_object('title', coalesce(v_booking.title, 'Ta sortie'), 'date', to_char(v_booking.day, 'YYYY-MM-DD')))
        );
      END IF;
    ELSIF v_booking.status = 'accepted' THEN
      PERFORM create_notification(
        v_booking.pro_id,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_booking.title, 'une sortie') || ' » du '
          || to_char(v_booking.day, 'DD/MM') || ' a été annulée (compte supprimé).',
        jsonb_build_object('booking_id', v_booking.id, 'by', 'client', 'variant', 'client_gone',
          'params', jsonb_build_object('title', coalesce(v_booking.title, 'une sortie'), 'date', to_char(v_booking.day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;

  -- 3. Wall messages: anonymize (SET NULL handled by FK ON DELETE SET NULL)
  -- 4. Private messages: deleted by FK ON DELETE CASCADE
  -- 5. Conversations: deleted by FK ON DELETE CASCADE
  -- 6. Participations: deleted by FK ON DELETE CASCADE
  -- 7. Notifications: deleted by FK ON DELETE CASCADE
  -- 8. Blocked users: deleted by FK ON DELETE CASCADE
  -- 9. Reputation votes: deleted by FK ON DELETE CASCADE
  -- 10. Reports: reporter anonymisé (reporter_id → SET NULL depuis 00418 ;
  --     l'historique de modération survit sans identité)

  -- 11. Delete the user row — FKs handle cascading
  DELETE FROM users WHERE id = v_user_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_pro_offering(p_offering_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00518 (L4): lock the offering first — no booking can slip in between the
  -- check below and the delete.
  PERFORM 1 FROM pro_offerings WHERE id = p_offering_id FOR UPDATE;

  -- 00416 : refuser tant que des réservations futures vivantes existent.
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE offering_id = p_offering_id
      AND status IN ('pending', 'accepted')
      AND day >= private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  DELETE FROM pro_offerings WHERE id = p_offering_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_bookings()
 RETURNS TABLE(id uuid, offering_id uuid, offering_title text, pro_id uuid, pro_name text, day date, period text, party_size integer, status text, conversation_id uuid, created_at timestamp with time zone, location_name text, price_eur numeric, price_unit text, sport_key text, sport_category text, equipment_required jsonb, participant_fields jsonb, participant_info jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  -- 00501 (PO-6): a suspended account reads nothing (like the table).
  IF private.user_is_suspended(v_user_id) THEN RETURN; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'expired'
  WHERE bookings.client_id = v_user_id AND bookings.status = 'pending' AND bookings.day < private.today_paris();
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT b.id, b.offering_id, po.title, b.pro_id, pp.display_name,
         b.day, b.period, b.party_size, b.status,
         (SELECT c.id FROM conversations c
          WHERE c.type = 'dm' AND c.status = 'active'
            AND c.user_1 = LEAST(v_user_id, b.pro_id)
            AND c.user_2 = GREATEST(v_user_id, b.pro_id)),
         b.created_at,
         po.location_name, coalesce(b.price_eur, po.price_eur), coalesce(b.price_unit, po.price_unit::TEXT),  -- 00501 (PO-5)
         s.key::TEXT, s.category::TEXT,
         po.equipment_required, po.participant_fields, b.participant_info
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.pro_id
  WHERE b.client_id = v_user_id
  ORDER BY b.day DESC, b.created_at DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_pro_agenda(p_from date, p_to date)
 RETURNS TABLE(kind text, id uuid, day date, period text, status text, offering_id uuid, offering_title text, party_size integer, client_id uuid, client_name text, manual_phone text, message text, is_manual boolean, sport_key text, sport_category text, participant_fields jsonb, participant_info jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_flip RECORD;
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from
     OR p_to > p_from + INTERVAL '12 months' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Expiration paresseuse + notif client (00420 D3).
  PERFORM set_config('junto.bypass_lock', 'true', true);
  FOR v_flip IN
    WITH flipped AS (
      UPDATE bookings SET status = 'expired'
      WHERE bookings.pro_id = v_user_id AND bookings.status = 'pending'
        AND bookings.day < private.today_paris()
      RETURNING bookings.id AS b_id, bookings.client_id AS b_client,
                bookings.offering_id AS b_off, bookings.day AS b_day,
                bookings.period AS b_period
    )
    SELECT f.b_id, f.b_client, f.b_off, f.b_day, f.b_period, po.title AS b_title
    FROM flipped f
    LEFT JOIN pro_offerings po ON po.id = f.b_off
    WHERE f.b_client IS NOT NULL
  LOOP
    v_period_label := CASE v_flip.b_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;
    PERFORM create_notification(
      v_flip.b_client,
      'booking_expired',
      'Demande expirée',
      'Ta demande pour « ' || coalesce(v_flip.b_title, 'une sortie') || ' » du '
        || to_char(v_flip.b_day, 'DD/MM') || ', ' || v_period_label
        || ' a expiré sans réponse. Tu peux demander un autre créneau.',
      jsonb_build_object('booking_id', v_flip.b_id, 'offering_id', v_flip.b_off,
        'params', jsonb_build_object('title', coalesce(v_flip.b_title, 'une sortie'),
                                     'date', to_char(v_flip.b_day, 'YYYY-MM-DD'), 'period', v_flip.b_period))
    );
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT 'availability'::TEXT, a.id, a.day, a.period, NULL::TEXT,
         NULL::UUID, NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::TEXT, NULL::TEXT,
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT, NULL::JSONB, NULL::JSONB
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL),
         s.key::TEXT, s.category::TEXT,
         po.participant_fields, b.participant_info
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id
    AND b.day BETWEEN p_from AND p_to
    AND b.status IN ('pending', 'accepted')
  ORDER BY 3, 4;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_pro_availability(p_pro_id uuid)
 RETURNS TABLE(day date, period text, taken integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- Cible : pro approuvé + tier pro (00419), non suspendu, gate démo, pas de blocage.
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles pp
    JOIN users u ON u.id = pp.user_id
    WHERE pp.user_id = p_pro_id
      AND pp.status = 'approved'
      AND u.tier = 'pro'
      AND u.suspended_at IS NULL
      AND (pp.is_demo = false OR demo_content_visible())
  ) THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_pro_id)
       OR (blocker_id = p_pro_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  -- `taken` = somme des groupes ACCEPTÉS du pro sur le créneau, toutes offres
  -- confondues (un pro = une sortie par demi-journée). Agrégat anonyme :
  -- aucun nom, aucune composition de groupe ne fuite.
  RETURN QUERY
  SELECT a.day, a.period,
         coalesce((
           SELECT sum(b.party_size)::INTEGER FROM bookings b
           WHERE b.pro_id = p_pro_id AND b.day = a.day AND b.period = a.period
             AND b.status = 'accepted'
         ), 0) AS taken
  FROM pro_availabilities a
  WHERE a.pro_id = p_pro_id AND a.day >= private.today_paris()
  ORDER BY a.day, a.period;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.purge_booking_participant_info()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = NULL
  WHERE participant_info IS NOT NULL AND day < private.today_paris() - 30;
  -- 00518 (L5): third-party contact typed by the pro, and the client's free
  -- text, are not kept forever either.
  UPDATE bookings SET manual_phone = NULL, message = NULL
  WHERE (manual_phone IS NOT NULL OR message IS NOT NULL) AND day < private.today_paris() - 30;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_booking_participant_info(p_booking_id uuid, p_info jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_fields JSONB;
  v_allowed_std JSONB;
  v_allowed_custom JSONB;
  v_entry JSONB;
  v_key TEXT;
  v_val JSONB;
  v_q TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT b.*, po.participant_fields AS fields INTO v_bk
  FROM bookings b JOIN pro_offerings po ON po.id = b.offering_id
  WHERE b.id = p_booking_id
  FOR UPDATE OF b;
  IF v_bk IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Client Junto : lui seul. Résa manuelle (sans compte) : le pro saisit.
  IF NOT (
    (v_bk.client_id IS NOT NULL AND v_bk.client_id = v_user_id)
    OR (v_bk.client_id IS NULL AND v_bk.pro_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_bk.day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  v_fields := coalesce(v_bk.fields, '{"std":[],"custom":[]}'::jsonb);
  v_allowed_std := coalesce(v_fields->'std', '[]'::jsonb);
  v_allowed_custom := coalesce(v_fields->'custom', '[]'::jsonb);
  IF jsonb_array_length(v_allowed_std) = 0 AND jsonb_array_length(v_allowed_custom) = 0 THEN
    RAISE EXCEPTION 'Operation not permitted'; -- l'offre ne demande pas de fiche
  END IF;

  -- Validation : tableau ≤ party_size ; par participant, un objet dont les
  -- clés ⊆ champs std demandés (valeurs texte ≤ 30) + 'custom' (objet
  -- question⊆demandées → réponse ≤ 120). Les valeurs sont stockées nettoyées
  -- (balises HTML et caractères de contrôle retirés, 00473 — audit L13).
  IF p_info IS NULL OR jsonb_typeof(p_info) != 'array'
     OR jsonb_array_length(p_info) < 1
     OR jsonb_array_length(p_info) > v_bk.party_size THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_info) LOOP
    IF jsonb_typeof(v_entry) != 'object' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    FOR v_key, v_val IN SELECT * FROM jsonb_each(v_entry) LOOP
      IF v_key = 'custom' THEN
        IF jsonb_typeof(v_val) != 'object' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
        FOR v_q IN SELECT jsonb_object_keys(v_val) LOOP
          IF NOT v_allowed_custom ? v_q THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
          IF jsonb_typeof(v_val->v_q) != 'string'
             OR char_length(v_val->>v_q) > 120 THEN
            RAISE EXCEPTION 'Operation not permitted';
          END IF;
        END LOOP;
      ELSE
        IF NOT v_allowed_std ? v_key THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
        IF jsonb_typeof(v_val) != 'string' OR char_length(v_entry->>v_key) > 30 THEN
          RAISE EXCEPTION 'Operation not permitted';
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET participant_info = (
    SELECT jsonb_agg(
      (SELECT coalesce(jsonb_object_agg(k,
         CASE WHEN k = 'custom' THEN
           (SELECT coalesce(jsonb_object_agg(q, to_jsonb(
              regexp_replace(regexp_replace(trim(a #>> '{}'), '<[^>]*>', '', 'g'), '[[:cntrl:]]', '', 'g'))), '{}'::jsonb)
            FROM jsonb_each(v) AS c(q, a))
         ELSE to_jsonb(regexp_replace(regexp_replace(trim(v #>> '{}'), '<[^>]*>', '', 'g'), '[[:cntrl:]]', '', 'g'))
         END), '{}'::jsonb)
       FROM jsonb_each(e) AS kv(k, v))
      ORDER BY ord)
    FROM jsonb_array_elements(p_info) WITH ORDINALITY AS x(e, ord)
  ) WHERE id = p_booking_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_pro_availability(p_day date, p_period text, p_available boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_day IS NULL OR p_day < private.today_paris() THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF p_day > private.today_paris() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;

  IF p_available THEN
    INSERT INTO pro_availabilities (pro_id, day, period)
    VALUES (v_user_id, p_day, p_period)
    ON CONFLICT (pro_id, day, period) DO NOTHING;
  ELSE
    DELETE FROM pro_availabilities
    WHERE pro_id = v_user_id AND day = p_day AND period = p_period;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_pro_availability_bulk(p_days date[], p_periods text[], p_available boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_n INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  v_n := coalesce(array_length(p_days, 1), 0);
  IF v_n < 1 OR v_n > 200 OR v_n IS DISTINCT FROM coalesce(array_length(p_periods, 1), 0) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_periods) AS pr WHERE pr IS NULL OR pr NOT IN ('am', 'pm')
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(p_days) AS d
    WHERE d IS NULL OR d < private.today_paris() OR d > private.today_paris() + INTERVAL '6 months'
  ) THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;

  IF p_available THEN
    INSERT INTO pro_availabilities (pro_id, day, period)
    SELECT v_user_id, t.d, t.pr
    FROM unnest(p_days, p_periods) AS t(d, pr)
    ON CONFLICT (pro_id, day, period) DO NOTHING;
  ELSE
    DELETE FROM pro_availabilities a
    USING unnest(p_days, p_periods) AS t(d, pr)
    WHERE a.pro_id = v_user_id AND a.day = t.d AND a.period = t.pr;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.unregister_as_pro()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00518 (L4): lock all of this pro's offerings before the check.
  PERFORM 1 FROM pro_offerings WHERE pro_id = v_user_id FOR UPDATE;

  -- 00416 : refuser tant que des réservations futures vivantes existent
  -- (le CASCADE pro_profiles → pro_offerings → bookings serait silencieux).
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE pro_id = v_user_id
      AND status IN ('pending', 'accepted')
      AND day >= private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  -- 00443 B6 : pro_availabilities référence users, pas pro_profiles — sans
  -- ceci les créneaux ouverts survivaient à la désinscription et redevenaient
  -- réservables tels quels à une ré-inscription.
  DELETE FROM pro_availabilities WHERE pro_id = v_user_id;
  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_alerts_for_activity(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_activity RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
  v_alert RECORD;
  v_today_count INTEGER;
BEGIN
  SELECT a.id, a.creator_id, a.title, a.location_meeting,
         a.starts_at, a.level, a.status, a.deleted_at, s.key AS sport_key
  INTO v_activity
  FROM activities a JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'published' OR v_activity.deleted_at IS NOT NULL THEN
    RETURN;
  END IF;

  v_sport_key := v_activity.sport_key;
  v_activity_date := (v_activity.starts_at AT TIME ZONE 'Europe/Paris')::date;  -- 00523

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
      AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000)
  LOOP
    -- Per-user advisory lock so the count+insert is atomic vs. concurrent
    -- alert checks for the same user (multiple activities published in parallel).
    PERFORM pg_advisory_xact_lock(hashtext('alert_match_' || v_alert.user_id::text));

    SELECT count(*) INTO v_today_count
    FROM notifications
    WHERE user_id = v_alert.user_id
      AND type = 'alert_match'
      AND created_at >= (private.today_paris()::timestamp AT TIME ZONE 'Europe/Paris');  -- 00523: Paris day

    IF v_today_count >= 3 THEN CONTINUE; END IF;

    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle sortie pour ton alerte',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id,
        'params', jsonb_build_object('title', v_activity.title))
    );
  END LOOP;
END;
$function$;


-- ==========================================================================
-- 5. Push taps reach the right screen
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.push_notification_to_device()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_should_push BOOLEAN := TRUE;
  v_collapse_id TEXT;
  v_activity_starts TIMESTAMPTZ;
  v_changes JSONB;
  v_secret TEXT;
  v_activity_id TEXT;
  v_presence_count INT;
  v_title TEXT := NEW.title;
  v_forwarded_data JSONB;
  v_allowed_keys TEXT[] := ARRAY[
    'activity_id',
    'conversation_id',
    'seat_request_id',
    'driver_id',
    'requester_id',
    'from_user_id',
    -- 00472 (audit M7): send-push composes the text in the recipient's
    -- language from these (lots A-F, 00447-00450). Display names, titles,
    -- dates only — the same facts the French body already carries.
    'params',
    'variant',
    -- 00523: routing keys for bookings, reviews and pro pages (ids only).
    'by',
    'pro_id',
    'offering_id',
    'booking_id'
  ];
BEGIN
  IF (NEW.data ? 'skip_push') AND ((NEW.data->>'skip_push')::boolean IS TRUE) THEN
    RETURN NEW;
  END IF;

  CASE NEW.type
    WHEN 'rate_participants', 'request_refused' THEN
      v_should_push := FALSE;

    WHEN 'participant_joined' THEN
      v_collapse_id := 'joined-' || (NEW.data->>'activity_id');

    WHEN 'badge_unlocked' THEN
      v_collapse_id := 'badge-' || NEW.user_id::text
                       || '-' || to_char(NEW.created_at, 'YYYY-MM-DD');

    WHEN 'presence_pre_warning', 'presence_validate_now', 'presence_validate_warning' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
        SELECT count(*) INTO v_presence_count
        FROM notifications
        WHERE user_id = NEW.user_id
          AND type IN ('presence_pre_warning', 'presence_validate_now', 'presence_validate_warning')
          AND (data->>'activity_id') = v_activity_id
          AND created_at > NOW() - INTERVAL '24 hours';
        IF v_presence_count > 1 THEN
          v_title := v_title || ' (×' || v_presence_count || ')';
        END IF;
      END IF;

    WHEN 'presence_confirmed' THEN
      v_activity_id := NEW.data->>'activity_id';
      IF v_activity_id IS NOT NULL THEN
        v_collapse_id := 'presence-' || v_activity_id;
      END IF;

    WHEN 'activity_cancelled' THEN
      SELECT starts_at INTO v_activity_starts
      FROM activities WHERE id = (NEW.data->>'activity_id')::uuid;
      v_should_push := v_activity_starts IS NULL
                       OR (v_activity_starts - now() < INTERVAL '48 hours');

    WHEN 'activity_updated' THEN
      v_changes := NEW.data->'changes';
      v_should_push := v_changes IS NOT NULL AND (
        v_changes ? 'starts_at' OR v_changes ? 'duration'
        OR v_changes ? 'location_meeting'
        OR v_changes ? 'max_participants' OR v_changes ? 'level'
        OR v_changes ? 'trace'  -- 00475: route changed after sign-up
      );

    ELSE
      v_should_push := TRUE;
  END CASE;

  IF NOT v_should_push THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL THEN RETURN NEW; END IF;

  -- Strict allow-list — anything not in v_allowed_keys is dropped
  -- before the payload leaves the DB. `type` is always added (the
  -- client routes on it).
  SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb)
    INTO v_forwarded_data
  FROM jsonb_each(COALESCE(NEW.data, '{}'::jsonb))
  WHERE key = ANY(v_allowed_keys);

  v_forwarded_data := v_forwarded_data || jsonb_build_object('type', NEW.type);

  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', v_title,
      'body', NEW.body,
      'data', v_forwarded_data,
      'collapseId', v_collapse_id
    )
  );

  RETURN NEW;
END;
$function$;


-- ==========================================================================
-- 6-8. Join requests, blocks, invitations
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.join_activity(p_activity_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo, deleted_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: once the presence check window of a started outing has passed,
  -- nobody joins any more (they could no longer validate, and could tip a
  -- 2-person outing into the 3+ rule).
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;

  -- Demo activities are joinable only by an admin currently in demo mode.
  IF v_activity.is_demo AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00494 (AC-11): the outing of a suspended organiser is hidden everywhere;
  -- it cannot be joined by id either.
  IF private.user_is_suspended(v_activity.creator_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00486 (IX-1): a private outing is joined only through its link (opened
  -- by this account) or an invitation from its organiser — never by id alone.
  IF v_activity.visibility IN ('private_link', 'private_link_approval')
     AND NOT private.private_activity_access(p_activity_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour'
    AND status <> 'invited';  -- 00523: invitations received are not the invitee's joins
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at, left_at INTO v_existing
  FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- 00477 (DB-PR-1): test the id, not the record — a RECORD with any NULL field
  -- (refused_at, left_at) is never « IS NOT NULL », which sent every rejoin to
  -- the INSERT branch and a raw unique violation.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    IF v_existing.status = 'invited' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE participations
      SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
      WHERE id = v_existing.id;
      SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
      PERFORM create_notification(
        v_activity.creator_id, 'invitation_accepted',
        coalesce(v_user_name, 'Quelqu''un') || ' a accepté ton invitation',
        '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
        jsonb_build_object('activity_id', p_activity_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
      );
      RETURN 'accepted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    -- 00477 (AB-1): a join/leave loop pushed the organiser without limit — the
    -- hourly cap counts rows and a rejoin reuses the same row. 15 min after a
    -- withdrawal before rejoining the same outing.
    IF v_existing.status = 'withdrawn'
       AND v_existing.left_at IS NOT NULL
       AND v_existing.left_at > NOW() - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'junto.rejoin_cooldown';
    END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now(), refused_at = NULL
    WHERE id = v_existing.id;
  ELSE
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id, 'join_request',
      coalesce(v_user_name, 'Quelqu''un') || ' veut rejoindre ta sortie',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id, 'requester_id', v_user_id,  -- 00523
        'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title))
    );
  ELSE
    PERFORM notify_participant_joined(v_activity.creator_id, p_activity_id, v_user_name, v_activity.title);
  END IF;

  RETURN v_result_status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_activity_invitations(p_activity_id uuid, p_user_ids uuid[], p_message text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_n INTEGER;
  v_daily INTEGER;
  v_written INTEGER := 0;
  v_target UUID;
  v_existing RECORD;
  v_clean_msg TEXT;
  v_sender_name TEXT;
  v_clean_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_n := array_length(p_user_ids, 1);
  IF p_user_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_n > 20 THEN RAISE EXCEPTION 'junto.invite_cap'; END IF;

  IF p_message IS NOT NULL AND char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'junto.message_too_long';
  END IF;
  v_clean_msg := NULLIF(regexp_replace(trim(COALESCE(p_message, '')), '<[^>]*>', '', 'g'), '');

  SELECT id, title, creator_id, status, deleted_at, is_demo INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_activity.creator_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00523: same lock as join/accept — an invitation nobody could accept is not sent.
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_invite'));
  SELECT count(*) INTO v_daily FROM participations
  WHERE invited_by = v_user_id AND created_at > now() - INTERVAL '24 hours';
  IF v_daily >= 30 THEN RAISE EXCEPTION 'junto.invite_daily_cap'; END IF;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  PERFORM set_config('junto.bypass_lock', 'true', true);

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL AND is_demo = false);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN NOT private.is_messaging_eligible(v_user_id, v_target);
    -- 00522 (F14): not someone in a block relation with an accepted member
    -- (the invitation could never be accepted).
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users b JOIN participations q ON q.activity_id = p_activity_id AND q.status = 'accepted'
      WHERE (b.blocker_id = q.user_id AND b.blocked_id = v_target) OR (b.blocker_id = v_target AND b.blocked_id = q.user_id));
    -- 00499 (MS-3): someone who declined this outing's invitation is not
    -- invited to it again.
    CONTINUE WHEN EXISTS (SELECT 1 FROM invitation_declines d
                          WHERE d.activity_id = p_activity_id AND d.user_id = v_target);

    SELECT id, status INTO v_existing FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_target;

    IF v_existing.id IS NULL THEN
      EXIT WHEN v_daily + v_written >= 30;  -- in-loop cap (no single-batch overshoot)
      INSERT INTO participations (activity_id, user_id, status, invited_by, invite_message, created_at)
      VALUES (p_activity_id, v_target, 'invited', v_user_id, v_clean_msg, now());
      v_written := v_written + 1;
    ELSIF v_existing.status IN ('withdrawn', 'refused', 'expired', 'removed') THEN
      EXIT WHEN v_daily + v_written >= 30;
      UPDATE participations
      SET status = 'invited', invited_by = v_user_id, invite_message = v_clean_msg,
          created_at = now(), refused_at = NULL, left_at = NULL
      WHERE id = v_existing.id;
      v_written := v_written + 1;
    ELSE
      CONTINUE;
    END IF;

    PERFORM create_notification(
      v_target, 'activity_invitation',
      coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
      '« ' || v_clean_title || ' »', jsonb_build_object('activity_id', p_activity_id, 'type', 'activity_invitation',
        'params', jsonb_build_object('name', coalesce(v_sender_name, 'Quelqu''un'), 'title', v_clean_title))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cascade_block_cleanup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_name TEXT;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 00522 (F2): a pending request of someone who is now in a block relation
  -- with an accepted member of that outing is withdrawn (it could never be
  -- accepted any more — the shared-outing rule would refuse it).
  -- 00523 (Scott, F2): the organiser is told that a block withdrew it — never
  -- who. Not when the organiser is a party (the refusal below covers it).
  FOR v_row IN
    UPDATE participations p
    SET status = 'withdrawn'
    FROM activities a
    WHERE a.id = p.activity_id
      AND p.status = 'pending'
      AND a.creator_id NOT IN (NEW.blocker_id, NEW.blocked_id)
      AND ((p.user_id = NEW.blocked_id AND EXISTS (SELECT 1 FROM participations q
              WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocker_id AND q.status = 'accepted'))
        OR (p.user_id = NEW.blocker_id AND EXISTS (SELECT 1 FROM participations q
              WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocked_id AND q.status = 'accepted')))
    RETURNING p.activity_id, p.user_id, a.creator_id, a.title
  LOOP
    SELECT display_name INTO v_name FROM public_profiles WHERE id = v_row.user_id;
    PERFORM create_notification(
      v_row.creator_id,
      'join_request_blocked',
      'Demande retirée',
      'La demande de ' || coalesce(v_name, 'quelqu''un') || ' pour « ' || v_row.title || ' » a été retirée : un blocage l''oppose à un participant.',
      jsonb_build_object('activity_id', v_row.activity_id,
        'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un'), 'title', v_row.title))
    );
  END LOOP;

  -- Refuse pending join requests where blocker is creator and blocked is requester (or vice-versa)
  UPDATE participations p
  SET status = 'refused', refused_at = now()
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND ((a.creator_id = NEW.blocker_id AND p.user_id = NEW.blocked_id)
      OR (a.creator_id = NEW.blocked_id AND p.user_id = NEW.blocker_id));

  -- Cancel pending/accepted seat requests in both directions
  UPDATE seat_requests
  SET status = 'cancelled'
  WHERE status IN ('pending', 'accepted')
    AND ((requester_id = NEW.blocker_id AND driver_id = NEW.blocked_id)
      OR (requester_id = NEW.blocked_id AND driver_id = NEW.blocker_id));

  RETURN NEW;
END;
$function$;

-- A request that ends without being accepted (withdrawn, expired, refused)
-- takes its unread « X veut rejoindre » notification with it.
CREATE OR REPLACE FUNCTION private.clear_stale_join_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'pending' AND NEW.status IN ('withdrawn', 'expired', 'refused') THEN
    DELETE FROM notifications n
    USING activities a
    WHERE a.id = NEW.activity_id
      AND n.user_id = a.creator_id
      AND n.type = 'join_request'
      AND n.read_at IS NULL
      AND n.data->>'activity_id' = NEW.activity_id::text
      AND n.data->>'requester_id' = NEW.user_id::text;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.clear_stale_join_request() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_participations_clear_join_request ON public.participations;
CREATE TRIGGER trg_participations_clear_join_request
  AFTER UPDATE OF status ON public.participations
  FOR EACH ROW EXECUTE FUNCTION private.clear_stale_join_request();


-- ==========================================================================
-- 9. A carpool message brings a hidden conversation back
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.request_seat(p_activity_id uuid, p_driver_id uuid, p_pickup_from text DEFAULT NULL::text, p_message text DEFAULT NULL::text, p_requested_pickup_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_starts_at TIMESTAMPTZ;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_conv_sender UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_seed_message TEXT;
  v_recent_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_driver_id)
       OR (blocker_id = p_driver_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('request_seat:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM seat_requests
  WHERE requester_id = v_user_id
    AND created_at > NOW() - INTERVAL '5 minutes';
  IF v_recent_count >= 5 THEN RAISE EXCEPTION 'junto.seat_rate_limit'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id
    AND a.status IN ('published', 'in_progress')
    AND a.starts_at > NOW() - INTERVAL '15 seconds'
    AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'junto.no_seats_available'; END IF;

  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'junto.pickup_out_of_window';
    END IF;
  END IF;

  -- Strip HTML/script tags from pickup_from too (message already does).
  v_pickup := CASE
    WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
    THEN regexp_replace(trim(p_pickup_from), '<[^>]*>', '', 'g')
    ELSE NULL
  END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  -- 00494 (BR-3): one seat per passenger and outing; a driver who carries
  -- passengers does not ride with someone else.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = p_activity_id AND driver_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';  -- 00496 (B-5): actionable, coded
  END IF;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  -- 00477 (DB-AC-2): test the id — the record has NULL columns, so the
  -- re-request branch was dead code and every re-request was refused.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    -- 00477 (AC-4 / AB-4): no request/cancel loop toward the same driver —
    -- 24 h after a refusal, 1 h after a cancellation or expiry.
    IF v_existing.status = 'declined' AND v_existing.created_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    IF v_existing.status IN ('cancelled', 'expired') AND v_existing.created_at > NOW() - INTERVAL '1 hour' THEN
      RAISE EXCEPTION 'junto.seat_request_cooldown';
    END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message,
        requested_pickup_at = p_requested_pickup_at
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message, requested_pickup_at)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message, p_requested_pickup_at)
      RETURNING id INTO v_request_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  IF v_user_id < p_driver_id THEN
    v_u1 := v_user_id; v_u2 := p_driver_id;
  ELSE
    v_u1 := p_driver_id; v_u2 := v_user_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (pas seulement active).
  -- Une ligne pending/declined est réactivée en logistique (retag 'transport'
  -- + purge des champs de requête — invariant 00372 : un refus social ne
  -- devient pas un contact par le covoit). Plus d'unique_violation brute.
  SELECT id, status, request_sender_id INTO v_conversation_id, v_conv_status, v_conv_sender
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  -- 00486 (IX-2 / BR-1): if the requester's own contact request to the driver
  -- was refused (or is still unanswered), the seat request must not turn into
  -- a conversation the driver never accepted. The driver gets the request by
  -- notification and decides; accepting it is the driver's consent.
  IF v_conversation_id IS NOT NULL AND v_conv_status IN ('declined', 'pending_request')
     AND v_conv_sender = v_user_id THEN
    v_conversation_id := NULL;
  END IF;

  -- 00514: a seat REQUEST never creates nor reactivates a conversation — only
  -- the driver's acceptance does (accept_seat_request). The seed message goes
  -- into an already active DM; otherwise the driver is notified only.
  IF v_conv_status IS DISTINCT FROM 'active' THEN
    v_conversation_id := NULL;
  END IF;

  IF v_conversation_id IS NOT NULL THEN
  v_seed_message := '🚗 Demande de place pour « ' || v_activity_title || ' »'
    || CASE WHEN v_pickup IS NOT NULL THEN E'\nDepuis : ' || v_pickup ELSE '' END
    || CASE WHEN v_message IS NOT NULL THEN E'\n\n' || v_message ELSE '' END;

  -- 00508: straight into the unified store (the legacy table and its mirror
  -- are gone). This writer notifies on its own: no generic message push.
  PERFORM set_config('junto.skip_message_push', 'true', true);
  INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, v_seed_message,
    jsonb_build_object(
      'type', 'seat_request_pending',
      'activity_id', p_activity_id,
      'seat_request_id', v_request_id
    ),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL  -- 00523
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  END IF;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_driver_id,
    'seat_request',
    'Demande de covoiturage',
    coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »'
      || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'conversation_id', v_conversation_id,
      'variant', CASE WHEN v_pickup IS NOT NULL THEN 'pickup' ELSE NULL END,
      'params', jsonb_build_object('name', coalesce(v_requester_name, 'Quelqu''un'), 'title', v_activity_title, 'pickup', coalesce(v_pickup, ''))
    )
  );

  RETURN v_conversation_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_seat_request(p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_updated_count INTEGER;
  v_skip_seed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'junto.seats_exhausted';
  END IF;

  -- 00494 (BR-3): a passenger already seated with another driver of this
  -- outing does not take a second seat (two drivers accepting at once are
  -- serialised on the passenger).
  PERFORM pg_advisory_xact_lock(hashtext('seat_passenger:' || v_req.activity_id::text || ':' || v_req.requester_id::text));
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
               AND status = 'accepted' AND id <> p_request_id) THEN
    RAISE EXCEPTION 'junto.passenger_already_seated';
  END IF;
  -- 00496 (BR-3): a passenger who carries passengers does not ride elsewhere,
  -- and a driver who is seated in someone else's car takes nobody.
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND driver_id = v_req.requester_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.driver_has_passengers';
  END IF;
  IF EXISTS (SELECT 1 FROM seat_requests
             WHERE activity_id = v_req.activity_id AND requester_id = v_req.driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00496 (B-4): the passenger's other pending requests on this outing are
  -- withdrawn (other drivers no longer see a request they cannot accept).
  UPDATE seat_requests SET status = 'cancelled'
  WHERE activity_id = v_req.activity_id AND requester_id = v_req.requester_id
    AND status = 'pending' AND id <> p_request_id;

  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL,
      transport_from_lat = NULL, transport_from_lng = NULL, transport_from_locality = NULL, transport_departs_at = NULL  -- 00522 (F11)
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_req.driver_id AND blocked_id = v_req.requester_id)
       OR (blocker_id = v_req.requester_id AND blocked_id = v_req.driver_id)
  ) OR EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_req.requester_id AND u.suspended_at IS NOT NULL
  ) INTO v_skip_seed;

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (retag 'transport' à la
  -- réactivation, purge des champs de requête). Plus d'unique_violation brute.
  SELECT id, status INTO v_conversation_id, v_conv_status
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF NOT v_skip_seed THEN
    IF v_conversation_id IS NULL THEN
      BEGIN
        INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
        RETURNING id INTO v_conversation_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT id INTO v_conversation_id FROM conversations
        WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
      END;
    ELSIF v_conv_status != 'active' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE conversations
      SET status = 'active', initiated_from = 'transport',
          request_sender_id = NULL, request_message = NULL,
          pending_activity_id = NULL, request_expires_at = NULL,
          last_message_at = NOW()
      WHERE id = v_conversation_id;
      UPDATE conversation_members SET hidden_at = NULL
      WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
      PERFORM set_config('junto.bypass_lock', 'false', true);
    END IF;

    v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
      || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
      || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

    -- 00508: unified store directly; this writer notifies on its own.
    PERFORM set_config('junto.skip_message_push', 'true', true);
    INSERT INTO messages (conversation_id, sender_id, content, metadata, created_at)
    VALUES (
      v_conversation_id, v_req.driver_id, v_message,
      jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
      NOW()
    );

    UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
    UPDATE conversation_members SET hidden_at = NULL  -- 00523
    WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  ELSIF v_conv_status IS DISTINCT FROM 'active' THEN
    -- Seed sauté (blocage/suspension) : ne pas pointer la notif vers un fil
    -- non actif.
    v_conversation_id := NULL;
  END IF;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );

  RETURN v_conversation_id;
END;
$function$;


-- ==========================================================================
-- 10. Message edits and deletions are live
-- ==========================================================================

CREATE OR REPLACE FUNCTION private.broadcast_message_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity UUID;
BEGIN
  IF NEW.content IS NOT DISTINCT FROM OLD.content AND NEW.deleted_at IS NOT DISTINCT FROM OLD.deleted_at THEN
    RETURN NEW;
  END IF;
  BEGIN
    PERFORM realtime.send(
      jsonb_build_object('table', 'messages', 'op', 'UPDATE',
                         'conversation_id', NEW.conversation_id, 'message_id', NEW.id),
      'change', 'conversation:' || NEW.conversation_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  SELECT activity_id INTO v_activity FROM conversations
  WHERE id = NEW.conversation_id AND type = 'activity';
  IF v_activity IS NOT NULL THEN
    BEGIN
      PERFORM realtime.send(
        jsonb_build_object('table', 'messages', 'op', 'UPDATE', 'conversation_id', NEW.conversation_id),
        'wall', 'activity:' || v_activity::text, true);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.broadcast_message_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_messages_broadcast_update ON public.messages;
CREATE TRIGGER trg_messages_broadcast_update
  AFTER UPDATE OF content, deleted_at ON public.messages
  FOR EACH ROW EXECUTE FUNCTION private.broadcast_message_update();


-- ==========================================================================
-- 11. « Sortie modifiée » notifications on by default (Scott 2026-10-22)
-- ==========================================================================

ALTER TABLE public.users ALTER COLUMN notification_preferences
  SET DEFAULT '{"alert_match": true, "driver_left": true, "join_request": true, "review_reply": true, "seat_request": true, "badge_unlocked": true, "booking_expired": true, "booking_request": true, "contact_request": true, "request_refused": true, "review_received": true, "activity_updated": true, "booking_accepted": true, "booking_declined": true, "participant_left": false, "request_accepted": true, "booking_cancelled": true, "rate_participants": true, "activity_cancelled": true, "participant_joined": false, "presence_confirmed": true, "qr_create_reminder": true, "participant_removed": true, "peer_review_closing": true, "presence_pre_warning": true, "seat_request_expired": true, "participant_left_late": true, "seat_request_accepted": true, "seat_request_declined": true, "contact_request_accepted": true, "presence_validate_overdue": true, "presence_validate_warning": true, "presence_pre_warning_10min": true}'::jsonb;
