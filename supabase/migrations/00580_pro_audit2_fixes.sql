-- Second pro audit fixes (audit 2026-11-02, round 2, docs/AUDIT_PRO_2026-11.md;
-- chains validated by Scott 2026-11-02). Every rebuilt function starts from
-- its LIVE definition. Ids in comments are the round-2 audit ids.


-- ---------------------------------------------------------------------------
-- A. Minimum and « Départ confirmé »

CREATE OR REPLACE FUNCTION private.mark_outing_confirmed(p_pro uuid, p_offering uuid, p_day date, p_period text, p_session uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_min INTEGER;
  v_n INTEGER;
  v_title TEXT;
  v_pro_name TEXT;
  v_bk RECORD;
BEGIN
  v_min := private.outing_min(p_offering, p_session);
  IF v_min IS NULL THEN RETURN false; END IF;
  IF p_reason = 'minimum' AND private.outing_total(p_offering, p_day, p_period, p_session) < v_min THEN
    RETURN false;
  END IF;

  -- 00580 (SESSIONS-A): « Maintenir » wins over « minimum reached » — an
  -- existing minimum confirmation becomes the pro's (clients were already told).
  IF p_reason = 'pro' THEN
    UPDATE private.outing_confirmations c SET reason = 'pro'
    WHERE c.reason <> 'pro'
      AND ((p_session IS NOT NULL AND c.session_id = p_session)
        OR (p_session IS NULL AND c.session_id IS NULL AND c.offering_id = p_offering
            AND c.day = p_day AND c.period = p_period));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN RETURN true; END IF;
  END IF;

  INSERT INTO private.outing_confirmations (pro_id, offering_id, day, period, session_id, reason)
  VALUES (p_pro, p_offering, p_day, p_period, p_session, p_reason)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN false; END IF;

  SELECT title INTO v_title FROM pro_offerings WHERE id = p_offering;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = p_pro;
  FOR v_bk IN
    SELECT b.id, b.client_id FROM bookings b
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND ((p_session IS NOT NULL AND b.session_id = p_session)
        OR (p_session IS NULL AND b.session_id IS NULL
            AND b.offering_id = p_offering AND b.day = p_day AND b.period = p_period))
  LOOP
    PERFORM create_notification(
      v_bk.client_id,
      'booking_confirmed',
      'Départ confirmé',
      'Le départ de « ' || coalesce(v_title, 'ta sortie') || ' » du ' || to_char(p_day, 'DD/MM') || ' est confirmé.',
      jsonb_build_object('booking_id', v_bk.id,
        'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                     'title', coalesce(v_title, 'ta sortie'),
                                     'date', to_char(p_day, 'YYYY-MM-DD'), 'period', p_period))
    );
  END LOOP;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION private.outing_recheck_on_leave()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_min INTEGER;
BEGIN
  IF OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted' THEN
    v_min := private.outing_min(NEW.offering_id, NEW.session_id);
    -- 00580 (SESSIONS-B): after the D-2 reminder a « Départ confirmé » already
    -- announced to clients stands — a late departure no longer withdraws it.
    IF v_min IS NOT NULL AND NOT private.after_d2_reminder(NEW.day)
       AND private.outing_total(NEW.offering_id, NEW.day, NEW.period, NEW.session_id) < v_min THEN
      DELETE FROM private.outing_confirmations c
      WHERE c.reason = 'minimum'
        AND ((NEW.session_id IS NOT NULL AND c.session_id = NEW.session_id)
          OR (NEW.session_id IS NULL AND c.session_id IS NULL AND c.offering_id = NEW.offering_id
              AND c.day = NEW.day AND c.period = NEW.period));
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_pro_session(p_session_id uuid, p_start_day date, p_start_period text, p_end_day date, p_end_period text, p_max_participants integer, p_min_participants integer DEFAULT NULL::integer, p_meeting_point text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_s RECORD;
  v_meeting TEXT;
  v_taken INTEGER;
  v_moved BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_sessions'));
  PERFORM pg_advisory_xact_lock(hashtext(p_session_id::text || '_session'));
  SELECT * INTO v_s FROM pro_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_s.pro_id <> v_user_id OR v_s.status <> 'scheduled' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF private.session_started(v_s.start_day, v_s.start_period) THEN
    RAISE EXCEPTION 'junto.session_closed';
  END IF;

  v_moved := (p_start_day, p_start_period, p_end_day, p_end_period)
             IS DISTINCT FROM (v_s.start_day, v_s.start_period, v_s.end_day, v_s.end_period);
  SELECT coalesce(sum(party_size), 0)::INTEGER INTO v_taken
  FROM bookings WHERE session_id = p_session_id AND status = 'accepted';
  -- Days change only while nobody is signed up: otherwise cancel and post again.
  IF v_moved AND v_taken > 0 THEN RAISE EXCEPTION 'junto.session_has_clients'; END IF;
  IF p_max_participants IS NOT NULL AND p_max_participants < v_taken THEN
    RAISE EXCEPTION 'junto.session_places';
  END IF;

  v_meeting := private.session_check(v_user_id, p_start_day, p_start_period, p_end_day, p_end_period,
                                     p_max_participants, p_min_participants, p_meeting_point, p_session_id);

  UPDATE pro_sessions
  SET start_day = p_start_day, start_period = p_start_period,
      end_day = p_end_day, end_period = p_end_period,
      max_participants = p_max_participants, min_participants = p_min_participants,
      meeting_point = v_meeting, updated_at = now()
  WHERE id = p_session_id;

  IF v_moved THEN
    PERFORM private.decline_pending_in_range(v_user_id,
      private.half_idx(p_start_day, p_start_period), private.half_idx(p_end_day, p_end_period));
    -- 00580 (SESSIONS-D): a moved date starts over — its old confirmation goes;
    -- posted after the D-2 reminder it is maintained, as in create_pro_session.
    DELETE FROM private.outing_confirmations WHERE session_id = p_session_id;
    IF private.after_d2_reminder(p_start_day) THEN
      PERFORM private.mark_outing_confirmed(v_user_id, v_s.offering_id, p_start_day, p_start_period, p_session_id, 'pro');
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_lk RECORD;
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

  -- 00580 (BOOKINGS-R2): the outing's lock before the row (the date, else the
  -- start half-day slot), like accept / join / manual: the minimum recheck of
  -- the trigger then sees a concurrent acceptance.
  SELECT session_id, pro_id, day, period INTO v_lk FROM bookings WHERE id = p_booking_id;
  IF FOUND THEN
    IF v_lk.session_id IS NOT NULL THEN
      PERFORM pg_advisory_xact_lock(hashtext(v_lk.session_id::text || '_session'));
    ELSE
      PERFORM pg_advisory_xact_lock(hashtext(v_lk.pro_id::text || v_lk.day::text || v_lk.period || '_slot'));
    END IF;
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
    -- 00578 (BOOKINGS-4): blocked either way → the same notice, without the name.
    IF EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_bk.pro_id AND blocked_id = v_user_id)
         OR (blocker_id = v_user_id AND blocked_id = v_bk.pro_id)
    ) THEN
      PERFORM create_notification(
        v_bk.pro_id,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_off_title, 'une sortie') || ' » du '
          || to_char(v_bk.day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'client', 'variant', 'client_gone',
          'params', jsonb_build_object('title', coalesce(v_off_title, 'une sortie'), 'date', to_char(v_bk.day, 'YYYY-MM-DD')))
      );
      RETURN;
    END IF;
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
$function$;

