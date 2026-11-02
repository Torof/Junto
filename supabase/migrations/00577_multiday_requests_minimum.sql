-- Multi-day « sur demande » + minimum mechanisms (Scott 2026-11-02, chains
-- validated).
--
-- Multi-day on request: an offering can be asked for by the day or over 2 to
-- 14 days (pro_offerings.request_days: NULL = a half-day, 1 = a day, 2-14 =
-- days). The client picks the start day; the booking covers start morning →
-- end_day afternoon (end_day computed by the server, NULL for a half-day).
-- Every half-day of the range must be open, not busy, outside a fixed date,
-- with places. Places are now counted on every accepted booking COVERING the
-- half-day, not only the ones starting there.
--
-- Minimum: an outing = a fixed date, or the accepted on-request bookings of
-- one offering at one start half-day. When its minimum is reached (or the pro
-- clicks « Maintenir »), it is confirmed once and for all and each client gets
-- « Départ confirmé ». At D-2 9h the pro is warned when it is still short; at
-- D-1 9h an outing still short and not maintained is cancelled automatically.
-- No minimum on the outing → none of this applies.

-- ---------------------------------------------------------------------------
-- 1. Data

ALTER TABLE public.pro_offerings
  ADD COLUMN request_days smallint CHECK (request_days IS NULL OR request_days BETWEEN 1 AND 14);

ALTER TABLE public.bookings
  ADD COLUMN end_day date,
  ADD CONSTRAINT bookings_end_day_range CHECK (end_day IS NULL OR (end_day >= day AND end_day - day <= 13));

-- end_day is privileged: pinned like day / period.
CREATE OR REPLACE FUNCTION public.bookings_whitelist_columns() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.pro_id := OLD.pro_id;
  NEW.client_id := OLD.client_id;
  NEW.manual_name := OLD.manual_name;
  NEW.manual_phone := OLD.manual_phone;
  NEW.day := OLD.day;
  NEW.period := OLD.period;
  NEW.end_day := OLD.end_day;
  NEW.created_at := OLD.created_at;
  NEW.submitted_count := OLD.submitted_count;
  NEW.last_submitted_at := OLD.last_submitted_at;
  NEW.session_id := OLD.session_id;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- The client reads the length from the offerings view (column appended).
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
    o.request_days
   FROM pro_offerings o
     JOIN sports s ON o.sport_id = s.id
     JOIN pro_profiles pp ON o.pro_id = pp.user_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM users u
          WHERE u.id = o.pro_id AND u.suspended_at IS NOT NULL)) AND (o.is_demo = false OR demo_content_visible()) AND (pp.status = 'approved'::text OR o.pro_id = auth.uid());

-- Confirmed outings. Internal, no client access: read through the RPCs.
CREATE TABLE private.outing_confirmations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  offering_id uuid NOT NULL REFERENCES public.pro_offerings(id) ON DELETE CASCADE,
  day date NOT NULL,
  period text NOT NULL CHECK (period IN ('am', 'pm')),
  session_id uuid REFERENCES public.pro_sessions(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('minimum', 'pro')),
  created_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON private.outing_confirmations FROM PUBLIC, anon, authenticated;
CREATE UNIQUE INDEX outing_confirmations_session_uq
  ON private.outing_confirmations (session_id) WHERE session_id IS NOT NULL;
CREATE UNIQUE INDEX outing_confirmations_request_uq
  ON private.outing_confirmations (offering_id, day, period) WHERE session_id IS NULL;

-- ---------------------------------------------------------------------------
-- 2. Internal helpers (no grant)

-- Last half-day of a booking: its own for a half-day, end_day afternoon else.
CREATE OR REPLACE FUNCTION private.booking_end_idx(p_day date, p_period text, p_end_day date)
RETURNS integer LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT CASE WHEN p_end_day IS NULL THEN private.half_idx(p_day, p_period)
              ELSE private.half_idx(p_end_day, 'pm') END
$$;
REVOKE ALL ON FUNCTION private.booking_end_idx(date, text, date) FROM PUBLIC, anon, authenticated;

