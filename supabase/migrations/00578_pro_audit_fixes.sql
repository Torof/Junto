-- Pro audit fixes (audit 2026-11, docs/AUDIT_PRO_2026-11.md; rules validated
-- by Scott 2026-11-02). Every rebuilt function starts from its LIVE definition.
-- Ids in comments are the audit / test ids (supabase/tests known holes).

-- ---------------------------------------------------------------------------
-- 1. Data

-- SESSIONS-2: automatic cancellation becomes an explicit choice of the pro
-- (« Participants min » used to be information only).
ALTER TABLE public.pro_offerings ADD COLUMN auto_cancel boolean NOT NULL DEFAULT false;

CREATE OR REPLACE VIEW public.pro_offerings_with_coords AS
 SELECT o.id,
    o.pro_id,
    o.sport_id,
    o.title,
    o.description,
    o.level,
    o.location_name,
    o.duration,
    o.max_participants,
    o.schedule_text,
    o.distance_km,
    o.elevation_gain_m,
    o.cover_url AS image_url,
    o.created_at,
    o.updated_at,
    extensions.st_x(o.location::extensions.geometry) AS lng,
    extensions.st_y(o.location::extensions.geometry) AS lat,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    pp.display_name AS pro_name,
    o.price_eur,
    o.price_unit,
    o.min_participants,
    o.equipment_provided,
    o.equipment_required,
    o.participant_fields,
    o.request_days,
    o.auto_cancel
   FROM pro_offerings o
     JOIN sports s ON o.sport_id = s.id
     JOIN pro_profiles pp ON o.pro_id = pp.user_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM users u
          WHERE u.id = o.pro_id AND u.suspended_at IS NOT NULL)) AND (o.is_demo = false OR demo_content_visible()) AND (pp.status = 'approved'::text OR o.pro_id = auth.uid());

-- VITRINE-1: a community photo can be reported.
ALTER TABLE public.reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_target_type_check CHECK (target_type = ANY (ARRAY[
  'user'::text, 'activity'::text, 'pro_review'::text, 'offering_review'::text,
  'message'::text, 'group'::text, 'channel'::text, 'pro_community_photo'::text]));

-- VITRINE-1: a contributor cannot overwrite or delete-and-replace a file once
-- it can be a community photo (<uid>/community/…); covers and gallery keep
-- their own rules.
DROP POLICY pro_photos_update_own ON storage.objects;
CREATE POLICY pro_photos_update_own ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING (bucket_id = 'pro-photos'::text AND (storage.foldername(name))[1] = (auth.uid())::text
         AND (storage.foldername(name))[2] IS DISTINCT FROM 'community'
         AND NOT private.user_is_suspended(auth.uid()));
DROP POLICY pro_photos_delete_own ON storage.objects;
CREATE POLICY pro_photos_delete_own ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (bucket_id = 'pro-photos'::text AND (storage.foldername(name))[1] = (auth.uid())::text
         AND (storage.foldername(name))[2] IS DISTINCT FROM 'community');

-- ---------------------------------------------------------------------------
-- 2. Internal helpers (no grant)

-- Last day of a booking: its fixed date's end, its own range, or its day.
CREATE OR REPLACE FUNCTION private.booking_last_day(p_session uuid, p_end_day date, p_day date)
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce((SELECT s.end_day FROM pro_sessions s WHERE s.id = p_session), p_end_day, p_day)
$$;
REVOKE ALL ON FUNCTION private.booking_last_day(uuid, date, date) FROM PUBLIC, anon, authenticated;

-- CLIENT-1: participant forms filled = non-empty objects (a blank participant
-- keeps its place as {}).
CREATE OR REPLACE FUNCTION private.filled_count(p_info jsonb)
RETURNS integer LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT CASE WHEN p_info IS NULL OR jsonb_typeof(p_info) <> 'array' THEN 0
              ELSE (SELECT count(*)::integer FROM jsonb_array_elements(p_info) e
                    WHERE jsonb_typeof(e) = 'object' AND e <> '{}'::jsonb) END
$$;
REVOKE ALL ON FUNCTION private.filled_count(jsonb) FROM PUBLIC, anon, authenticated;

-- SESSIONS-2: the D-2 reminder of an outing starting on p_day went out at
-- 9h Paris two days before.
CREATE OR REPLACE FUNCTION private.after_d2_reminder(p_day date)
RETURNS boolean LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$ SELECT now() >= (((p_day - 2) + TIME '09:00') AT TIME ZONE 'Europe/Paris') $$;
REVOKE ALL ON FUNCTION private.after_d2_reminder(date) FROM PUBLIC, anon, authenticated;

-- A file of the caller's own folder under a given sub-folder (covers,
-- community photos), on top of the host / climbing checks of pro_photo_url_ok.
CREATE OR REPLACE FUNCTION private.pro_photo_in_folder(p_url text, p_uid uuid, p_sub text)
RETURNS boolean LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
  SELECT private.pro_photo_url_ok(p_url, p_uid)
     AND coalesce(p_url LIKE private.project_url() || '/storage/v1/object/public/pro-photos/'
                             || p_uid::text || '/' || p_sub || '/%', false)
