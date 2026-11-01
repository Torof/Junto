-- Calendar links (Scott 2026-11-01, option A validated): a private iCal feed
-- of the pro's bookings for Google / Apple / Outlook (edge `calendar-feed`),
-- and an import of the pro's own calendar (its secret iCal address, read every
-- 15 min by edge `calendar-import`) that makes busy half-days unbookable.
-- Only « busy / free » per half-day is kept — never the pro's event titles.
-- Half-days: morning 08:00-13:00, afternoon 13:00-19:00 Europe/Paris.

CREATE TABLE private.pro_calendar_links (
  pro_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  export_token text NOT NULL UNIQUE CHECK (export_token ~ '^[0-9a-f]{64}$'),
  hide_names boolean NOT NULL DEFAULT false,
  import_url text CHECK (import_url IS NULL OR (char_length(import_url) <= 500 AND import_url ~ '^https://')),
  import_synced_at timestamptz,
  import_error text CHECK (import_error IS NULL OR char_length(import_error) <= 200),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE private.pro_busy_slots (
  pro_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  day date NOT NULL,
  period text NOT NULL CHECK (period IN ('am', 'pm')),
  PRIMARY KEY (pro_id, day, period)
);

REVOKE ALL ON private.pro_calendar_links FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.pro_busy_slots FROM PUBLIC, anon, authenticated;

-- Hosts we agree to fetch (anti-SSRF: the import never reaches an arbitrary
-- address). webcal:// is normalised to https:// by the setter.
CREATE OR REPLACE FUNCTION private.calendar_import_host_ok(p_url text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
  SELECT p_url ~ '^https://(calendar\.google\.com|p[0-9]+-caldav\.icloud\.com|outlook\.office365\.com|outlook\.live\.com)/';
$$;

REVOKE ALL ON FUNCTION private.calendar_import_host_ok(text) FROM PUBLIC, anon, authenticated;

-- Lazily creates the pro's row (fresh 256-bit token).
CREATE OR REPLACE FUNCTION private.ensure_calendar_link(p_pro uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO private.pro_calendar_links (pro_id, export_token)
  VALUES (p_pro, encode(extensions.gen_random_bytes(32), 'hex'))
  ON CONFLICT (pro_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION private.ensure_calendar_link(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Client RPCs (approved, non-suspended pro).

CREATE OR REPLACE FUNCTION public.get_calendar_links()
RETURNS TABLE (export_token text, hide_names boolean, import_connected boolean,
               import_synced_at timestamptz, import_error text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  PERFORM private.ensure_calendar_link(v_user_id);
  -- The imported address is never returned, not even to its owner.
  RETURN QUERY
  SELECT l.export_token, l.hide_names, l.import_url IS NOT NULL, l.import_synced_at, l.import_error
  FROM private.pro_calendar_links l WHERE l.pro_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_calendar_links() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_calendar_links() TO authenticated;

CREATE OR REPLACE FUNCTION public.regenerate_calendar_export()
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_token TEXT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  PERFORM private.rate_hit('calendar_export_regen', 10, INTERVAL '1 day');
  PERFORM private.ensure_calendar_link(v_user_id);
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  UPDATE private.pro_calendar_links SET export_token = v_token WHERE pro_id = v_user_id;
  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION public.regenerate_calendar_export() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.regenerate_calendar_export() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_calendar_export_hide_names(p_hide boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL OR p_hide IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  PERFORM private.ensure_calendar_link(v_user_id);
  UPDATE private.pro_calendar_links SET hide_names = p_hide WHERE pro_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_calendar_export_hide_names(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_calendar_export_hide_names(boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_calendar_import_url(p_url text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_url TEXT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  PERFORM private.rate_hit('calendar_import_set', 10, INTERVAL '1 day');
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

  v_url := regexp_replace(v_url, '^webcals?://', 'https://', 'i');
  IF char_length(v_url) > 500 OR v_url ~ '\s' OR NOT private.calendar_import_host_ok(v_url) THEN
    RAISE EXCEPTION 'junto.calendar_url';
  END IF;

  UPDATE private.pro_calendar_links
  SET import_url = v_url, import_synced_at = NULL, import_error = NULL
  WHERE pro_id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_calendar_import_url(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_calendar_import_url(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Edge-only RPCs (service_role): the feed reads bookings by token, the import
-- lists the addresses and writes back busy half-days.

CREATE OR REPLACE FUNCTION public.calendar_feed_bookings(p_token text)
RETURNS TABLE (id uuid, day date, period text, status text, offering_title text,
               party_size integer, client_name text, is_manual boolean, hide_names boolean)
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
         coalesce(pp.display_name, b.manual_name), (b.client_id IS NULL), v_link.hide_names
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_link.pro_id
    AND b.status IN ('pending', 'accepted')
    AND b.day BETWEEN private.today_paris() - 31 AND private.today_paris() + 190
  ORDER BY b.day, b.period;
END;
$$;

REVOKE ALL ON FUNCTION public.calendar_feed_bookings(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calendar_feed_bookings(text) TO service_role;

CREATE OR REPLACE FUNCTION public.calendar_import_targets()
RETURNS TABLE (pro_id uuid, import_url text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT l.pro_id, l.import_url
  FROM private.pro_calendar_links l
  JOIN pro_profiles pp ON pp.user_id = l.pro_id AND pp.status = 'approved'
  JOIN users u ON u.id = l.pro_id AND u.suspended_at IS NULL
  WHERE l.import_url IS NOT NULL AND private.calendar_import_host_ok(l.import_url);
$$;

REVOKE ALL ON FUNCTION public.calendar_import_targets() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calendar_import_targets() TO service_role;

-- p_slots: [{"day":"YYYY-MM-DD","period":"am"|"pm"}, …] (null on error: the
-- previous busy half-days are kept, only the error is recorded).
CREATE OR REPLACE FUNCTION public.calendar_import_apply(p_pro uuid, p_slots jsonb, p_error text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.pro_calendar_links WHERE pro_id = p_pro AND import_url IS NOT NULL) THEN
    RETURN;  -- unplugged meanwhile
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
  SELECT DISTINCT p_pro, (s ->> 'day')::date, s ->> 'period'
  FROM jsonb_array_elements(p_slots) s
  WHERE s ->> 'period' IN ('am', 'pm')
    AND (s ->> 'day') ~ '^\d{4}-\d{2}-\d{2}$'
    AND (s ->> 'day')::date BETWEEN private.today_paris() AND private.today_paris() + 190;
  UPDATE private.pro_calendar_links SET import_synced_at = now(), import_error = NULL WHERE pro_id = p_pro;
END;
$$;

REVOKE ALL ON FUNCTION public.calendar_import_apply(uuid, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calendar_import_apply(uuid, jsonb, text) TO service_role;

-- Cron: every 15 min, the edge function reads the imported calendars. Same
-- shared secret and project URL as the push webhook (00524).
CREATE OR REPLACE FUNCTION private.trigger_calendar_import()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.pro_calendar_links WHERE import_url IS NOT NULL) THEN RETURN; END IF;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL OR private.project_url() IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(
    url := private.project_url() || '/functions/v1/calendar-import',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
END;
$$;

REVOKE ALL ON FUNCTION private.trigger_calendar_import() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('junto-calendar-import', '*/15 * * * *', 'SELECT private.trigger_calendar_import();');

-- ---------------------------------------------------------------------------
-- Busy half-days in the booking path.

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
  -- 00568: a half-day busy in the pro's own calendar (iCal import) is not bookable.
  IF EXISTS (
    SELECT 1 FROM private.pro_busy_slots
    WHERE pro_id = v_off.pro_id AND day = p_day AND period = p_period
  ) THEN
    RAISE EXCEPTION 'junto.booking_slot_unavailable';
  END IF;

  IF p_party_size IS NULL
     OR p_party_size < 1
     OR p_party_size > LEAST(coalesce(v_off.max_participants, 50), 50) THEN
    RAISE EXCEPTION 'junto.booking_party_size';
  END IF;

  -- 00566: a request must fit in the places still free. Only ACCEPTED groups
  -- count (all offerings of the half-day: one pro = one outing per half-day,
  -- same count as get_pro_availability.taken) — pending requests never block,
  -- the pro picks among them.
  IF v_off.max_participants IS NOT NULL
     AND p_party_size > v_off.max_participants - coalesce((
       SELECT sum(b.party_size) FROM bookings b
       WHERE b.pro_id = v_off.pro_id AND b.day = p_day AND b.period = p_period
         AND b.status = 'accepted'), 0) THEN
    RAISE EXCEPTION 'junto.booking_full';
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
    -- 00568: busy in the pro's own calendar → not offered.
    AND NOT EXISTS (
      SELECT 1 FROM private.pro_busy_slots bs
      WHERE bs.pro_id = p_pro_id AND bs.day = a.day AND bs.period = a.period
    )
  ORDER BY a.day, a.period;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pro_agenda(p_from date, p_to date) RETURNS TABLE(kind text, id uuid, day date, period text, status text, offering_id uuid, offering_title text, party_size integer, client_id uuid, client_name text, manual_phone text, message text, is_manual boolean, sport_key text, sport_category text, participant_fields jsonb, participant_info jsonb, client_avatar_url text, max_participants integer)
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
         NULL::TEXT, NULL::INTEGER
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  -- 00568: half-days busy in the pro's own calendar (iCal import).
  SELECT 'busy'::TEXT, NULL::UUID, bs.day, bs.period, NULL::TEXT,
         NULL::UUID, NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::TEXT, NULL::TEXT,
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT, NULL::JSONB, NULL::JSONB,
         NULL::TEXT, NULL::INTEGER
  FROM private.pro_busy_slots bs
  WHERE bs.pro_id = v_user_id AND bs.day BETWEEN p_from AND p_to
  UNION ALL
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL),
         s.key::TEXT, s.category::TEXT,
         po.participant_fields, b.participant_info,
         pp.avatar_url, po.max_participants
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id
    AND b.day BETWEEN p_from AND p_to
    AND b.status IN ('pending', 'accepted')
  ORDER BY 3, 4;
END;
$$;