CREATE OR REPLACE FUNCTION public.cancel_booking_pro(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_lk RECORD;
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

  -- 00580 (BOOKINGS-R2): the outing's lock before the row (the date, else the
  -- start half-day slot), like accept / join / manual: the minimum recheck of
  -- the trigger then sees a concurrent acceptance.
  SELECT session_id, pro_id, day, period INTO v_lk FROM bookings WHERE id = p_booking_id;
  IF FOUND THEN
    IF v_lk.session_id IS NOT NULL THEN
      PERFORM pg_advisory_xact_lock(hashtext(v_lk.session_id::text || '_session'));
    ELSE
      PERFORM pg_advisory_xact_lock(hashtext(v_lk.pro_id::text || v_lk.day::text || v_lk.period || '_slot'));
    END IF;
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
    -- 00580 (BOOKINGS-R4): blocked either way → the neutral notice, no name.
    IF private.blocked_either_way(v_user_id, v_bk.client_id) THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        '« ' || coalesce(v_off_title, 'Ta sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'pro',
          'params', jsonb_build_object('title', coalesce(v_off_title, 'Ta sortie'), 'date', to_char(v_bk.day, 'YYYY-MM-DD')))
      );
      RETURN;
    END IF;
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
$function$;


-- ---------------------------------------------------------------------------
-- B. An outing under way (VITRINE-5): the guards look at its LAST day.