$$;
REVOKE ALL ON FUNCTION private.pro_photo_in_folder(text, uuid, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Minimum (SESSIONS-1 / GRANTS-1, SESSIONS-2, T-SESSION-CONF)

-- An accepted booking leaving 'accepted' (client cancel, pro removal,
-- suspension, …): a 'minimum' confirmation falls when the outing is now short.
-- A 'pro' one (Maintenir, or acting after the D-2 reminder) stays.
CREATE OR REPLACE FUNCTION private.outing_recheck_on_leave()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_min INTEGER;
BEGIN
  IF OLD.status = 'accepted' AND NEW.status IS DISTINCT FROM 'accepted' THEN
    v_min := private.outing_min(NEW.offering_id, NEW.session_id);
    IF v_min IS NOT NULL
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
$$;
REVOKE ALL ON FUNCTION private.outing_recheck_on_leave() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER bookings_outing_recheck AFTER UPDATE OF status ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION private.outing_recheck_on_leave();

-- A date's minimum changed: confirmed when now reached, a 'minimum'
-- confirmation falls when no longer. A cancelled date loses its confirmations.
CREATE OR REPLACE FUNCTION private.session_minimum_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    DELETE FROM private.outing_confirmations WHERE session_id = NEW.id;
  ELSIF NEW.status = 'scheduled' AND NEW.min_participants IS DISTINCT FROM OLD.min_participants THEN
    IF NEW.min_participants IS NULL
       OR private.outing_total(NEW.offering_id, NEW.start_day, NEW.start_period, NEW.id) < NEW.min_participants THEN
      DELETE FROM private.outing_confirmations WHERE session_id = NEW.id AND reason = 'minimum';
    ELSE
      PERFORM private.mark_outing_confirmed(NEW.pro_id, NEW.offering_id, NEW.start_day, NEW.start_period, NEW.id, 'minimum');
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.session_minimum_changed() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER pro_sessions_minimum_changed AFTER UPDATE OF min_participants, status ON public.pro_sessions
  FOR EACH ROW EXECUTE FUNCTION private.session_minimum_changed();

-- Same for the on-request outings of an offering whose minimum changed.
CREATE OR REPLACE FUNCTION private.offering_minimum_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_o RECORD;
BEGIN
  IF NEW.min_participants IS NOT DISTINCT FROM OLD.min_participants THEN RETURN NULL; END IF;
  FOR v_o IN
    SELECT DISTINCT b.day, b.period FROM bookings b
    WHERE b.offering_id = NEW.id AND b.session_id IS NULL AND b.status = 'accepted'
      AND b.day >= private.today_paris()
  LOOP
    IF NEW.min_participants IS NULL
       OR private.outing_total(NEW.id, v_o.day, v_o.period, NULL) < NEW.min_participants THEN
      DELETE FROM private.outing_confirmations
      WHERE session_id IS NULL AND offering_id = NEW.id AND day = v_o.day AND period = v_o.period
        AND reason = 'minimum';
    ELSE
      PERFORM private.mark_outing_confirmed(NEW.pro_id, NEW.id, v_o.day, v_o.period, NULL, 'minimum');
    END IF;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.offering_minimum_changed() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER pro_offerings_minimum_changed AFTER UPDATE OF min_participants ON public.pro_offerings
  FOR EACH ROW EXECUTE FUNCTION private.offering_minimum_changed();

-- SESSIONS-2b: the opt-in.
CREATE OR REPLACE FUNCTION public.set_offering_auto_cancel(p_offering_id uuid, p_on boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);  -- includes suspension
  IF p_on IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  UPDATE pro_offerings SET auto_cancel = p_on WHERE id = p_offering_id AND pro_id = v_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.set_offering_auto_cancel(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_offering_auto_cancel(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_booking(p_booking_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
  v_max INTEGER;
  v_days INTEGER;
  v_i INTEGER;
  v_d DATE;
  v_p TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00418 : le verbe ACCEPT exige un pro encore approuvé (un pro révoqué garde
  -- cancel, perd accept) — inclut le check suspension.
  PERFORM private.assert_approved_pro(v_user_id);

  -- 00578 (BOOKINGS-2): read first, take the slot locks, THEN lock the row —
  -- the order of cancel_outing / the cron / session_check. day, period and
  -- end_day are pinned by the whitelist trigger.
  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id;
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

  -- 00566: no overbooking on accept. The slot locks (every half-day of the
  -- range, in order — 00577) serialise two accepts so they cannot both pass
  -- the count.
  FOR v_i IN private.half_idx(v_bk.day, v_bk.period) .. private.booking_end_idx(v_bk.day, v_bk.period, v_bk.end_day) LOOP
    v_d := DATE '2000-01-01' + (v_i / 2);
    v_p := CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END;
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || v_d::text || v_p || '_slot'));
  END LOOP;
  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  SELECT max_participants INTO v_max FROM pro_offerings WHERE id = v_bk.offering_id;
  FOR v_i IN private.half_idx(v_bk.day, v_bk.period) .. private.booking_end_idx(v_bk.day, v_bk.period, v_bk.end_day) LOOP
    v_d := DATE '2000-01-01' + (v_i / 2);
    v_p := CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END;
    -- 00575: the half-day now belongs to a fixed date.
    IF private.session_at(v_user_id, v_d, v_p) IS NOT NULL THEN
      RAISE EXCEPTION 'junto.booking_slot_unavailable';
    END IF;
    IF v_max IS NOT NULL AND v_bk.party_size + private.half_taken(v_user_id, v_d, v_p) > v_max THEN
      RAISE EXCEPTION 'junto.booking_full';
    END IF;
  END LOOP;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'accepted' WHERE id = p_booking_id AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
  v_days := CASE WHEN v_bk.end_day IS NOT NULL THEN v_bk.end_day - v_bk.day + 1 END;

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
    '📆 Réservation confirmée — « ' || coalesce(v_off_title, 'Sortie') || ' », '
      || private.booking_when(v_bk.day, v_bk.period, v_bk.end_day)
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
      || coalesce(v_off_title, 'ta sortie') || ' » '
      || private.booking_when(v_bk.day, v_bk.period, v_bk.end_day) || '. Paiement sur place.',
    jsonb_build_object('booking_id', v_bk.id, 'conversation_id', v_conversation_id,
      'variant', CASE WHEN v_days = 1 THEN 'day' WHEN v_days > 1 THEN 'multi' END,
      'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_off_title, 'ta sortie'),
                                   'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period, 'days', v_days))
  );

  -- 00577: this acceptance may reach the outing's minimum.
  PERFORM private.mark_outing_confirmed(v_user_id, v_bk.offering_id, v_bk.day, v_bk.period, NULL, 'minimum');
  -- 00578 (SESSIONS-2): accepting after the D-2 reminder maintains the outing.
  IF private.after_d2_reminder(v_bk.day) THEN
    PERFORM private.mark_outing_confirmed(v_user_id, v_bk.offering_id, v_bk.day, v_bk.period, NULL, 'pro');
  END IF;

  RETURN v_conversation_id;
END;
$function$;

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
  IF p_party_size IS NULL OR p_party_size < 1 OR p_party_size > LEAST(v_s.max_participants, 6) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;
  v_msg := nullif(regexp_replace(trim(coalesce(p_message, '')), '<[^>]*>', '', 'g'), '');
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

CREATE OR REPLACE FUNCTION public.create_pro_session(p_offering_id uuid, p_start_day date, p_start_period text, p_end_day date, p_end_period text, p_max_participants integer, p_min_participants integer DEFAULT NULL::integer, p_meeting_point text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_meeting TEXT;
  v_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);  -- includes suspension

  -- The offering cannot be deleted while its date is created.
  PERFORM 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_sessions'));
  PERFORM private.rate_hit('pro_session_create', 30, INTERVAL '1 day');
  IF (SELECT count(*) FROM pro_sessions
      WHERE pro_id = v_user_id AND status = 'scheduled' AND end_day >= private.today_paris()) >= 100 THEN
    RAISE EXCEPTION 'junto.session_cap';
  END IF;

  v_meeting := private.session_check(v_user_id, p_start_day, p_start_period, p_end_day, p_end_period,
                                     p_max_participants, p_min_participants, p_meeting_point, NULL);

  INSERT INTO pro_sessions (pro_id, offering_id, start_day, start_period, end_day, end_period,
                            max_participants, min_participants, meeting_point)
  VALUES (v_user_id, p_offering_id, p_start_day, p_start_period, p_end_day, p_end_period,
          p_max_participants, p_min_participants, v_meeting)
  RETURNING id INTO v_id;

  PERFORM private.decline_pending_in_range(v_user_id,
    private.half_idx(p_start_day, p_start_period), private.half_idx(p_end_day, p_end_period));

  -- 00578 (SESSIONS-2): a date posted after its D-2 reminder is maintained.
  IF private.after_d2_reminder(p_start_day) THEN
    PERFORM private.mark_outing_confirmed(v_user_id, p_offering_id, p_start_day, p_start_period, v_id, 'pro');
  END IF;

  RETURN v_id;
END;
$function$;

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

  -- Same slot lock as accept_booking (00566): no accept slips in mid-cancel.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || p_day::text || p_period || '_slot'));
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = v_user_id;
  -- 00578 (SESSIONS-5): the date's lock, like the other date writers.
  PERFORM pg_advisory_xact_lock(hashtext(s.id::text || '_session'))
  FROM pro_sessions s
  WHERE s.pro_id = v_user_id AND s.offering_id = p_offering_id
    AND s.start_day = p_day AND s.start_period = p_period AND s.status = 'scheduled';
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

    IF v_bk.status = 'accepted' THEN
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