-- Places taken on a half-day: accepted groups covering it, all offerings (one
-- pro = one outing per half-day).
CREATE OR REPLACE FUNCTION private.half_taken(p_pro uuid, p_day date, p_period text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce(sum(b.party_size), 0)::integer FROM bookings b
  WHERE b.pro_id = p_pro AND b.status = 'accepted'
    AND b.day <= p_day AND coalesce(b.end_day, b.day) >= p_day
    AND private.half_idx(p_day, p_period)
        BETWEEN private.half_idx(b.day, b.period) AND private.booking_end_idx(b.day, b.period, b.end_day)
$$;
REVOKE ALL ON FUNCTION private.half_taken(uuid, date, text) FROM PUBLIC, anon, authenticated;

-- People signed up to an outing (a fixed date, or the accepted on-request
-- bookings of an offering at a start half-day). Manual bookings count.
CREATE OR REPLACE FUNCTION private.outing_total(p_offering uuid, p_day date, p_period text, p_session uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT coalesce(sum(b.party_size), 0)::integer FROM bookings b
  WHERE b.status = 'accepted'
    AND ((p_session IS NOT NULL AND b.session_id = p_session)
      OR (p_session IS NULL AND b.session_id IS NULL
          AND b.offering_id = p_offering AND b.day = p_day AND b.period = p_period))
$$;
REVOKE ALL ON FUNCTION private.outing_total(uuid, date, text, uuid) FROM PUBLIC, anon, authenticated;

-- Minimum of an outing: the date's own, the offering's on request.
CREATE OR REPLACE FUNCTION private.outing_min(p_offering uuid, p_session uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT CASE WHEN p_session IS NOT NULL
              THEN (SELECT s.min_participants FROM pro_sessions s WHERE s.id = p_session)
              ELSE (SELECT po.min_participants FROM pro_offerings po WHERE po.id = p_offering) END
$$;
REVOKE ALL ON FUNCTION private.outing_min(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.outing_confirmed(p_offering uuid, p_day date, p_period text, p_session uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM private.outing_confirmations c
    WHERE (p_session IS NOT NULL AND c.session_id = p_session)
       OR (p_session IS NULL AND c.session_id IS NULL
           AND c.offering_id = p_offering AND c.day = p_day AND c.period = p_period))
$$;
REVOKE ALL ON FUNCTION private.outing_confirmed(uuid, date, text, uuid) FROM PUBLIC, anon, authenticated;

-- Confirms an outing once: reason 'minimum' only when the minimum is reached,
-- 'pro' when the pro maintains it. No minimum → nothing. Each client with an
-- accepted booking gets « Départ confirmé ». Returns whether it confirmed now.
CREATE OR REPLACE FUNCTION private.mark_outing_confirmed(
  p_pro uuid, p_offering uuid, p_day date, p_period text, p_session uuid, p_reason text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
$$;
REVOKE ALL ON FUNCTION private.mark_outing_confirmed(uuid, uuid, date, text, uuid, text) FROM PUBLIC, anon, authenticated;

-- When a booking happens, in French (stored fallback text).
CREATE OR REPLACE FUNCTION private.booking_when(p_day date, p_period text, p_end_day date)
RETURNS text LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT CASE
    WHEN p_end_day IS NULL THEN 'le ' || to_char(p_day, 'DD/MM') || ' ' || CASE p_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END
    WHEN p_end_day = p_day THEN 'le ' || to_char(p_day, 'DD/MM') || ', journée'
    ELSE 'du ' || to_char(p_day, 'DD/MM') || ' au ' || to_char(p_end_day, 'DD/MM')
  END
$$;
REVOKE ALL ON FUNCTION private.booking_when(date, text, date) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Pro RPCs

-- How the offering is asked for on request: NULL half-day, 1 day, 2-14 days.
-- Pending / accepted bookings keep the range they were made with.
CREATE OR REPLACE FUNCTION public.set_offering_request_length(p_offering_id uuid, p_days integer)
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
  IF p_days IS NOT NULL AND (p_days < 1 OR p_days > 14) THEN
    RAISE EXCEPTION 'junto.offering_request_days';
  END IF;
  UPDATE pro_offerings SET request_days = p_days
  WHERE id = p_offering_id AND pro_id = v_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.set_offering_request_length(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_offering_request_length(uuid, integer) TO authenticated;

-- « Maintenir la sortie »: the pro keeps an outing below its minimum. Clients
-- get « Départ confirmé »; it is no longer cancelled automatically.
CREATE OR REPLACE FUNCTION public.confirm_outing(p_offering_id uuid, p_day date, p_period text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_session UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);  -- includes suspension
  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') OR p_day IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF private.session_started(p_day, p_period) THEN RAISE EXCEPTION 'junto.session_closed'; END IF;

  SELECT id INTO v_session FROM pro_sessions
  WHERE pro_id = v_user_id AND offering_id = p_offering_id
    AND start_day = p_day AND start_period = p_period AND status = 'scheduled';
  IF v_session IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext(v_session::text || '_session'));
  ELSE
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || p_day::text || p_period || '_slot'));
  END IF;

  IF private.outing_total(p_offering_id, p_day, p_period, v_session) = 0 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  RETURN private.mark_outing_confirmed(v_user_id, p_offering_id, p_day, p_period, v_session, 'pro');
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_outing(uuid, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_outing(uuid, date, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Fixed-date helpers: on-request bookings now conflict over their range

CREATE OR REPLACE FUNCTION private.session_check(
  p_pro uuid, p_start_day date, p_start_period text, p_end_day date, p_end_period text,
  p_max integer, p_min integer, p_meeting text, p_exclude uuid
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_s INTEGER;
  v_e INTEGER;
  v_i INTEGER;
  v_day DATE;
  v_period TEXT;
  v_meeting TEXT;
BEGIN
  IF p_start_period IS NULL OR p_start_period NOT IN ('am', 'pm')
     OR p_end_period IS NULL OR p_end_period NOT IN ('am', 'pm')
     OR p_start_day IS NULL OR p_end_day IS NULL THEN
    RAISE EXCEPTION 'junto.session_dates';
  END IF;
  v_s := private.half_idx(p_start_day, p_start_period);
  v_e := private.half_idx(p_end_day, p_end_period);
  IF v_e < v_s OR p_end_day - p_start_day > 13
     OR private.session_started(p_start_day, p_start_period)
     OR p_start_day > private.today_paris() + INTERVAL '12 months' THEN
    RAISE EXCEPTION 'junto.session_dates';
  END IF;

  IF p_max IS NULL OR p_max < 1 OR p_max > 50
     OR (p_min IS NOT NULL AND (p_min < 1 OR p_min > p_max)) THEN
    RAISE EXCEPTION 'junto.session_places';
  END IF;

  -- Meeting point: tags out, control and invisible / direction characters out.
  v_meeting := nullif(trim(regexp_replace(regexp_replace(
                 regexp_replace(coalesce(p_meeting, ''), '<[^>]*>', '', 'g'),
                 '[\x00-\x1F\x7F]', ' ', 'g'),
                 '[­​-‏‪-‮⁠-⁤⁦-⁩﻿]', '', 'g')), '');
  IF v_meeting IS NOT NULL AND char_length(v_meeting) > 120 THEN
    RAISE EXCEPTION 'junto.session_meeting';
  END IF;

  FOR v_i IN v_s .. v_e LOOP
    v_day := DATE '2000-01-01' + (v_i / 2);
    v_period := CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END;
    PERFORM pg_advisory_xact_lock(hashtext(p_pro::text || v_day::text || v_period || '_slot'));
  END LOOP;

  -- Another date, an accepted « sur demande » booking overlapping the range,
  -- or a half-day busy in the pro's own calendar.
  IF EXISTS (
    SELECT 1 FROM pro_sessions s
    WHERE s.pro_id = p_pro AND s.status = 'scheduled' AND s.id IS DISTINCT FROM p_exclude
      AND private.half_idx(s.start_day, s.start_period) <= v_e
      AND private.half_idx(s.end_day, s.end_period) >= v_s
  ) OR EXISTS (
    SELECT 1 FROM bookings b
    WHERE b.pro_id = p_pro AND b.status = 'accepted'
      AND b.session_id IS NULL  -- the date's own sign-ups never conflict
      AND private.half_idx(b.day, b.period) <= v_e
      AND private.booking_end_idx(b.day, b.period, b.end_day) >= v_s
  ) OR EXISTS (
    SELECT 1 FROM private.pro_busy_slots bs
    WHERE bs.pro_id = p_pro AND private.half_idx(bs.day, bs.period) BETWEEN v_s AND v_e
  ) THEN
    RAISE EXCEPTION 'junto.session_conflict';
  END IF;

  RETURN v_meeting;
END;
$$;
REVOKE ALL ON FUNCTION private.session_check(uuid, date, text, date, text, integer, integer, text, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.decline_pending_in_range(p_pro uuid, p_s integer, p_e integer)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bk RECORD;
  v_pro_name TEXT;
  v_n INTEGER := 0;
BEGIN
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = p_pro;
  FOR v_bk IN
    SELECT b.id, b.client_id, b.offering_id, b.day, po.title
    FROM bookings b JOIN pro_offerings po ON po.id = b.offering_id
    WHERE b.pro_id = p_pro AND b.status = 'pending'
      AND private.half_idx(b.day, b.period) <= p_e
      AND private.booking_end_idx(b.day, b.period, b.end_day) >= p_s
    FOR UPDATE OF b
  LOOP
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings SET status = 'declined' WHERE id = v_bk.id AND status = 'pending';
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_n := v_n + 1;
    CONTINUE WHEN v_bk.client_id IS NULL;
    PERFORM create_notification(
      v_bk.client_id,
      'booking_declined',
      'Créneau indisponible',
      coalesce(v_pro_name, 'Le professionnel') || ' n''est pas disponible pour « '
        || coalesce(v_bk.title, 'cette sortie') || ' » le ' || to_char(v_bk.day, 'DD/MM')
        || '. Essaie un autre créneau.',
      jsonb_build_object('booking_id', v_bk.id, 'offering_id', v_bk.offering_id,
        'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'), 'title', coalesce(v_bk.title, 'cette sortie'),
                                     'date', to_char(v_bk.day, 'YYYY-MM-DD')))
    );
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION private.decline_pending_in_range(uuid, integer, integer) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_session_conflicts(
  p_start_day date, p_start_period text, p_end_day date, p_end_period text
) RETURNS TABLE (booking_id uuid, day date, period text, client_name text, offering_title text, party_size integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  IF p_start_period IS NULL OR p_start_period NOT IN ('am', 'pm')
     OR p_end_period IS NULL OR p_end_period NOT IN ('am', 'pm')
     OR p_start_day IS NULL OR p_end_day IS NULL OR p_end_day - p_start_day > 13 THEN
    RAISE EXCEPTION 'junto.session_dates';
  END IF;

  RETURN QUERY
  SELECT b.id, b.day, b.period, coalesce(pp.display_name, b.manual_name), po.title, b.party_size
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id AND b.status = 'pending'
    AND private.half_idx(b.day, b.period) <= private.half_idx(p_end_day, p_end_period)
    AND private.booking_end_idx(b.day, b.period, b.end_day) >= private.half_idx(p_start_day, p_start_period)
  ORDER BY b.day, b.period;
END;
$$;
REVOKE ALL ON FUNCTION public.get_session_conflicts(date, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_session_conflicts(date, text, date, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Bookings (rebuilt from their last definition, 00575 / 00576)

CREATE OR REPLACE FUNCTION public.create_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_message text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.get_pro_availability(p_pro_id uuid) RETURNS TABLE(day date, period text, taken integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
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

  -- `taken` = somme des groupes ACCEPTÉS couvrant la demi-journée (00577 :
  -- plages de plusieurs jours comprises), toutes offres confondues. Agrégat
  -- anonyme : aucun nom, aucune composition de groupe ne fuite.
  RETURN QUERY
  SELECT a.day, a.period, private.half_taken(p_pro_id, a.day, a.period) AS taken
  FROM pro_availabilities a
  WHERE a.pro_id = p_pro_id AND a.day >= private.today_paris()
    -- 00568: busy in the pro's own calendar → not offered.
    AND NOT EXISTS (
      SELECT 1 FROM private.pro_busy_slots bs
      WHERE bs.pro_id = p_pro_id AND bs.day = a.day AND bs.period = a.period
    )
    -- 00575: taken by a fixed date → not offered on request.
    AND private.session_at(p_pro_id, a.day, a.period) IS NULL
  ORDER BY a.day, a.period;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_booking(p_booking_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
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

  -- 00566: no overbooking on accept. The slot locks (every half-day of the
  -- range, in order — 00577) serialise two accepts so they cannot both pass
  -- the count.
  FOR v_i IN private.half_idx(v_bk.day, v_bk.period) .. private.booking_end_idx(v_bk.day, v_bk.period, v_bk.end_day) LOOP
    v_d := DATE '2000-01-01' + (v_i / 2);
    v_p := CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END;
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || v_d::text || v_p || '_slot'));
  END LOOP;
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

  RETURN v_conversation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_pro_session(p_session_id uuid, p_party_size integer, p_message text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
  IF p_party_size IS NULL OR p_party_size < 1 OR p_party_size > v_s.max_participants THEN
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
    IF v_existing.last_submitted_at > now() - INTERVAL '1 hour' OR v_existing.submitted_count >= 5 THEN
      RAISE EXCEPTION 'junto.booking_cooldown';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'accepted', session_id = p_session_id, end_day = NULL, party_size = p_party_size, message = v_msg,
        created_at = now(), price_eur = v_s.o_price, price_unit = v_s.o_unit,
        submitted_count = v_existing.submitted_count + 1, last_submitted_at = now()
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
$$;
REVOKE ALL ON FUNCTION public.join_pro_session(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_pro_session(uuid, integer, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_manual_booking(p_offering_id uuid, p_day date, p_period text, p_party_size integer, p_name text, p_phone text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
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
    SELECT * INTO v_sess FROM pro_sessions WHERE id = v_session_id;
    IF v_sess.offering_id <> p_offering_id OR v_sess.start_day <> p_day OR v_sess.start_period <> v_period
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
    -- 00577: no half-day of the range inside a fixed date.
    FOR v_i IN private.half_idx(p_day, v_period) .. private.booking_end_idx(p_day, v_period, v_end_day) LOOP
      IF private.session_at(v_user_id, DATE '2000-01-01' + (v_i / 2),
                            CASE WHEN v_i % 2 = 0 THEN 'am' ELSE 'pm' END) IS NOT NULL THEN
        RAISE EXCEPTION 'junto.booking_slot_unavailable';
      END IF;
    END LOOP;
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || p_day::text || v_period || '_slot'));
  END IF;

  INSERT INTO bookings (offering_id, pro_id, client_id, manual_name, manual_phone,
                        day, period, end_day, party_size, status, session_id)
  VALUES (p_offering_id, v_user_id, NULL, v_name, v_phone, p_day, v_period, v_end_day, p_party_size, 'accepted', v_session_id)
  RETURNING id INTO v_booking_id;

  -- 00577: these people may reach the outing's minimum.
  PERFORM private.mark_outing_confirmed(v_user_id, p_offering_id, p_day, v_period, v_session_id, 'minimum');

  RETURN v_booking_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_outing(
  p_offering_id uuid, p_day date, p_period text, p_reason text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
  PERFORM private.assert_approved_pro(v_user_id);

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
    IF v_reason IS NOT NULL
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
$$;

-- ---------------------------------------------------------------------------
-- 6. Reads

DROP FUNCTION public.get_pro_agenda(date, date);
CREATE FUNCTION public.get_pro_agenda(p_from date, p_to date) RETURNS TABLE(kind text, id uuid, day date, period text, status text, offering_id uuid, offering_title text, party_size integer, client_id uuid, client_name text, manual_phone text, message text, is_manual boolean, sport_key text, sport_category text, participant_fields jsonb, participant_info jsonb, client_avatar_url text, max_participants integer, session_id uuid, end_day date, min_participants integer, confirmed boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
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
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT, NULL::JSONB, NULL::JSONB,
         NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::DATE, NULL::INTEGER, NULL::BOOLEAN
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  -- 00568: half-days busy in the pro's own calendar (iCal import).
  SELECT 'busy'::TEXT, NULL::UUID, bs.day, bs.period, NULL::TEXT,
         NULL::UUID, NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::TEXT, NULL::TEXT,
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT, NULL::JSONB, NULL::JSONB,
         NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::DATE, NULL::INTEGER, NULL::BOOLEAN
  FROM private.pro_busy_slots bs
  WHERE bs.pro_id = v_user_id AND bs.day BETWEEN p_from AND p_to
  UNION ALL
  -- 00577: a booking over several days shows while any of its days is in range;
  -- min / confirmed = its on-request outing (a fixed date's come from get_my_sessions).
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL),
         s.key::TEXT, s.category::TEXT,
         po.participant_fields, b.participant_info,
         pp.avatar_url, po.max_participants, b.session_id,
         b.end_day,
         CASE WHEN b.session_id IS NULL THEN po.min_participants END,
         CASE WHEN b.session_id IS NULL AND b.status = 'accepted'
              THEN private.outing_confirmed(b.offering_id, b.day, b.period, NULL) END
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id
    AND b.day <= p_to AND coalesce(b.end_day, b.day) >= p_from
    AND b.status IN ('pending', 'accepted')
  ORDER BY 3, 4;
END;
$$;
REVOKE ALL ON FUNCTION public.get_pro_agenda(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pro_agenda(date, date) TO authenticated;

DROP FUNCTION public.get_my_sessions(date, date);
CREATE FUNCTION public.get_my_sessions(p_from date, p_to date)
RETURNS TABLE (id uuid, offering_id uuid, offering_title text, sport_key text, sport_category text,
               start_day date, start_period text, end_day date, end_period text,
               max_participants integer, min_participants integer, meeting_point text, taken integer,
               confirmed boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to > p_from + INTERVAL '13 months' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT s.id, s.offering_id, po.title, sp.key::TEXT, sp.category::TEXT,
         s.start_day, s.start_period, s.end_day, s.end_period,
         s.max_participants, s.min_participants, s.meeting_point,
         coalesce((SELECT sum(b.party_size) FROM bookings b
                   WHERE b.session_id = s.id AND b.status = 'accepted'), 0)::INTEGER,
         private.outing_confirmed(s.offering_id, s.start_day, s.start_period, s.id)
  FROM pro_sessions s
  JOIN pro_offerings po ON po.id = s.offering_id
  LEFT JOIN sports sp ON sp.id = po.sport_id
  WHERE s.pro_id = v_user_id AND s.status = 'scheduled'
    AND s.end_day >= p_from AND s.start_day <= p_to
  ORDER BY s.start_day, s.start_period;
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_sessions(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_sessions(date, date) TO authenticated;

-- The client's bookings: + the end of an on-request range, and for an accepted
-- one the outing's minimum, how many are signed up (a number, no names) and
-- whether the departure is confirmed.
DROP FUNCTION public.get_my_bookings();
CREATE FUNCTION public.get_my_bookings() RETURNS TABLE(id uuid, offering_id uuid, offering_title text, pro_id uuid, pro_name text, day date, period text, party_size integer, status text, conversation_id uuid, created_at timestamp with time zone, location_name text, price_eur numeric, price_unit text, sport_key text, sport_category text, equipment_required jsonb, participant_fields jsonb, participant_info jsonb, session_id uuid, end_day date, end_period text, meeting_point text, min_participants integer, outing_total integer, confirmed boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, extensions
    AS $$
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
         po.equipment_required, po.participant_fields, b.participant_info,
         b.session_id,
         coalesce(ps.end_day, b.end_day),
         coalesce(ps.end_period, CASE WHEN b.end_day IS NOT NULL THEN 'pm' END),
         ps.meeting_point,
         CASE WHEN b.status = 'accepted' THEN private.outing_min(b.offering_id, b.session_id) END,
         CASE WHEN b.status = 'accepted' THEN private.outing_total(b.offering_id, b.day, b.period, b.session_id) END,
         CASE WHEN b.status = 'accepted' THEN private.outing_confirmed(b.offering_id, b.day, b.period, b.session_id) END
  FROM bookings b
  LEFT JOIN pro_sessions ps ON ps.id = b.session_id
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.pro_id
  WHERE b.client_id = v_user_id
  ORDER BY b.day DESC, b.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.get_my_bookings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_bookings() TO authenticated;

-- Calendar feed: an on-request booking over several days spans them.
CREATE OR REPLACE FUNCTION public.calendar_feed_bookings(p_token text)
RETURNS TABLE (id uuid, day date, period text, status text, offering_title text,
               party_size integer, client_name text, is_manual boolean, hide_names boolean,
               kind text, end_day date, end_period text, max_participants integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
         coalesce(pp.display_name, b.manual_name), (b.client_id IS NULL), v_link.hide_names,
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
$$;
REVOKE ALL ON FUNCTION public.calendar_feed_bookings(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calendar_feed_bookings(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 7. Scheduled jobs

-- D-2 9h pro reminder (00574/00576): the minimum now also covers on-request
-- outings (the offering's minimum), and a confirmed outing is never reported
-- as short. The text says it will be cancelled the next morning.
CREATE OR REPLACE FUNCTION private.notify_booking_forms_missing()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
                      THEN greatest(b.party_size - coalesce(jsonb_array_length(b.participant_info), 0), 0)
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
             po.title
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
      v_body := v_body || v_row.total || '/' || v_row.min || ' inscrits. Maintiens-la, sinon elle sera annulée demain à 9 h';
    END IF;
    PERFORM create_notification(
      v_row.pro_id,
      'booking_forms_missing',
      CASE WHEN v_row.missing > 0 THEN 'Il manque des infos' ELSE 'Minimum pas atteint' END,
      v_body || '.',
      jsonb_build_object('offering_id', v_row.offering_id,
        'variant', CASE WHEN v_min_low AND v_row.missing > 0 THEN 'both'
                        WHEN v_min_low THEN 'minimum' ELSE NULL END,
        'params', jsonb_build_object('title', coalesce(v_row.title, ''), 'date', to_char(v_row.day, 'YYYY-MM-DD'),
                                     'period', v_row.period, 'count', v_row.missing, 'total', v_row.total,
                                     'min', v_row.min))
    );
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION private.notify_booking_forms_missing() FROM PUBLIC, anon, authenticated;

-- Cancels one outing that did not reach its minimum: accepted → cancelled_pro
-- (« pas assez de participants »), pending → declined. Nothing in the DMs —
-- the pro is not the one writing. Returns the bookings closed.
CREATE OR REPLACE FUNCTION private.auto_cancel_outing_bookings(
  p_pro uuid, p_offering uuid, p_day date, p_period text, p_session uuid, p_title text
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_bk RECORD;
  v_pro_name TEXT;
  v_n INTEGER := 0;
BEGIN
  SELECT display_name INTO v_pro_name FROM public_profiles WHERE id = p_pro;
  FOR v_bk IN
    SELECT b.id, b.client_id, b.status FROM bookings b
    WHERE b.status IN ('pending', 'accepted')
      AND ((p_session IS NOT NULL AND b.session_id = p_session)
        OR (p_session IS NULL AND b.session_id IS NULL AND b.pro_id = p_pro
            AND b.offering_id = p_offering AND b.day = p_day AND b.period = p_period))
    FOR UPDATE
  LOOP
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = CASE WHEN v_bk.status = 'accepted' THEN 'cancelled_pro' ELSE 'declined' END
    WHERE id = v_bk.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_n := v_n + 1;
    CONTINUE WHEN v_bk.client_id IS NULL;

    IF v_bk.status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.client_id,
        'booking_cancelled',
        'Sortie annulée',
        '« ' || coalesce(p_title, 'Ta sortie') || ' » du ' || to_char(p_day, 'DD/MM')
          || ' est annulée : pas assez de participants.',
        jsonb_build_object('booking_id', v_bk.id, 'by', 'auto', 'variant', 'auto_minimum',
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(p_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    ELSE
      PERFORM create_notification(
        v_bk.client_id,
        'booking_declined',
        'Créneau indisponible',
        coalesce(v_pro_name, 'Le professionnel') || ' n’est pas disponible pour « '
          || coalesce(p_title, 'ta sortie') || ' » le ' || to_char(p_day, 'DD/MM') || '.',
        jsonb_build_object('booking_id', v_bk.id, 'offering_id', p_offering,
          'params', jsonb_build_object('name', coalesce(v_pro_name, 'Le professionnel'),
                                       'title', coalesce(p_title, 'ta sortie'),
                                       'date', to_char(p_day, 'YYYY-MM-DD')))
      );
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION private.auto_cancel_outing_bookings(uuid, uuid, date, text, uuid, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.notify_outing_auto_cancelled(
  p_pro uuid, p_offering uuid, p_day date, p_period text, p_title text, p_total integer, p_min integer
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  PERFORM create_notification(
    p_pro,
    'outing_auto_cancelled',
    'Sortie annulée automatiquement',
    '« ' || coalesce(p_title, 'Ta sortie') || ' » du ' || to_char(p_day, 'DD/MM')
      || ' : minimum non atteint (' || p_total || '/' || p_min || '), la sortie est annulée.',
    jsonb_build_object('offering_id', p_offering,
      'params', jsonb_build_object('title', coalesce(p_title, ''), 'date', to_char(p_day, 'YYYY-MM-DD'),
                                   'period', p_period, 'total', p_total, 'min', p_min))
  );
END;
$$;
REVOKE ALL ON FUNCTION private.notify_outing_auto_cancelled(uuid, uuid, date, text, text, integer, integer) FROM PUBLIC, anon, authenticated;

-- D-1 9h: outings leaving tomorrow, with a minimum, still short and not
-- maintained by the pro → cancelled.
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

  -- Fixed dates.
  FOR v_s IN
    SELECT s.id, s.pro_id, s.offering_id, s.start_day, s.start_period, s.min_participants, po.title
    FROM pro_sessions s JOIN pro_offerings po ON po.id = s.offering_id
    WHERE s.status = 'scheduled' AND s.start_day = v_tomorrow AND s.min_participants IS NOT NULL
    ORDER BY s.id
  LOOP
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
  END LOOP;

  -- On request: the accepted bookings of an offering at a start half-day.
  -- Ordered by pro then half-day so the slot locks are taken in the same
  -- order as accept_booking's.
  FOR v_o IN
    SELECT b.pro_id, b.offering_id, b.day, b.period, po.title, po.min_participants
    FROM bookings b JOIN pro_offerings po ON po.id = b.offering_id
    WHERE b.status = 'accepted' AND b.session_id IS NULL AND b.day = v_tomorrow
      AND po.min_participants IS NOT NULL
    GROUP BY b.pro_id, b.offering_id, b.day, b.period, po.title, po.min_participants
    ORDER BY b.pro_id, b.day, b.period, b.offering_id
  LOOP
    PERFORM pg_advisory_xact_lock(hashtext(v_o.pro_id::text || v_o.day::text || v_o.period || '_slot'));
    v_total := private.outing_total(v_o.offering_id, v_o.day, v_o.period, NULL);
    CONTINUE WHEN v_total = 0 OR v_total >= v_o.min_participants
               OR private.outing_confirmed(v_o.offering_id, v_o.day, v_o.period, NULL);
    PERFORM private.auto_cancel_outing_bookings(v_o.pro_id, v_o.offering_id, v_o.day, v_o.period,
                                                NULL, v_o.title);
    PERFORM private.notify_outing_auto_cancelled(v_o.pro_id, v_o.offering_id, v_o.day, v_o.period,
                                                 v_o.title, v_total, v_o.min_participants);
    v_n := v_n + 1;
  END LOOP;

  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION private.auto_cancel_short_outings() FROM PUBLIC, anon, authenticated;

-- 9h Paris whatever the season (07:00 UTC in summer, 08:00 in winter).
SELECT cron.schedule('junto-outing-auto-cancel', '0 7,8 * * *', 'SELECT private.auto_cancel_short_outings();');