CREATE OR REPLACE FUNCTION public.delete_pro_offering(p_offering_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
      -- 00580 (VITRINE-5): an outing still running counts (range or date end).
      AND private.booking_last_day(session_id, end_day, day) >= private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  DELETE FROM pro_offerings WHERE id = p_offering_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.unregister_as_pro()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
      -- 00580 (VITRINE-5): an outing still running counts (range or date end).
      AND private.booking_last_day(session_id, end_day, day) >= private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  -- 00443 B6 : pro_availabilities référence users, pas pro_profiles — sans
  -- ceci les créneaux ouverts survivaient à la désinscription et redevenaient
  -- réservables tels quels à une ré-inscription.
  DELETE FROM pro_availabilities WHERE pro_id = v_user_id;
  -- 00578 (CALENDAR-4): the export token and the import go too — a return
  -- as pro gets a fresh link, never the old one.
  DELETE FROM private.pro_busy_slots WHERE pro_id = v_user_id;
  DELETE FROM private.pro_calendar_links WHERE pro_id = v_user_id;
  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_own_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
        '« ' || v_activity.title || ' » — l''organisateur a quitté askandgo',
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
      -- 00580 (VITRINE-5): clients of an outing under way are told too.
      AND private.booking_last_day(b.session_id, b.end_day, b.day) >= private.today_paris()
  LOOP
    IF v_booking.pro_id = v_user_id THEN
      IF v_booking.client_id IS NOT NULL THEN
        PERFORM create_notification(
          v_booking.client_id,
          'booking_cancelled',
          'Sortie annulée',
          '« ' || coalesce(v_booking.title, 'Ta sortie') || ' » du '
            || to_char(v_booking.day, 'DD/MM') || ' est annulée — le professionnel n''est plus sur askandgo.',
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
$function$;


-- ---------------------------------------------------------------------------
-- C. Community photos

CREATE OR REPLACE FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid DEFAULT NULL::uuid, p_offering_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_count INTEGER;
  v_photo_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF private.user_is_suspended(p_pro_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;  -- 00520
  -- 00578 (VITRINE-1): never on one's own page.
  IF p_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : cible = pro APPROUVÉ (ferme l'oracle de candidature — même
  -- erreur générique qu'une cible inexistante).
  -- 00443 B5 : et NON démo — un compte démo ne reçoit jamais d'écriture réelle (00426).
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND status = 'approved' AND is_demo = false
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00418 H4 : URL ancrée hôte + dossier du CONTRIBUTEUR (fin du wildcard).
  -- 00578 (VITRINE-1): in the own community folder of this pro (a file the
  -- contributor can no longer overwrite, storage policies).
  IF NOT private.pro_photo_in_folder(p_photo_url, v_user_id, 'community/' || p_pro_id::text) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00580 (CLIENT-1): the file is already there, uploaded by the caller — no
  -- URL registered first and filled later.
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id = 'pro-photos'
      AND o.owner_id = v_user_id::text
      AND o.name = split_part(substr(p_photo_url,
            char_length(private.project_url() || '/storage/v1/object/public/pro-photos/') + 1), '?', 1)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00578 (VITRINE-1): like a review, it needs an accepted booking with this
  -- pro (this offering when given) whose outing is over.
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.pro_id = p_pro_id AND b.client_id = v_user_id AND b.status = 'accepted'
      AND (p_offering_id IS NULL OR b.offering_id = p_offering_id)
      AND private.booking_last_day(b.session_id, b.end_day, b.day) < private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.photo_requires_booking';  -- 00580 (CLIENT-3)
  END IF;

  IF p_review_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_reviews
    WHERE id = p_review_id AND reviewer_id = v_user_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_offering_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pro_offerings
    WHERE id = p_offering_id AND pro_id = p_pro_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('add_community_photo:' || v_user_id::text || ':' || p_pro_id::text));

  SELECT count(*) INTO v_count
  FROM pro_community_photos
  WHERE pro_id = p_pro_id AND contributor_id = v_user_id;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'junto.photo_limit';
  END IF;

  INSERT INTO pro_community_photos (pro_id, contributor_id, photo_url, review_id, offering_id)
  VALUES (p_pro_id, v_user_id, p_photo_url, p_review_id, p_offering_id)
  RETURNING id INTO v_photo_id;

  RETURN v_photo_id;
END;
$function$;


-- 00580 (CLIENT-3): may the caller add a community photo to this pro's page
-- (this offering when given)? Only the caller's own situation is revealed.
CREATE FUNCTION public.can_add_community_photo(p_pro_id uuid, p_offering_id uuid DEFAULT NULL)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RETURN false;
  END IF;
  IF p_pro_id IS NULL OR p_pro_id = v_user_id OR private.user_is_suspended(p_pro_id) THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND status = 'approved' AND is_demo = false
  ) THEN
    RETURN false;
  END IF;
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.pro_id = p_pro_id AND b.client_id = v_user_id AND b.status = 'accepted'
      AND (p_offering_id IS NULL OR b.offering_id = p_offering_id)
      AND private.booking_last_day(b.session_id, b.end_day, b.day) < private.today_paris()
  );
END;
$function$;
GRANT EXECUTE ON FUNCTION public.can_add_community_photo(uuid, uuid) TO authenticated;

-- 00580 (VITRINE-7 / GRANTS-1): community files no photo row points to any
-- more (removed by the contributor, the pro or an admin; abandoned drafts;
-- refused additions), older than one hour (an addition may be under way).
-- Swept by the storage-cleanup edge function (service role) — no client can
-- delete a community file itself (00578: no swapping).
CREATE FUNCTION public.community_photo_orphans(p_limit integer DEFAULT 100)
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
  SELECT o.name
  FROM storage.objects o
  WHERE o.bucket_id = 'pro-photos'
    AND (storage.foldername(o.name))[2] = 'community'
    AND o.created_at < now() - INTERVAL '1 hour'
    AND NOT EXISTS (
      SELECT 1 FROM public.pro_community_photos p
      WHERE position('/pro-photos/' || o.name IN p.photo_url) > 0
    )
  ORDER BY o.created_at
  LIMIT least(greatest(coalesce(p_limit, 100), 1), 100);
$function$;
REVOKE ALL ON FUNCTION public.community_photo_orphans(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.community_photo_orphans(integer) TO service_role;

CREATE FUNCTION private.trigger_storage_cleanup()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE
  v_secret TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.community_photo_orphans(1)) THEN RETURN; END IF;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL OR private.project_url() IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(
    url := private.project_url() || '/functions/v1/storage-cleanup',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
END;
$function$;

SELECT cron.schedule('junto-storage-cleanup', '20 * * * *', 'SELECT private.trigger_storage_cleanup();');

CREATE OR REPLACE FUNCTION public.moderate_report(p_report_id uuid, p_action text, p_admin_note text DEFAULT NULL::text, p_suspend_user_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_report RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_action NOT IN ('dismissed', 'actioned') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, target_type, target_id INTO v_report FROM reports WHERE id = p_report_id;
  IF v_report IS NULL OR v_report.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE reports
  SET status = p_action, admin_note = p_admin_note, resolved_at = now()
  WHERE id = p_report_id;

  IF p_suspend_user_id IS NOT NULL AND p_action = 'actioned' THEN
    -- 00513 (ID-4): only the person the report is about can be suspended
    -- from it, through the full suspension path (reason, booking
    -- cancellations, notifications, log).
    IF p_suspend_user_id IS DISTINCT FROM (
      SELECT CASE v_report.target_type
        WHEN 'user' THEN v_report.target_id
        WHEN 'message' THEN (SELECT m.sender_id FROM messages m WHERE m.id = v_report.target_id)
        WHEN 'activity' THEN (SELECT a.creator_id FROM activities a WHERE a.id = v_report.target_id)
        WHEN 'pro_review' THEN (SELECT r.reviewer_id FROM pro_reviews r WHERE r.id = v_report.target_id)
        WHEN 'offering_review' THEN (SELECT r.reviewer_id FROM offering_reviews r WHERE r.id = v_report.target_id)
        WHEN 'group' THEN (SELECT c.created_by FROM conversations c WHERE c.id = v_report.target_id)
        WHEN 'channel' THEN (SELECT ch.created_by FROM channels ch WHERE ch.conversation_id = v_report.target_id)
        -- 00580 (VITRINE-6)
        WHEN 'pro_community_photo' THEN (SELECT ph.contributor_id FROM pro_community_photos ph WHERE ph.id = v_report.target_id)
      END) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    PERFORM admin_suspend_user(p_suspend_user_id, coalesce(nullif(trim(p_admin_note), ''), 'Signalement n° ' || p_report_id::text));
  END IF;

  PERFORM log_admin_action(
    v_user_id, 'moderate_report', 'report', p_report_id, p_admin_note,
    jsonb_build_object('action', p_action, 'suspended_user_id', p_suspend_user_id)
  );
END;
$function$;


-- ---------------------------------------------------------------------------
-- D. Blocking and bookings (BOOKINGS-R4)

CREATE OR REPLACE FUNCTION public.cascade_block_cleanup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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

  -- The organiser who blocks a requester refuses their pending request.
  UPDATE participations p
  SET status = 'refused', refused_at = now()
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND a.creator_id = NEW.blocker_id AND p.user_id = NEW.blocked_id;
  -- 00541: a requester who blocks the organiser withdraws their own request —
  -- a refusal would be recorded against them as the organiser's decision.
  UPDATE participations p
  SET status = 'withdrawn'
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND a.creator_id = NEW.blocked_id AND p.user_id = NEW.blocker_id;

  -- Cancel pending/accepted seat requests in both directions
  UPDATE seat_requests
  SET status = 'cancelled'
  WHERE status IN ('pending', 'accepted')
    AND ((requester_id = NEW.blocker_id AND driver_id = NEW.blocked_id)
      OR (requester_id = NEW.blocked_id AND driver_id = NEW.blocker_id));

  -- 00580 (BOOKINGS-R4): pending booking requests between the pair go,
  -- silently — withdrawn by the client who blocks, declined when the pro does.
  -- Accepted bookings stay (logistics); their notices lose the names.
  UPDATE bookings
  SET status = CASE WHEN client_id = NEW.blocker_id THEN 'cancelled' ELSE 'declined' END
  WHERE status = 'pending'
    AND ((client_id = NEW.blocker_id AND pro_id = NEW.blocked_id)
      OR (client_id = NEW.blocked_id AND pro_id = NEW.blocker_id));

  PERFORM set_config('junto.bypass_lock', 'false', true);  -- 00578 (T-BYPASS)
  RETURN NEW;
END;
$function$;


-- Requests already pending between a blocked pair.
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE public.bookings b
SET status = CASE WHEN EXISTS (SELECT 1 FROM public.blocked_users x
                               WHERE x.blocker_id = b.client_id AND x.blocked_id = b.pro_id)
                  THEN 'cancelled' ELSE 'declined' END
WHERE b.status = 'pending' AND b.client_id IS NOT NULL
  AND private.blocked_either_way(b.client_id, b.pro_id);
SELECT set_config('junto.bypass_lock', 'false', true);

CREATE OR REPLACE FUNCTION public.cancel_outing(p_offering_id uuid, p_day date, p_period text, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_title TEXT;
  v_pro_name TEXT;
  v_reason TEXT;
  v_bk RECORD;
  v_conversation_id UUID;
  v_done INTEGER := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00578 (T-REVOKED-CANCEL): like cancel_pro_session / cancel_booking_pro, a
  -- revoked pro keeps cancelling (clients must be told); suspension refused.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') OR p_day IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT title INTO v_title FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_day < private.today_paris() THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  v_reason := nullif(trim(regexp_replace(coalesce(p_reason, ''), '<[^>]*>', '', 'g')), '');
  IF v_reason IS NOT NULL AND char_length(v_reason) > 300 THEN
    RAISE EXCEPTION 'junto.outing_reason';
  END IF;

  -- 00578 (SESSIONS-5): the date's lock, like the other date writers —
  -- 00580 (BOOKINGS-R1): BEFORE the slot lock (date → slot everywhere).
  PERFORM pg_advisory_xact_lock(hashtext(s.id::text || '_session'))
  FROM pro_sessions s
  WHERE s.pro_id = v_user_id AND s.offering_id = p_offering_id
    AND s.start_day = p_day AND s.start_period = p_period AND s.status = 'scheduled';
  -- Same slot lock as accept_booking (00566): no accept slips in mid-cancel.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || p_day::text || p_period || '_slot'));
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
  -- 00575: cancelling the start half-day of a fixed date cancels the date.
  UPDATE pro_sessions SET status = 'cancelled', updated_at = now()
  WHERE pro_id = v_user_id AND offering_id = p_offering_id
    AND start_day = p_day AND start_period = p_period AND status = 'scheduled';
  -- 00577: a cancelled outing is no longer confirmed.
  DELETE FROM private.outing_confirmations
  WHERE session_id IS NULL AND offering_id = p_offering_id AND day = p_day AND period = p_period;

  FOR v_bk IN
    SELECT id, client_id, status FROM bookings
    WHERE pro_id = v_user_id AND offering_id = p_offering_id
      AND day = p_day AND period = p_period
      AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = CASE WHEN v_bk.status = 'accepted' THEN 'cancelled_pro' ELSE 'declined' END
    WHERE id = v_bk.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_done := v_done + 1;

    -- Manual booking: no one in the app — the pro calls them.
    CONTINUE WHEN v_bk.client_id IS NULL;

    -- The reason is the pro's own words: it goes into the private thread,
    -- never into a notification (push content rule).
    v_conversation_id := NULL;
    -- 00578 (T-OUTING-PENDING): the reason goes to accepted clients only — a
    -- pending request never opens a thread.
    IF v_reason IS NOT NULL AND v_bk.status = 'accepted'
       AND NOT EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL)
       AND NOT EXISTS (
         SELECT 1 FROM blocked_users
         WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
            OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
       ) THEN
      v_conversation_id := private.booking_dm(v_user_id, v_bk.client_id);
      PERFORM private.post_booking_dm(v_conversation_id, v_user_id, v_reason);
    END IF;

    -- 00580 (BOOKINGS-R4): blocked either way → the neutral notice, no name.
    IF v_bk.status = 'accepted' AND private.blocked_either_way(v_user_id, v_bk.client_id) THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        '« ' || coalesce(v_title, 'Ta sortie') || ' » du ' || to_char(p_day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'pro',
          'params', jsonb_build_object('title', coalesce(v_title, 'Ta sortie'), 'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    ELSIF v_bk.status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        coalesce(v_pro_name, 'Le professionnel') || ' a annulé « ' || coalesce(v_title, 'ta sortie')
          || ' » du ' || to_char(p_day, 'DD/MM') || '.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'pro',
          'variant', CASE WHEN v_conversation_id IS NOT NULL THEN 'by_pro_message' ELSE 'by_pro' END,
          'conversation_id', v_conversation_id,
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(v_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    ELSE
      PERFORM create_notification(
        v_bk.client_id,
        'booking_declined',
        'Créneau indisponible',
        coalesce(v_pro_name, 'Le professionnel') || ' n’est pas disponible pour « '
          || coalesce(v_title, 'ta sortie') || ' » le ' || to_char(p_day, 'DD/MM') || '.',
        jsonb_build_object('booking_id', v_bk.id, 'offering_id', p_offering_id,
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(v_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;

  RETURN v_done;
END;
$function$;

CREATE OR REPLACE FUNCTION private.cancel_session_bookings(p_pro uuid, p_session_id uuid, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_bk RECORD;
  v_title TEXT;
  v_pro_name TEXT;
  v_conversation_id UUID;
  v_n INTEGER := 0;
BEGIN
  SELECT po.title INTO v_title FROM pro_sessions s JOIN pro_offerings po ON po.id = s.offering_id WHERE s.id = p_session_id;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = p_pro;
  FOR v_bk IN
    SELECT id, client_id, day FROM bookings
    WHERE session_id = p_session_id AND status IN ('pending', 'accepted')
    FOR UPDATE
  LOOP
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings SET status = 'cancelled_pro' WHERE id = v_bk.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_n := v_n + 1;
    CONTINUE WHEN v_bk.client_id IS NULL;

    v_conversation_id := NULL;
    IF p_reason IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL)
       AND NOT EXISTS (
         SELECT 1 FROM blocked_users
         WHERE (blocker_id = p_pro AND blocked_id = v_bk.client_id)
            OR (blocker_id = v_bk.client_id AND blocked_id = p_pro)
       ) THEN
      v_conversation_id := private.booking_dm(p_pro, v_bk.client_id);
      PERFORM private.post_booking_dm(v_conversation_id, p_pro, p_reason);
    END IF;

    -- 00580 (BOOKINGS-R4): blocked either way → the neutral notice, no name.
    IF private.blocked_either_way(p_pro, v_bk.client_id) THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        '« ' || coalesce(v_title, 'Ta sortie') || ' » du ' || to_char(v_bk.day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'pro',
          'params', jsonb_build_object('title', coalesce(v_title, 'Ta sortie'), 'date', to_char(v_bk.day, 'YYYY-MM-DD')))
      );
      CONTINUE;
    END IF;
    PERFORM create_notification(
      v_bk.client_id,
      'booking_cancelled',
      'Sortie annulée',
      coalesce(v_pro_name, 'Le professionnel') || ' a annulé « ' || coalesce(v_title, 'ta sortie')
        || ' » du ' || to_char(v_bk.day, 'DD/MM') || '.',
      jsonb_build_object('booking_id', v_bk.id, 'by', 'pro',
        'variant', CASE WHEN v_conversation_id IS NOT NULL THEN 'by_pro_message' ELSE 'by_pro' END,
        'conversation_id', v_conversation_id,
        'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                     'title', coalesce(v_title, 'ta sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_booking_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_bk RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 18 THEN RETURN; END IF;

  FOR v_bk IN
    -- 00580 (BOOKINGS-R4): no pro name between a blocked pair.
    SELECT b.id, b.client_id, b.day, b.period, po.title,
           CASE WHEN private.blocked_either_way(b.pro_id, b.client_id) THEN NULL ELSE pp.display_name END AS pro_name,
           (coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
            + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
            AND private.filled_count(b.participant_info) < b.party_size) AS forms_missing
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    LEFT JOIN public_profiles pp ON pp.id = b.pro_id
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND b.day = private.today_paris() + 1
  LOOP
    PERFORM create_notification(
      v_bk.client_id,
      'booking_reminder',
      'C’est demain',
      '« ' || coalesce(v_bk.title, 'Ta sortie') || ' » demain, '
        || CASE v_bk.period WHEN 'am' THEN 'matin' ELSE 'après-midi' END
        || CASE WHEN v_bk.forms_missing THEN ' · pense à remplir tes fiches participants.' ELSE '.' END,
      jsonb_build_object('booking_id', v_bk.id,
        'variant', CASE WHEN v_bk.forms_missing THEN 'forms' WHEN v_bk.pro_name IS NULL THEN 'plain' ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_booking_forms_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_bk RECORD;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 18 THEN RETURN; END IF;

  FOR v_bk IN
    -- 00580 (BOOKINGS-R4): no pro name between a blocked pair.
    SELECT b.id, b.client_id, b.day, b.period, po.title,
           CASE WHEN private.blocked_either_way(b.pro_id, b.client_id) THEN NULL ELSE pp.display_name END AS pro_name
    FROM bookings b
    JOIN pro_offerings po ON po.id = b.offering_id
    LEFT JOIN public_profiles pp ON pp.id = b.pro_id
    WHERE b.status = 'accepted' AND b.client_id IS NOT NULL
      AND b.day = private.today_paris() + 3
      AND coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
          + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
      AND private.filled_count(b.participant_info) < b.party_size
  LOOP
    PERFORM create_notification(
      v_bk.client_id,
      'booking_forms_reminder',
      'Fiche du groupe à compléter',
      CASE WHEN v_bk.pro_name IS NULL THEN 'Remplis les infos de ton groupe pour « '
           ELSE v_bk.pro_name || ' attend les infos de ton groupe pour « ' END
        || coalesce(v_bk.title, 'ta sortie') || ' » (' || to_char(v_bk.day, 'DD/MM') || ').',
      jsonb_build_object('booking_id', v_bk.id,
        'variant', CASE WHEN v_bk.pro_name IS NULL THEN 'plain' ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
    );
  END LOOP;
END;
$function$;


-- ---------------------------------------------------------------------------
-- E + F. Sign-ups, invisible characters, lock order

CREATE OR REPLACE FUNCTION public.join_pro_session(p_session_id uuid, p_party_size integer, p_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_s RECORD;
  v_msg TEXT;
  v_taken INTEGER;
  v_existing RECORD;
  v_booking_id UUID;
  v_client_name TEXT;
  v_pro_name TEXT;
  v_conversation_id UUID;
  v_when TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00578 (SESSIONS-3): the date's lock before its row (order of cancel /
  -- update / the cron).
  PERFORM pg_advisory_xact_lock(hashtext(p_session_id::text || '_session'));

  SELECT s.*, po.title, po.price_eur AS o_price, po.price_unit::TEXT AS o_unit, pp.is_demo
    INTO v_s
  FROM pro_sessions s
  JOIN pro_offerings po ON po.id = s.offering_id
  JOIN pro_profiles pp ON pp.user_id = s.pro_id
  JOIN users u ON u.id = s.pro_id
  WHERE s.id = p_session_id
    AND pp.status = 'approved' AND u.tier = 'pro' AND u.suspended_at IS NULL
  FOR SHARE OF s;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_s.pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_s.is_demo = true AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_s.pro_id)
       OR (blocker_id = v_s.pro_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_s.status <> 'scheduled' OR private.session_started(v_s.start_day, v_s.start_period) THEN
    RAISE EXCEPTION 'junto.session_closed';
  END IF;
  -- 00578 (SESSIONS-4): instant sign-up, so one group is at most 6.
  IF p_party_size IS NULL OR p_party_size < 1 OR p_party_size > v_s.max_participants THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;
  -- 00580 (CLIENT-4): the 6-person cap has its own message.
  IF p_party_size > 6 THEN RAISE EXCEPTION 'junto.session_group_cap'; END IF;
  -- 00580 (BOOKINGS-R3): invisible characters out before the checks.
  v_msg := nullif(trim(private.strip_invisible(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'))), '');
  IF v_msg IS NOT NULL AND char_length(v_msg) > 500 THEN
    RAISE EXCEPTION 'junto.booking_message';
  END IF;

  -- Same per-client caps as create_booking.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND created_at > now() - INTERVAL '24 hours') >= 10 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;
  -- 00578 (SESSIONS-4): at most 3 upcoming sign-ups with the same pro.
  IF (SELECT count(*) FROM bookings b JOIN pro_sessions s ON s.id = b.session_id
      WHERE b.client_id = v_user_id AND b.pro_id = v_s.pro_id AND b.status = 'accepted'
        AND s.status = 'scheduled' AND s.end_day >= private.today_paris()
        AND b.session_id <> p_session_id) >= 3 THEN
    RAISE EXCEPTION 'junto.session_signup_cap';
  END IF;

  -- Already signed up: say so before « complet ».
  IF EXISTS (SELECT 1 FROM bookings WHERE session_id = p_session_id AND client_id = v_user_id
             AND status IN ('pending', 'accepted')) THEN
    RAISE EXCEPTION 'junto.booking_already';
  END IF;

  -- Places: the date is locked while counting, two sign-ups cannot overflow.
  PERFORM pg_advisory_xact_lock(hashtext(p_session_id::text || '_session'));
  SELECT coalesce(sum(party_size), 0)::INTEGER INTO v_taken
  FROM bookings WHERE session_id = p_session_id AND status = 'accepted';
  IF p_party_size > v_s.max_participants - v_taken THEN
    RAISE EXCEPTION 'junto.booking_full';
  END IF;

  -- One row per (offering, client, start half-day): a cancelled sign-up (or an
  -- old request on that half-day) is reactivated, with the anti-spam rules of
  -- create_booking.
  SELECT * INTO v_existing FROM bookings
  WHERE offering_id = v_s.offering_id AND client_id = v_user_id
    AND day = v_s.start_day AND period = v_s.start_period
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.status IN ('pending', 'accepted') THEN RAISE EXCEPTION 'junto.booking_already'; END IF;
    -- 00580 (SESSIONS-C): removed from THIS date by the pro — final.
    IF v_existing.status = 'cancelled_pro' AND v_existing.session_id = p_session_id THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00578 (T-COOLDOWN): a row closed by the pro (declined, cancelled by the
    -- pro, expired unanswered) is no client resubmission: no wait, not counted.
    IF v_existing.status NOT IN ('declined', 'cancelled_pro', 'expired')
       AND (v_existing.last_submitted_at > now() - INTERVAL '1 hour' OR v_existing.submitted_count >= 5) THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'accepted', session_id = p_session_id, end_day = NULL, party_size = p_party_size, message = v_msg,
        created_at = now(), price_eur = v_s.o_price, price_unit = v_s.o_unit,
        submitted_count = v_existing.submitted_count
          + CASE WHEN v_existing.status IN ('declined', 'cancelled_pro', 'expired') THEN 0 ELSE 1 END,
        last_submitted_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message,
                            status, session_id, price_eur, price_unit)
      VALUES (v_s.offering_id, v_s.pro_id, v_user_id, v_s.start_day, v_s.start_period, p_party_size, v_msg,
              'accepted', p_session_id, v_s.o_price, v_s.o_unit)
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  -- The logistic DM with the pro, opened like an accepted booking.
  v_when := CASE WHEN v_s.end_day > v_s.start_day
                 THEN 'du ' || to_char(v_s.start_day, 'DD/MM') || ' au ' || to_char(v_s.end_day, 'DD/MM')
                 ELSE 'le ' || to_char(v_s.start_day, 'DD/MM') || ' '
                      || CASE WHEN v_s.start_period <> v_s.end_period THEN 'journée'
                              WHEN v_s.start_period = 'am' THEN 'matin' ELSE 'après-midi' END
            END;
  v_conversation_id := private.booking_dm(v_s.pro_id, v_user_id);
  INSERT INTO messages (conversation_id, sender_id, content, metadata)
  VALUES (
    v_conversation_id, v_s.pro_id,
    '📆 Inscription confirmée — « ' || coalesce(v_s.title, 'Sortie') || ' », ' || v_when
      || ' (' || p_party_size || ' pers.). Paiement sur place.',
    jsonb_build_object('type', 'booking_accepted', 'booking_id', v_booking_id, 'offering_id', v_s.offering_id)
  );
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations SET last_message_at = now() WHERE id = v_conversation_id;
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_s.pro_id,
    'session_joined',
    'Nouvelle inscription',
    coalesce(v_client_name, 'Un membre') || ' · « ' || coalesce(v_s.title, 'ta sortie') || ' » · '
      || to_char(v_s.start_day, 'DD/MM') || ' · ' || p_party_size || ' pers.',
    jsonb_build_object('booking_id', v_booking_id, 'session_id', p_session_id,
      'params', jsonb_build_object('name', coalesce(v_client_name, 'Un membre'), 'title', coalesce(v_s.title, ''),
                                   'date', to_char(v_s.start_day, 'YYYY-MM-DD'), 'count', p_party_size))
  );

  -- 00577: this sign-up may reach the date's minimum.
  PERFORM private.mark_outing_confirmed(v_s.pro_id, v_s.offering_id, v_s.start_day, v_s.start_period,
                                        p_session_id, 'minimum');

  RETURN v_booking_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_msg TEXT;
  v_existing RECORD;
  v_booking_id UUID;
  v_client_name TEXT;
  v_end_day DATE;
  v_i INTEGER;
  v_d DATE;
  v_p TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT po.id, po.pro_id, po.title, po.max_participants, po.request_days, pp.is_demo
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

  -- 00577: by the day or over several days, the range is the server's:
  -- start morning → end_day afternoon.
  IF v_off.request_days IS NOT NULL THEN
    IF p_period <> 'am' THEN RAISE EXCEPTION 'junto.booking_slot_unavailable'; END IF;
    v_end_day := p_day + (v_off.request_days - 1);
  END IF;

  IF p_party_size IS NULL
     OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  -- Every half-day of the range: open in the agenda, not busy in the pro's
  -- own calendar (00568), outside a fixed date (00575), and with the places
  -- (00566: only ACCEPTED groups count, all offerings, now over their whole
  -- range — pending requests never block, the pro picks among them).
  FOR v_i IN private.half_idx(p_day, p_period) .. private.booking_end_idx(p_day, p_period, v_end_day) LOOP
    v_d := DATE '2000-01-01' + (v_i / 2);
    v_p := CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END;
    IF NOT EXISTS (
      SELECT 1 FROM pro_availabilities
      WHERE pro_id = v_off.pro_id AND day = v_d AND period = v_p
    ) OR EXISTS (
      SELECT 1 FROM private.pro_busy_slots
      WHERE pro_id = v_off.pro_id AND day = v_d AND period = v_p
    ) OR private.session_at(v_off.pro_id, v_d, v_p) IS NOT NULL THEN
      RAISE EXCEPTION 'junto.booking_slot_unavailable';
    END IF;
    IF v_off.max_participants IS NOT NULL
       AND p_party_size > v_off.max_participants - private.half_taken(v_off.pro_id, v_d, v_p) THEN
      RAISE EXCEPTION 'junto.booking_full';
    END IF;
  END LOOP;

  -- 00580 (BOOKINGS-R3): invisible characters out before the checks.
  v_msg := nullif(trim(private.strip_invisible(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'))), '');
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
        created_at = now(), end_day = v_end_day, session_id = NULL,
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
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, end_day, party_size, message, price_eur, price_unit)
      VALUES (p_offering_id, v_off.pro_id, v_user_id, p_day, p_period, v_end_day, p_party_size, v_msg,
              (SELECT o.price_eur FROM pro_offerings o WHERE o.id = p_offering_id),
              (SELECT o.price_unit::text FROM pro_offerings o WHERE o.id = p_offering_id))
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    v_off.pro_id,
    'booking_request',
    'Nouvelle demande de réservation',
    coalesce(v_client_name, 'Un membre') || ' · « ' || v_off.title || ' » · '
      || private.booking_when(p_day, p_period, v_end_day)
      || ' · ' || p_party_size || ' pers.',
    jsonb_build_object('booking_id', v_booking_id, 'offering_id', p_offering_id,
      'variant', CASE WHEN v_off.request_days = 1 THEN 'day' WHEN v_off.request_days > 1 THEN 'multi' END,
      'params', jsonb_build_object('name', coalesce(v_client_name, 'Un membre'), 'title', v_off.title,
                                   'date', to_char(p_day, 'YYYY-MM-DD'), 'period', p_period, 'count', p_party_size,
                                   'days', v_off.request_days))
  );

  RETURN v_booking_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_off RECORD;
  v_name TEXT;
  v_phone TEXT;
  v_booking_id UUID;
  v_sess RECORD;
  v_session_id UUID;
  v_period TEXT;
  v_end_day DATE;
  v_i INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT po.id, po.max_participants, po.request_days INTO v_off
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

  -- 00580 (BOOKINGS-R3): invisible characters out before the checks.
  v_name := nullif(trim(private.strip_invisible(regexp_replace(coalesce(p_name, ''), '<[^>]*>', '', 'g'))), '');
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

  -- 00577: an offering asked for by the day / over days covers the same range
  -- as a client's request (start morning → end_day afternoon).
  v_period := p_period;
  IF v_off.request_days IS NOT NULL THEN
    v_period := 'am';
    v_end_day := p_day + (v_off.request_days - 1);
  END IF;

  -- 00575: on a fixed date's half-days, a manual booking is a sign-up to that
  -- date (same offering, its start half-day, within its places) — never a
  -- second outing.
  v_session_id := private.session_at(v_user_id, p_day, v_period);
  IF v_session_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext(v_session_id::text || '_session'));
    -- 00578 (SESSIONS-5): re-read under the lock — the date may have just been cancelled.
    SELECT * INTO v_sess FROM pro_sessions WHERE id = v_session_id FOR UPDATE;
    IF v_sess.status <> 'scheduled' OR v_sess.offering_id <> p_offering_id OR v_sess.start_day <> p_day OR v_sess.start_period <> v_period
       OR private.session_started(v_sess.start_day, v_sess.start_period) THEN
      RAISE EXCEPTION 'junto.booking_slot_unavailable';
    END IF;
    IF p_party_size > v_sess.max_participants - coalesce((
         SELECT sum(b.party_size) FROM bookings b
         WHERE b.session_id = v_session_id AND b.status = 'accepted'), 0) THEN
      RAISE EXCEPTION 'junto.booking_full';
    END IF;
    v_end_day := NULL;  -- the date carries its own span
  ELSE
    -- 00578 (BOOKINGS-3): every half-day of the range locked first (ascending,
    -- like accept_booking), then checked.
    FOR v_i IN private.half_idx(p_day, v_period) .. private.booking_end_idx(p_day, v_period, v_end_day) LOOP
      PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || (DATE '2000-01-01' + (v_i / 2))::text
                                             || CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END || '_slot'));
    END LOOP;
    -- 00577: no half-day of the range inside a fixed date.
    FOR v_i IN private.half_idx(p_day, v_period) .. private.booking_end_idx(p_day, v_period, v_end_day) LOOP
      IF private.session_at(v_user_id, DATE '2000-01-01' + (v_i / 2),
                            CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END) IS NOT NULL THEN
        RAISE EXCEPTION 'junto.booking_slot_unavailable';
      END IF;
    END LOOP;
  END IF;

  INSERT INTO bookings (offering_id, pro_id, client_id, manual_name, manual_phone,
                        day, period, end_day, party_size, status, session_id)
  VALUES (p_offering_id, v_user_id, NULL, v_name, v_phone, p_day, v_period, v_end_day, p_party_size, 'accepted', v_session_id)
  RETURNING id INTO v_booking_id;

  -- 00577: these people may reach the outing's minimum.
  PERFORM private.mark_outing_confirmed(v_user_id, p_offering_id, p_day, v_period, v_session_id, 'minimum');
  -- 00578 (SESSIONS-2): adding people after the D-2 reminder maintains the outing.
  IF private.after_d2_reminder(p_day) THEN
    PERFORM private.mark_outing_confirmed(v_user_id, p_offering_id, p_day, v_period, v_session_id, 'pro');
  END IF;

  RETURN v_booking_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_suspend_user(p_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
  -- 00580 (BOOKINGS-R1): dates BEFORE their bookings, the order of
  -- cancel_pro_session.
  -- 00578 (SESSIONS-6): the suspended pro's upcoming and running dates close
  -- (their confirmations go with them, trigger pro_sessions_minimum_changed).
  UPDATE pro_sessions SET status = 'cancelled', updated_at = now()
  WHERE pro_id = p_user_id AND status = 'scheduled' AND end_day >= private.today_paris();

  FOR v_bk IN
    SELECT b.id AS b_id, b.pro_id AS b_pro, b.client_id AS b_client,
           b.status AS b_status, b.day AS b_day, po.title AS b_title
    FROM bookings b
    LEFT JOIN pro_offerings po ON po.id = b.offering_id
    WHERE (b.pro_id = p_user_id OR b.client_id = p_user_id)
      AND b.status IN ('pending', 'accepted')
      -- 00578 (SESSIONS-6): an outing still running counts (range or date end).
      AND private.booking_last_day(b.session_id, b.end_day, b.day) >= private.today_paris()
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
$function$;


-- ---------------------------------------------------------------------------
-- G. Hardening (GRANTS-2): visitors read activities through the definer view
-- activities_with_coords only — no column grant left on the base table.
REVOKE SELECT ON public.activities FROM anon;
DO $$
DECLARE c text;
BEGIN
  FOR c IN SELECT a.attname FROM pg_attribute a
           WHERE a.attrelid = 'public.activities'::regclass AND a.attnum > 0 AND NOT a.attisdropped
             AND a.attacl::text LIKE '%anon=%'
  LOOP
    EXECUTE format('REVOKE SELECT (%I) ON public.activities FROM anon', c);
  END LOOP;
END $$;