CREATE OR REPLACE FUNCTION public.message_outing_clients(p_offering_id uuid, p_day date, p_period text, p_content text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_content TEXT;
  v_client UUID;
  v_conversation_id UUID;
  v_sent INTEGER := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') OR p_day IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00578 (BOOKINGS-1): up to 7 days after the outing's end, then closed.
  IF coalesce((SELECT max(private.booking_last_day(b.session_id, b.end_day, b.day)) FROM bookings b
               WHERE b.pro_id = v_user_id AND b.offering_id = p_offering_id
                 AND b.day = p_day AND b.period = p_period AND b.status = 'accepted'), p_day)
     < private.today_paris() - 7 THEN
    RAISE EXCEPTION 'junto.outing_closed';
  END IF;

  v_content := trim(regexp_replace(coalesce(p_content, ''), '<[^>]*>', '', 'g'));
  IF char_length(v_content) < 1 OR char_length(v_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.rate_hit('outing_broadcast', 20, INTERVAL '1 day');

  -- Confirmed in-app clients of the session only: a pending request does not
  -- get the meeting point. Suspended or blocked (either way) are skipped.
  FOR v_client IN
    SELECT DISTINCT b.client_id FROM bookings b
    JOIN users u ON u.id = b.client_id
    WHERE b.pro_id = v_user_id AND b.offering_id = p_offering_id
      AND b.day = p_day AND b.period = p_period
      AND b.status = 'accepted' AND b.client_id IS NOT NULL
      AND u.suspended_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users bu
        WHERE (bu.blocker_id = v_user_id AND bu.blocked_id = b.client_id)
           OR (bu.blocker_id = b.client_id AND bu.blocked_id = v_user_id)
      )
  LOOP
    v_conversation_id := private.booking_dm(v_user_id, v_client);
    PERFORM private.post_booking_dm(v_conversation_id, v_user_id, v_content);
    v_sent := v_sent + 1;
  END LOOP;

  RETURN v_sent;
END;
$function$;

CREATE OR REPLACE FUNCTION public.open_booking_conversation(p_booking_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_conversation_id UUID;
  v_u1 UUID;
  v_u2 UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Approved, non-suspended pro.
  PERFORM private.assert_approved_pro(v_user_id);

  SELECT id, pro_id, client_id, status, day, end_day, session_id INTO v_bk
  FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk.id IS NULL
     OR v_bk.pro_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted')
     OR v_bk.client_id IS NULL THEN   -- manual booking: no client in the app
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00578 (BOOKINGS-1): a request whose day is past, or an outing ended more
  -- than 7 days ago, no longer opens a thread.
  IF (v_bk.status = 'pending' AND v_bk.day < private.today_paris())
     OR (v_bk.status = 'accepted'
         AND private.booking_last_day(v_bk.session_id, v_bk.end_day, v_bk.day) < private.today_paris() - 7) THEN
    RAISE EXCEPTION 'junto.outing_closed';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_bk.client_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_bk.client_id)
       OR (blocker_id = v_bk.client_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE conversations
  SET status = 'active',
      initiated_from = CASE WHEN status != 'active' THEN 'booking' ELSE initiated_from END,
      request_sender_id = CASE WHEN status != 'active' THEN NULL ELSE request_sender_id END,
      request_message   = CASE WHEN status != 'active' THEN NULL ELSE request_message END,
      pending_activity_id = CASE WHEN status != 'active' THEN NULL ELSE pending_activity_id END,
      request_expires_at = CASE WHEN status != 'active' THEN NULL ELSE request_expires_at END
  WHERE id = v_conversation_id;
  -- The pro is about to write: their hidden copy comes back. The client's
  -- reappears with the first message, like any DM.
  UPDATE conversation_members SET hidden_at = NULL
  WHERE conversation_id = v_conversation_id AND user_id = v_user_id AND hidden_at IS NOT NULL;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN v_conversation_id;
END;
$function$;

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

  -- Validation (00578 : tableau vide accepté = fiche effacée) : tableau ≤ party_size ; par participant, un objet dont les
  -- clés ⊆ champs std demandés (valeurs texte ≤ 30) + 'custom' (objet
  -- question⊆demandées → réponse ≤ 120). Les valeurs sont stockées nettoyées
  -- (balises HTML et caractères de contrôle retirés, 00473 — audit L13).
  IF p_info IS NULL OR jsonb_typeof(p_info) != 'array'
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
    SELECT b.id, b.client_id, b.day, b.period, po.title, pp.display_name AS pro_name
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
      coalesce(v_bk.pro_name, 'Le professionnel') || ' attend les infos de ton groupe pour « '
        || coalesce(v_bk.title, 'ta sortie') || ' » (' || to_char(v_bk.day, 'DD/MM') || ').',
      jsonb_build_object('booking_id', v_bk.id,
        'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
    );
  END LOOP;
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
    SELECT b.id, b.client_id, b.day, b.period, po.title, pp.display_name AS pro_name,
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
        'variant', CASE WHEN v_bk.forms_missing THEN 'forms' ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_bk.title, ''), 'name', coalesce(v_bk.pro_name, ''),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD'), 'period', v_bk.period))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.notify_booking_forms_missing()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_row RECORD;
  v_min_low BOOLEAN;
  v_body TEXT;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN; END IF;

  FOR v_row IN
    WITH outings AS (
      SELECT b.pro_id, b.offering_id, b.day, b.period, b.session_id,
             sum(CASE WHEN coalesce(jsonb_array_length(po.participant_fields -> 'std'), 0)
                         + coalesce(jsonb_array_length(po.participant_fields -> 'custom'), 0) > 0
                      THEN greatest(b.party_size - private.filled_count(b.participant_info), 0)
                      ELSE 0 END)::INTEGER AS missing,
             sum(b.party_size)::INTEGER AS total
      FROM bookings b
      JOIN pro_offerings po ON po.id = b.offering_id
      WHERE b.status = 'accepted' AND b.day = private.today_paris() + 2
      GROUP BY b.pro_id, b.offering_id, b.day, b.period, b.session_id
    ), sess AS (
      SELECT s.id, s.pro_id, s.offering_id, s.start_day AS day, s.start_period AS period, s.min_participants
      FROM pro_sessions s
      WHERE s.status = 'scheduled' AND s.start_day = private.today_paris() + 2
        AND s.min_participants IS NOT NULL
    ), joined AS (
      SELECT coalesce(o.pro_id, s.pro_id) AS pro_id, coalesce(o.offering_id, s.offering_id) AS offering_id,
             coalesce(o.day, s.day) AS day, coalesce(o.period, s.period) AS period,
             coalesce(s.id, o.session_id) AS session_id,
             coalesce(o.missing, 0) AS missing, coalesce(o.total, 0) AS total,
             coalesce(s.min_participants, CASE WHEN o.session_id IS NULL THEN po.min_participants END) AS min,
             po.title, po.auto_cancel
      FROM outings o
      FULL JOIN sess s ON s.id = o.session_id
      JOIN pro_offerings po ON po.id = coalesce(o.offering_id, s.offering_id)
    )
    SELECT j.*,
           (j.min IS NOT NULL AND j.total < j.min
            AND NOT private.outing_confirmed(j.offering_id, j.day, j.period, j.session_id)) AS is_short
    FROM joined j
  LOOP
    v_min_low := v_row.is_short;
    CONTINUE WHEN v_row.missing = 0 AND NOT v_min_low;
    v_body := '« ' || coalesce(v_row.title, 'Ta sortie') || ' » (' || to_char(v_row.day, 'DD/MM') || ') : ';
    IF v_row.missing > 0 THEN
      v_body := v_body || v_row.missing || ' fiche' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' participant' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END
        || ' manquante' || CASE WHEN v_row.missing > 1 THEN 's' ELSE '' END;
      IF v_min_low THEN v_body := v_body || ', et ';
      ELSE v_body := v_body || ' sur ' || v_row.total; END IF;
    END IF;
    IF v_min_low THEN
      -- 00578 (SESSIONS-2): « annulée demain » only when the pro chose it.
      v_body := v_body || v_row.total || '/' || v_row.min || ' inscrits'
        || CASE WHEN v_row.auto_cancel THEN '. Maintiens-la, sinon elle sera annulée demain à 9 h'
                ELSE ', minimum ' || v_row.min || ' pour partir' END;
    END IF;
    PERFORM create_notification(
      v_row.pro_id,
      'booking_forms_missing',
      CASE WHEN v_row.missing > 0 THEN 'Il manque des infos' ELSE 'Minimum pas atteint' END,
      v_body || '.',
      jsonb_build_object('offering_id', v_row.offering_id,
        'variant', CASE WHEN v_min_low AND v_row.missing > 0 THEN CASE WHEN v_row.auto_cancel THEN 'both_auto' ELSE 'both' END
                        WHEN v_min_low THEN CASE WHEN v_row.auto_cancel THEN 'minimum_auto' ELSE 'minimum' END
                        ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_row.title, ''), 'date', to_char(v_row.day, 'YYYY-MM-DD'),
                                     'period', v_row.period, 'count', v_row.missing, 'total', v_row.total,
                                     'min', v_row.min))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.auto_cancel_short_outings()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_tomorrow DATE;
  v_s RECORD;
  v_o RECORD;
  v_total INTEGER;
  v_n INTEGER := 0;
BEGIN
  IF extract(hour FROM now() AT TIME ZONE 'Europe/Paris') <> 9 THEN RETURN 0; END IF;
  v_tomorrow := private.today_paris() + 1;

  -- Fixed dates. 00578: only offerings whose pro chose automatic cancellation
  -- (SESSIONS-2b); each outing in its own sub-transaction, so one failure
  -- (deadlock, …) never rolls back the day's run (SESSIONS-3).
  FOR v_s IN
    SELECT s.id, s.pro_id, s.offering_id, s.start_day, s.start_period, s.min_participants, po.title
    FROM pro_sessions s JOIN pro_offerings po ON po.id = s.offering_id
    WHERE s.status = 'scheduled' AND s.start_day = v_tomorrow AND s.min_participants IS NOT NULL
      AND po.auto_cancel
    ORDER BY s.id
  LOOP
    BEGIN
      PERFORM pg_advisory_xact_lock(hashtext(v_s.id::text || '_session'));
      v_total := private.outing_total(v_s.offering_id, v_s.start_day, v_s.start_period, v_s.id);
      CONTINUE WHEN v_total >= v_s.min_participants
                 OR private.outing_confirmed(v_s.offering_id, v_s.start_day, v_s.start_period, v_s.id);
      UPDATE pro_sessions SET status = 'cancelled', updated_at = now()
      WHERE id = v_s.id AND status = 'scheduled';
      CONTINUE WHEN NOT FOUND;
      PERFORM private.auto_cancel_outing_bookings(v_s.pro_id, v_s.offering_id, v_s.start_day, v_s.start_period,
                                                  v_s.id, v_s.title);
      PERFORM private.notify_outing_auto_cancelled(v_s.pro_id, v_s.offering_id, v_s.start_day, v_s.start_period,
                                                   v_s.title, v_total, v_s.min_participants);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_cancel_short_outings: date % skipped (%)', v_s.id, SQLERRM;
    END;
  END LOOP;

  -- On request: the accepted bookings of an offering at a start half-day.
  -- Ordered by pro then half-day so the slot locks are taken in the same
  -- order as accept_booking's.
  FOR v_o IN
    SELECT b.pro_id, b.offering_id, b.day, b.period, po.title, po.min_participants
    FROM bookings b JOIN pro_offerings po ON po.id = b.offering_id
    WHERE b.status = 'accepted' AND b.session_id IS NULL AND b.day = v_tomorrow
      AND po.min_participants IS NOT NULL AND po.auto_cancel
    GROUP BY b.pro_id, b.offering_id, b.day, b.period, po.title, po.min_participants
    ORDER BY b.pro_id, b.day, b.period, b.offering_id
  LOOP
    BEGIN
      PERFORM pg_advisory_xact_lock(hashtext(v_o.pro_id::text || v_o.day::text || v_o.period || '_slot'));
      v_total := private.outing_total(v_o.offering_id, v_o.day, v_o.period, NULL);
      CONTINUE WHEN v_total = 0 OR v_total >= v_o.min_participants
                 OR private.outing_confirmed(v_o.offering_id, v_o.day, v_o.period, NULL);
      PERFORM private.auto_cancel_outing_bookings(v_o.pro_id, v_o.offering_id, v_o.day, v_o.period,
                                                  NULL, v_o.title);
      PERFORM private.notify_outing_auto_cancelled(v_o.pro_id, v_o.offering_id, v_o.day, v_o.period,
                                                   v_o.title, v_total, v_o.min_participants);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'auto_cancel_short_outings: outing % % % skipped (%)', v_o.offering_id, v_o.day, v_o.period, SQLERRM;
    END;
  END LOOP;

  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION private.auto_cancel_short_outings() FROM PUBLIC, anon, authenticated;

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
  -- 00578 (SESSIONS-6): the suspended pro's upcoming and running dates close
  -- (their confirmations go with them, trigger pro_sessions_minimum_changed).
  UPDATE pro_sessions SET status = 'cancelled', updated_at = now()
  WHERE pro_id = p_user_id AND status = 'scheduled' AND end_day >= private.today_paris();
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM log_admin_action(v_admin, 'suspend_user', 'user', p_user_id, v_reason, NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_pro_review(p_pro_id uuid, p_rating smallint, p_body text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
  v_reviewer_name TEXT;
  v_pro_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = p_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00443 B5 : cible démo refusée (même erreur générique qu'inexistante).
  -- 00505 (B8): only an approved pro can be reviewed (same generic error).
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_pro_id AND is_demo = false AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = p_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00554: a review needs a booking with this pro, accepted and already past.
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.pro_id = p_pro_id AND b.client_id = v_user_id
      AND b.status = 'accepted'
      -- 00578 (VITRINE-3): the outing is over (multi-day range, fixed date end).
      AND private.booking_last_day(b.session_id, b.end_day, b.day) < private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.review_requires_booking';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM pro_reviews WHERE pro_id = p_pro_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'junto.review_duplicate';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.review_rate_limit'; END IF;

  BEGIN
    INSERT INTO pro_reviews (pro_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_pro_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  SELECT display_name INTO v_pro_name FROM pro_profiles WHERE user_id = p_pro_id;
  PERFORM notify_review_received(
    p_pro_id,
    v_reviewer_name,
    p_rating,
    v_pro_name,
    jsonb_build_object('pro_id', p_pro_id, 'review_id', v_review_id, 'reviewer_id', v_user_id)
  );

  RETURN v_review_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_offering_review(p_offering_id uuid, p_rating smallint, p_body text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_pro_id UUID;
  v_body TEXT;
  v_daily_count INTEGER;
  v_review_id UUID;
  v_reviewer_name TEXT;
  v_offering_title TEXT;
  v_is_demo BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT o.pro_id, o.title, o.is_demo INTO v_pro_id, v_offering_title, v_is_demo FROM pro_offerings o
  WHERE o.id = p_offering_id
    -- 00505 (B8): an approved pro's offering only.
    AND EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = o.pro_id AND pp.status = 'approved');
  -- 00443 B5 : offre démo refusée (même erreur générique qu'inexistante).
  IF v_pro_id IS NULL OR v_is_demo THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00501 (PO-4): someone the pro has blocked cannot post on their page.
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_pro_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_pro_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00554: a review needs a booking of this offering, accepted and already past.
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.offering_id = p_offering_id AND b.client_id = v_user_id
      AND b.status = 'accepted'
      -- 00578 (VITRINE-3): the outing is over (multi-day range, fixed date end).
      AND private.booking_last_day(b.session_id, b.end_day, b.day) < private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.review_requires_booking';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_body IS NOT NULL THEN
    v_body := trim(regexp_replace(p_body, '<[^>]*>', '', 'g'));
    IF char_length(v_body) = 0 THEN v_body := NULL; END IF;
    IF v_body IS NOT NULL AND char_length(v_body) > 1000 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reviews'));

  IF EXISTS (
    SELECT 1 FROM offering_reviews WHERE offering_id = p_offering_id AND reviewer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'junto.review_duplicate';
  END IF;

  SELECT (
    (SELECT count(*) FROM pro_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
    +
    (SELECT count(*) FROM offering_reviews
     WHERE reviewer_id = v_user_id AND created_at > NOW() - INTERVAL '24 hours')
  ) INTO v_daily_count;

  IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.review_rate_limit'; END IF;

  BEGIN
    INSERT INTO offering_reviews (offering_id, reviewer_id, rating, body, created_at, updated_at)
    VALUES (p_offering_id, v_user_id, p_rating, v_body, now(), now())
    RETURNING id INTO v_review_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Operation not permitted';
  END;

  SELECT display_name INTO v_reviewer_name FROM users WHERE id = v_user_id;
  PERFORM notify_review_received(
    v_pro_id,
    v_reviewer_name,
    p_rating,
    v_offering_title,
    jsonb_build_object('offering_id', p_offering_id, 'review_id', v_review_id, 'reviewer_id', v_user_id)
  );

  RETURN v_review_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_pro_cover(p_url text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- NULL retire ; sinon URL ancrée au dossier du caller.
  -- 00578 (VITRINE-4): a photo of the own gallery, or a file of the own
  -- cover folder (cover picked from the phone).
  IF p_url IS NOT NULL AND NOT (
       (private.pro_photo_url_ok(p_url, v_user_id)
        AND EXISTS (SELECT 1 FROM pro_profile_photos WHERE pro_id = v_user_id AND photo_url = p_url))
       OR private.pro_photo_in_folder(p_url, v_user_id, 'cover')) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET cover_url = p_url WHERE user_id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_offering_cover(p_offering_id uuid, p_url text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00578 (VITRINE-4): a photo of this offering's gallery, or a file of its
  -- own cover folder (cover picked from the phone).
  IF p_url IS NOT NULL AND NOT (
       (private.pro_photo_url_ok(p_url, v_user_id)
        AND EXISTS (SELECT 1 FROM pro_offering_photos WHERE offering_id = p_offering_id AND photo_url = p_url))
       OR private.pro_photo_in_folder(p_url, v_user_id, 'offering/' || p_offering_id::text || '/cover')) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_offerings SET cover_url = p_url WHERE id = p_offering_id AND pro_id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_pro_community_photo(p_pro_id uuid, p_photo_url text, p_review_id uuid DEFAULT NULL::uuid, p_offering_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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

  -- 00578 (VITRINE-1): like a review, it needs an accepted booking with this
  -- pro (this offering when given) whose outing is over.
  IF NOT EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.pro_id = p_pro_id AND b.client_id = v_user_id AND b.status = 'accepted'
      AND (p_offering_id IS NULL OR b.offering_id = p_offering_id)
      AND private.booking_last_day(b.session_id, b.end_day, b.day) < private.today_paris()
  ) THEN
    RAISE EXCEPTION 'junto.review_requires_booking';
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

CREATE OR REPLACE FUNCTION public.create_report(p_target_type text, p_target_id uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_target_type NOT IN ('user', 'activity',
                           'pro_review', 'offering_review', 'message', 'group', 'channel',
                           'pro_community_photo') THEN  -- 00578 (VITRINE-1)
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := regexp_replace(trim(p_reason), '<[^>]*>', '', 'g');
  IF char_length(v_reason) < 10 THEN RAISE EXCEPTION 'junto.report_reason_too_short'; END IF;

  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Existence checks. 'message' / 'group' hit the unified store; the reporter
  -- must be a member of the conversation the content lives in (no probing).
  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00535: an outing one cannot see is answered like an unknown one.
  IF p_target_type = 'activity' AND NOT private.can_see_activity(p_target_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'message' AND NOT EXISTS (
    -- 00499 (MS-8): a message deleted by its author stays reportable by a
    -- member (deleting abuse right after sending it must not dodge a report).
    SELECT 1 FROM messages m
    WHERE m.id = p_target_id
      AND private.is_conversation_member(m.conversation_id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'group' AND NOT EXISTS (
    SELECT 1 FROM conversations c
    WHERE c.id = p_target_id AND c.type = 'group'
      AND private.is_conversation_member(c.id, v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'channel' AND NOT EXISTS (
    SELECT 1 FROM conversations c WHERE c.id = p_target_id AND c.type = 'channel'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_target_type = 'pro_review' AND NOT EXISTS (SELECT 1 FROM pro_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'offering_review' AND NOT EXISTS (SELECT 1 FROM offering_reviews WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'pro_community_photo' AND NOT EXISTS (SELECT 1 FROM pro_community_photos WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00520: serialised per reporter (and a unique index backs it).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_report'));
  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN RAISE EXCEPTION 'junto.report_already_filed'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));
  SELECT count(*) INTO v_hourly_count FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.report_rate_limit'; END IF;

  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, v_reason, 'pending', now())
  RETURNING id INTO v_report_id;
  RETURN v_report_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_remove_content(p_target_type text, p_target_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_found BOOLEAN := false;
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

  IF p_target_type NOT IN ('activity', 'message', 'group', 'channel', 'pro_review', 'offering_review',
                           'pro_community_photo') THEN  -- 00578 (VITRINE-1)
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  IF p_target_type = 'activity' THEN
    UPDATE activities SET deleted_at = now(), updated_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'message' THEN
    -- Unified store: reads come from `messages`. 'wall_message' kept for
    -- migrated ids (id is shared), 'message' for post-rebuild content.
    UPDATE messages SET deleted_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'group' THEN
    UPDATE conversations SET name = '[Groupe retiré]', icon = NULL, moderated_at = now()
    WHERE id = p_target_id AND type = 'group';
    v_found := FOUND;
  ELSIF p_target_type = 'channel' THEN
    -- 00507: a reported channel is closed (read-only, out of search).
    UPDATE channels SET closed_at = now()
    WHERE conversation_id = p_target_id AND closed_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'pro_review' THEN
    DELETE FROM pro_reviews WHERE id = p_target_id;
    v_found := FOUND;
  ELSIF p_target_type = 'offering_review' THEN
    DELETE FROM offering_reviews WHERE id = p_target_id;
    v_found := FOUND;
  ELSIF p_target_type = 'pro_community_photo' THEN
    DELETE FROM pro_community_photos WHERE id = p_target_id;
    v_found := FOUND;
  END IF;

  IF NOT v_found THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM log_admin_action(v_admin, 'remove_content', p_target_type, p_target_id, v_reason, NULL);
END;
$function$;

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
  -- 00578 (CALENDAR-4): the export token and the import go too — a return
  -- as pro gets a fresh link, never the old one.
  DELETE FROM private.pro_busy_slots WHERE pro_id = v_user_id;
  DELETE FROM private.pro_calendar_links WHERE pro_id = v_user_id;
  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calendar_import_targets()
 RETURNS TABLE(pro_id uuid, import_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT l.pro_id, l.import_url
  FROM private.pro_calendar_links l
  JOIN pro_profiles pp ON pp.user_id = l.pro_id AND pp.status = 'approved'
  JOIN users u ON u.id = l.pro_id AND u.suspended_at IS NULL AND u.tier = 'pro'  -- 00578 (T-CAL-TIER)
  WHERE l.import_url IS NOT NULL AND private.calendar_import_host_ok(l.import_url);
$function$;

-- 00578 (CALENDAR-5): the address that was read comes back with the result;
-- a result for an address the pro has since changed is dropped. Impossible
-- dates are skipped instead of failing the whole batch (T-CAL-DATE).
DROP FUNCTION public.calendar_import_apply(uuid, jsonb, text);
CREATE FUNCTION public.calendar_import_apply(p_pro uuid, p_slots jsonb, p_error text, p_url text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.pro_calendar_links
    WHERE pro_id = p_pro AND import_url IS NOT NULL
      AND (p_url IS NULL OR import_url = p_url)
  ) THEN
    RETURN;  -- unplugged or changed meanwhile
  END IF;
  IF p_error IS NOT NULL THEN
    UPDATE private.pro_calendar_links SET import_error = left(p_error, 200) WHERE pro_id = p_pro;
    RETURN;
  END IF;
  IF p_slots IS NULL OR jsonb_typeof(p_slots) <> 'array' OR jsonb_array_length(p_slots) > 400 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  DELETE FROM private.pro_busy_slots WHERE pro_id = p_pro;
  INSERT INTO private.pro_busy_slots (pro_id, day, period)
  SELECT DISTINCT p_pro, d.day, d.period
  FROM (
    SELECT private.try_date(s ->> 'day') AS day, s ->> 'period' AS period
    FROM jsonb_array_elements(p_slots) s
    WHERE s ->> 'period' IN ('am', 'pm')
  ) d
  WHERE d.day BETWEEN private.today_paris() AND private.today_paris() + 190;
  UPDATE private.pro_calendar_links SET import_synced_at = now(), import_error = NULL WHERE pro_id = p_pro;
END;
$$;
REVOKE ALL ON FUNCTION public.calendar_import_apply(uuid, jsonb, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calendar_import_apply(uuid, jsonb, text, text) TO service_role;

-- 'YYYY-MM-DD' → date, NULL when malformed or impossible.
CREATE OR REPLACE FUNCTION private.try_date(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE
SET search_path = public, extensions
AS $$
BEGIN
  IF p IS NULL OR p !~ '^\d{4}-\d{2}-\d{2}$' THEN RETURN NULL; END IF;
  RETURN p::date;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.try_date(text) FROM PUBLIC, anon, authenticated;

-- 00578 (CALENDAR-1): one call per pro — a heavy or broken calendar never
-- stops the others.
CREATE OR REPLACE FUNCTION private.trigger_calendar_import()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret TEXT;
  v_pro UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.pro_calendar_links WHERE import_url IS NOT NULL) THEN RETURN; END IF;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL OR private.project_url() IS NULL THEN RETURN; END IF;
  FOR v_pro IN SELECT t.pro_id FROM public.calendar_import_targets() t LOOP
    PERFORM net.http_post(
      url := private.project_url() || '/functions/v1/calendar-import',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
      body := jsonb_build_object('pro_id', v_pro),
      timeout_milliseconds := 60000
    );
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION private.trigger_calendar_import() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_calendar_import_url(p_url text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_url TEXT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  PERFORM private.ensure_calendar_link(v_user_id);

  v_url := nullif(trim(coalesce(p_url, '')), '');
  IF v_url IS NULL THEN
    -- Unplugging also forgets the busy half-days it produced.
    UPDATE private.pro_calendar_links
    SET import_url = NULL, import_synced_at = NULL, import_error = NULL
    WHERE pro_id = v_user_id;
    DELETE FROM private.pro_busy_slots WHERE pro_id = v_user_id;
    RETURN;
  END IF;

  -- 00578 (T-CAL-UNPLUG): unplugging never counts, only setting an address.
  PERFORM private.rate_hit('calendar_import_set', 10, INTERVAL '1 day');

  v_url := regexp_replace(v_url, '^webcals?://', 'https://', 'i');
  IF char_length(v_url) > 500 OR v_url ~ '\s' OR NOT private.calendar_import_host_ok(v_url) THEN
    RAISE EXCEPTION 'junto.calendar_url';
  END IF;

  UPDATE private.pro_calendar_links
  SET import_url = v_url, import_synced_at = NULL, import_error = NULL
  WHERE pro_id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calendar_feed_bookings(p_token text)
 RETURNS TABLE(id uuid, day date, period text, status text, offering_title text, party_size integer, client_name text, is_manual boolean, hide_names boolean, kind text, end_day date, end_period text, max_participants integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_link RECORD;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RETURN; END IF;
  SELECT l.pro_id, l.hide_names INTO v_link
  FROM private.pro_calendar_links l
  JOIN pro_profiles pp ON pp.user_id = l.pro_id AND pp.status = 'approved'
  JOIN users u ON u.id = l.pro_id AND u.suspended_at IS NULL AND u.tier = 'pro'
  WHERE l.export_token = p_token;
  IF v_link.pro_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT b.id, b.day, b.period, b.status, po.title, b.party_size,
         -- 00578 (T-CAL-NAMES): hidden here too, not only in the edge function.
         CASE WHEN v_link.hide_names THEN NULL ELSE coalesce(pp.display_name, b.manual_name) END,
         (b.client_id IS NULL), v_link.hide_names,
         'booking'::TEXT, coalesce(b.end_day, b.day),
         CASE WHEN b.end_day IS NOT NULL THEN 'pm' ELSE b.period END, NULL::INTEGER
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_link.pro_id
    AND b.session_id IS NULL
    AND b.status IN ('pending', 'accepted')
    AND coalesce(b.end_day, b.day) >= private.today_paris() - 31
    AND b.day <= private.today_paris() + 190
  UNION ALL
  SELECT s.id, s.start_day, s.start_period, s.status, po.title,
         coalesce((SELECT sum(b.party_size) FROM bookings b
                   WHERE b.session_id = s.id AND b.status = 'accepted'), 0)::INTEGER,
         NULL::TEXT, false, v_link.hide_names,
         'session'::TEXT, s.end_day, s.end_period, s.max_participants
  FROM pro_sessions s
  JOIN pro_offerings po ON po.id = s.offering_id
  WHERE s.pro_id = v_link.pro_id AND s.status = 'scheduled'
    AND s.end_day >= private.today_paris() - 31
    AND s.start_day <= private.today_paris() + 190
  ORDER BY 2, 3;
END;
$function$;

DROP FUNCTION public.set_gpx_trace_waypoints(uuid, jsonb);
CREATE FUNCTION public.set_gpx_trace_waypoints(p_id uuid, p_waypoints jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_geojson JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('gpx_waypoints', 60, INTERVAL '1 hour');

  -- Ownership: exists AND mine. Generic error either way.
  SELECT geojson INTO v_geojson FROM gpx_traces WHERE id = p_id AND user_id = v_user_id FOR UPDATE;
  IF v_geojson IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_geojson := v_geojson - 'waypoints';
  IF p_waypoints IS NOT NULL AND jsonb_typeof(p_waypoints) = 'array' AND jsonb_array_length(p_waypoints) > 0 THEN
    v_geojson := v_geojson || jsonb_build_object('waypoints', p_waypoints);
  ELSIF p_waypoints IS NOT NULL AND jsonb_typeof(p_waypoints) <> 'array' THEN
    RETURN 'junto.trace_geojson_invalid';
  END IF;
  -- Same gate as every trace path (00570). 00578 (DB-WP-1): REPORTED, not
  -- raised, so the call stays counted in the frequency (like 00483).
  IF NOT trace_geojson_ok(v_geojson) THEN RETURN 'junto.trace_geojson_invalid'; END IF;

  UPDATE gpx_traces SET geojson = v_geojson, updated_at = now()
  WHERE id = p_id AND user_id = v_user_id;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.set_gpx_trace_waypoints(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_gpx_trace_waypoints(uuid, jsonb) TO authenticated;

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

  PERFORM set_config('junto.bypass_lock', 'false', true);  -- 00578 (T-BYPASS)
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_pro_application()
 RETURNS TABLE(user_id uuid, display_name text, company_name text, real_name text, tagline text, description text, website text, email text, phone text, instagram text, facebook text, primary_lng double precision, primary_lat double precision, primary_location_name text, pin_image_url text, pin_icon text, status text, rejection_reason text, last_location_change_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone, profession text, featured_offering_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF private.user_is_suspended(v_user_id) THEN RETURN; END IF;  -- 00578

  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.tagline, pp.description, pp.website, pp.email, pp.phone,
         pp.instagram, pp.facebook,
         pp.primary_lng, pp.primary_lat, pp.primary_location_name,
         pp.pin_image_url, pp.pin_icon,
         pp.status, pp.rejection_reason,
         pp.last_location_change_at, pp.created_at, pp.updated_at,
         pp.profession, pp.featured_offering_id
  FROM pro_profiles pp
  WHERE pp.user_id = v_user_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Grants hardening

-- CALENDAR-7: the network extension is for the database only.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA net FROM PUBLIC, anon, authenticated;
REVOKE USAGE ON SCHEMA net FROM anon, authenticated;

-- GRANTS-3: a new public table gives nothing to visitors by default.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE SELECT ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

-- GRANTS-4: visitors never reach the private schema (no anon-readable object
-- uses it: the visitor views are definer views, sports/gear_catalog policies
-- are plain).
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA private FROM anon;
REVOKE USAGE ON SCHEMA private FROM anon;

-- GRANTS-2: every function of public / private resolves PostGIS & co.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
      AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%' AND c NOT LIKE '%extensions%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions', r.sig);
  END LOOP;
END $$;
