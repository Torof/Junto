-- ============================================================================
-- 00416 — Suite pro v1 : disponibilités + réservations (docs/sprint-booking.md,
-- DECISIONS 2026-09-17 « de la devanture à la suite de gestion »).
--
--   (1) pro_availabilities — demi-journées où le pro est disponible.
--   (2) bookings — demandes de réservation (client Junto OU manuelle hors-app).
--   (3) initiated_from += 'booking' (DM logistique, jamais compté social/contact).
--   (4) RPCs : set_pro_availability · create_booking · create_manual_booking ·
--       accept/decline/cancel(_pro)_booking · get_pro_availability ·
--       get_pro_agenda · get_my_bookings.
--   (5) Garde-fous : delete_pro_offering + unregister_as_pro refusent si des
--       réservations futures vivantes existent.
--   (6) 4 types de notifications + defaults/backfill préférences (pattern 00168).
--
-- Invariants respectés : DM actif seulement à l'acceptation (double consentement
-- frais : demande = consentement client, accept = consentement pro — peut
-- réactiver une ligne pending/declined) ; refus NOTIFIÉ (logistique, pas social —
-- déviation assumée, sprint-booking.md) ; pas de décompte de capacité ; aucun
-- texte libre client dans title/body de push ; jamais de paiement.
-- ============================================================================

-- ---------- (1) pro_availabilities ----------
CREATE TABLE pro_availabilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  period TEXT NOT NULL CHECK (period IN ('am', 'pm')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (pro_id, day, period)
);

ALTER TABLE pro_availabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE pro_availabilities FORCE ROW LEVEL SECURITY;

-- Own rows only — les autres lisent via get_pro_availability (RPC gated).
CREATE POLICY pro_availabilities_select_own ON pro_availabilities
  FOR SELECT USING (pro_id = auth.uid());
-- Aucune write policy : RPC uniquement.

CREATE OR REPLACE FUNCTION pro_availabilities_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN RETURN NEW; END IF;
  NEW.id := OLD.id;
  NEW.pro_id := OLD.pro_id;
  NEW.day := OLD.day;
  NEW.period := OLD.period;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION pro_availabilities_whitelist_columns() FROM anon, authenticated;
CREATE TRIGGER pro_availabilities_whitelist_trg
  BEFORE UPDATE ON pro_availabilities
  FOR EACH ROW EXECUTE FUNCTION pro_availabilities_whitelist_columns();

REVOKE INSERT, UPDATE, DELETE ON pro_availabilities FROM anon, authenticated, PUBLIC;
GRANT SELECT ON pro_availabilities TO authenticated;

-- ---------- (2) bookings ----------
CREATE TABLE bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id UUID NOT NULL REFERENCES pro_offerings(id) ON DELETE CASCADE,
  pro_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES users(id) ON DELETE CASCADE,
  -- Réservation manuelle hors-app : saisie par le pro, pas de compte.
  manual_name TEXT CHECK (manual_name IS NULL OR char_length(manual_name) BETWEEN 1 AND 80),
  manual_phone TEXT CHECK (manual_phone IS NULL OR char_length(manual_phone) BETWEEN 3 AND 30),
  day DATE NOT NULL,
  period TEXT NOT NULL CHECK (period IN ('am', 'pm')),
  party_size INTEGER NOT NULL CHECK (party_size BETWEEN 1 AND 50),
  message TEXT CHECK (message IS NULL OR char_length(message) BETWEEN 1 AND 500),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'cancelled_pro', 'expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (client_id != pro_id),
  -- Exactement une identité : client Junto XOR client manuel.
  CHECK ((client_id IS NOT NULL AND manual_name IS NULL AND manual_phone IS NULL)
      OR (client_id IS NULL AND manual_name IS NOT NULL)),
  UNIQUE (offering_id, client_id, day, period)
);

CREATE INDEX bookings_pro_day_idx ON bookings (pro_id, day);
CREATE INDEX bookings_client_idx ON bookings (client_id) WHERE client_id IS NOT NULL;

ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings FORCE ROW LEVEL SECURITY;

CREATE POLICY bookings_select_parties ON bookings
  FOR SELECT USING (client_id = auth.uid() OR pro_id = auth.uid());
-- Aucune write policy : RPC uniquement.

CREATE OR REPLACE FUNCTION bookings_whitelist_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  -- Identité et créneau figés ; status/party_size/message évoluent via RPC
  -- (resubmit) — il n'existe de toute façon aucun chemin d'UPDATE client.
  NEW.id := OLD.id;
  NEW.offering_id := OLD.offering_id;
  NEW.pro_id := OLD.pro_id;
  NEW.client_id := OLD.client_id;
  NEW.manual_name := OLD.manual_name;
  NEW.manual_phone := OLD.manual_phone;
  NEW.day := OLD.day;
  NEW.period := OLD.period;
  NEW.created_at := OLD.created_at;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION bookings_whitelist_columns() FROM anon, authenticated;
CREATE TRIGGER bookings_whitelist_trg
  BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_whitelist_columns();

REVOKE INSERT, UPDATE, DELETE ON bookings FROM anon, authenticated, PUBLIC;
GRANT SELECT ON bookings TO authenticated;

-- ---------- (3) initiated_from += 'booking' (logistique, comme transport) ----------
ALTER TABLE conversations DROP CONSTRAINT conversations_initiated_from_check;
ALTER TABLE conversations ADD CONSTRAINT conversations_initiated_from_check
  CHECK (initiated_from IS NULL OR initiated_from IN
         ('profile', 'discovery', 'transport', 'invite', 'request_reply', 'booking'));
-- NB : 00372 liste explicitement ('profile','discovery','invite') comme DM
-- « sociaux » — 'booking' reste donc logistique (pas un contact) sans autre patch.

-- ---------- Helper interne : le triple check pro ----------
CREATE OR REPLACE FUNCTION private.assert_approved_pro(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM users u
    JOIN pro_profiles pp ON pp.user_id = u.id
    WHERE u.id = p_user_id
      AND u.tier = 'pro'
      AND u.suspended_at IS NULL
      AND pp.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION private.assert_approved_pro(UUID) FROM PUBLIC, anon, authenticated;

-- ---------- (4a) set_pro_availability ----------
CREATE OR REPLACE FUNCTION set_pro_availability(
  p_day DATE,
  p_period TEXT,
  p_available BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM private.assert_approved_pro(v_user_id);

  IF p_period IS NULL OR p_period NOT IN ('am', 'pm') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_day IS NULL OR p_day < current_date THEN
    RAISE EXCEPTION 'junto.booking_date';
  END IF;
  IF p_day > current_date + INTERVAL '6 months' THEN
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
$$;
REVOKE ALL ON FUNCTION set_pro_availability(DATE, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_pro_availability(DATE, TEXT, BOOLEAN) TO authenticated;

-- ---------- (4b) create_booking (client Junto) ----------
CREATE OR REPLACE FUNCTION create_booking(
  p_offering_id UUID,
  p_day DATE,
  p_period TEXT,
  p_party_size INTEGER,
  p_message TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  -- Offre + pro cible : approuvé, non suspendu, gate démo.
  SELECT po.id, po.pro_id, po.title, po.max_participants, pp.is_demo
    INTO v_off
  FROM pro_offerings po
  JOIN pro_profiles pp ON pp.user_id = po.pro_id
  JOIN users u ON u.id = po.pro_id
  WHERE po.id = p_offering_id
    AND pp.status = 'approved'
    AND u.suspended_at IS NULL
    AND u.tier = 'pro';
  IF v_off IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.pro_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_off.is_demo = true AND NOT demo_content_visible() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Blocage bidirectionnel.
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_off.pro_id)
       OR (blocker_id = v_off.pro_id AND blocked_id = v_user_id)
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Fenêtre temporelle + créneau réellement ouvert par le pro.
  IF p_day IS NULL OR p_day < current_date OR p_day > current_date + INTERVAL '6 months' THEN
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

  -- Rate limits sous advisory lock (le slot survit au decline — anti-oracle 00350).
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_booking'));
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND status = 'pending') >= 5 THEN
    RAISE EXCEPTION 'junto.booking_pending_cap';
  END IF;
  IF (SELECT count(*) FROM bookings
      WHERE client_id = v_user_id AND created_at > now() - INTERVAL '24 hours') >= 10 THEN
    RAISE EXCEPTION 'junto.booking_daily_cap';
  END IF;

  -- Resubmit sur la même clé (offre, jour, période) — pattern seat_requests.
  SELECT * INTO v_existing FROM bookings
  WHERE offering_id = p_offering_id AND client_id = v_user_id
    AND day = p_day AND period = p_period
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status IN ('pending', 'accepted') THEN
      RAISE EXCEPTION 'junto.booking_already';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE bookings
    SET status = 'pending', party_size = p_party_size, message = v_msg, created_at = now()
    WHERE id = v_existing.id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    v_booking_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO bookings (offering_id, pro_id, client_id, day, period, party_size, message)
      VALUES (p_offering_id, v_off.pro_id, v_user_id, p_day, p_period, p_party_size, v_msg)
      RETURNING id INTO v_booking_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'junto.booking_already';
    END;
  END IF;

  SELECT display_name INTO v_client_name FROM public_profiles WHERE id = v_user_id;
  v_period_label := CASE p_period WHEN 'am' THEN 'matin' ELSE 'après-midi' END;

  -- Copy générique : jamais le message libre du client dans title/body.
  PERFORM create_notification(
    v_off.pro_id,
    'booking_request',
    'Nouvelle demande de réservation',
    coalesce(v_client_name, 'Un membre') || ' — « ' || v_off.title || ' », le '
      || to_char(p_day, 'DD/MM') || ' ' || v_period_label
      || ' (' || p_party_size || ' pers.)',
    jsonb_build_object('booking_id', v_booking_id, 'offering_id', p_offering_id)
  );

  RETURN v_booking_id;
END;
$$;
REVOKE ALL ON FUNCTION create_booking(UUID, DATE, TEXT, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_booking(UUID, DATE, TEXT, INTEGER, TEXT) TO authenticated;

-- ---------- (4c) create_manual_booking (client hors-app, saisi par le pro) ----------
CREATE OR REPLACE FUNCTION create_manual_booking(
  p_offering_id UUID,
  p_day DATE,
  p_period TEXT,
  p_party_size INTEGER,
  p_name TEXT,
  p_phone TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  IF p_day IS NULL OR p_day < current_date OR p_day > current_date + INTERVAL '6 months' THEN
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
$$;
REVOKE ALL ON FUNCTION create_manual_booking(UUID, DATE, TEXT, INTEGER, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_manual_booking(UUID, DATE, TEXT, INTEGER, TEXT, TEXT) TO authenticated;

-- ---------- (4d) accept_booking ----------
CREATE OR REPLACE FUNCTION accept_booking(p_booking_id UUID)
RETURNS UUID  -- conversation_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  v_period_label TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.status != 'pending' OR v_bk.client_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.pro_id != v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  -- Client toujours joignable ? (suspension / blocage survenus entre-temps)
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

  -- DM : actif seulement MAINTENANT (double consentement frais). Réutilise /
  -- réactive toute ligne existante de la paire, sinon crée en logistique.
  IF v_bk.client_id < v_user_id THEN v_u1 := v_bk.client_id; v_u2 := v_user_id;
  ELSE v_u1 := v_user_id; v_u2 := v_bk.client_id; END IF;

  SELECT id INTO v_conversation_id FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;

  IF v_conversation_id IS NULL THEN
    INSERT INTO conversations (type, user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
    VALUES ('dm', v_u1, v_u2, v_user_id, 'active', 'booking', now(), now())
    RETURNING id INTO v_conversation_id;
  ELSE
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations
    SET status = 'active', request_expires_at = NULL, last_message_at = now()
    WHERE id = v_conversation_id AND status != 'active';
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;

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
      || coalesce(v_off_title, 'ta sortie') || ' » — le ' || to_char(v_bk.day, 'DD/MM')
      || ' ' || v_period_label || '. Paiement sur place.',
    jsonb_build_object('booking_id', v_bk.id, 'conversation_id', v_conversation_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION accept_booking(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION accept_booking(UUID) TO authenticated;

-- ---------- (4e) decline_booking (refus NOTIFIÉ — logistique, pas social) ----------
CREATE OR REPLACE FUNCTION decline_booking(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.status != 'pending' OR v_bk.pro_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'declined' WHERE id = p_booking_id AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  PERFORM set_config('junto.bypass_lock', 'false', true);
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_bk.client_id IS NOT NULL THEN
    SELECT title INTO v_off_title FROM pro_offerings WHERE id = v_bk.offering_id;
    PERFORM create_notification(
      v_bk.client_id,
      'booking_declined',
      'Réservation non disponible',
      'Le professionnel n''est pas disponible pour « '
        || coalesce(v_off_title, 'cette sortie') || ' » le ' || to_char(v_bk.day, 'DD/MM')
        || '. Essaie un autre créneau.',
      jsonb_build_object('booking_id', v_bk.id, 'offering_id', v_bk.offering_id)
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION decline_booking(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION decline_booking(UUID) TO authenticated;

-- ---------- (4f) cancel_booking (client) ----------
CREATE OR REPLACE FUNCTION cancel_booking(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_client_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.client_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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
      jsonb_build_object('booking_id', v_bk.id, 'by', 'client')
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION cancel_booking(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION cancel_booking(UUID) TO authenticated;

-- ---------- (4g) cancel_booking_pro (pro — météo, imprévu) ----------
CREATE OR REPLACE FUNCTION cancel_booking_pro(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_bk RECORD;
  v_off_title TEXT;
  v_pro_name TEXT;
  v_updated INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.pro_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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
      jsonb_build_object('booking_id', v_bk.id, 'by', 'pro')
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION cancel_booking_pro(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION cancel_booking_pro(UUID) TO authenticated;

-- ---------- (4h) get_pro_availability (lecture publique gated) ----------
CREATE OR REPLACE FUNCTION get_pro_availability(p_pro_id UUID)
RETURNS TABLE (day DATE, period TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  -- Cible : pro approuvé, non suspendu, gate démo, pas de blocage.
  IF NOT EXISTS (
    SELECT 1 FROM pro_profiles pp
    JOIN users u ON u.id = pp.user_id
    WHERE pp.user_id = p_pro_id
      AND pp.status = 'approved'
      AND u.suspended_at IS NULL
      AND (pp.is_demo = false OR demo_content_visible())
  ) THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_pro_id)
       OR (blocker_id = p_pro_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  RETURN QUERY
  SELECT a.day, a.period FROM pro_availabilities a
  WHERE a.pro_id = p_pro_id AND a.day >= current_date
  ORDER BY a.day, a.period;
END;
$$;
REVOKE ALL ON FUNCTION get_pro_availability(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_pro_availability(UUID) TO authenticated;

-- ---------- (4i) get_pro_agenda (own — dispos + réservations, expire au passage) ----------
CREATE OR REPLACE FUNCTION get_pro_agenda(p_from DATE, p_to DATE)
RETURNS TABLE (
  kind TEXT,               -- 'availability' | 'booking'
  id UUID,
  day DATE,
  period TEXT,
  status TEXT,
  offering_id UUID,
  offering_title TEXT,
  party_size INTEGER,
  client_id UUID,
  client_name TEXT,        -- display_name Junto OU manual_name
  manual_phone TEXT,
  message TEXT,
  is_manual BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  PERFORM private.assert_approved_pro(v_user_id);
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from
     OR p_to > p_from + INTERVAL '12 months' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Expiration paresseuse : les pending dont la date est passée.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'expired'
  WHERE pro_id = v_user_id AND status = 'pending' AND bookings.day < current_date;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT 'availability'::TEXT, a.id, a.day, a.period, NULL::TEXT,
         NULL::UUID, NULL::TEXT, NULL::INTEGER, NULL::UUID, NULL::TEXT, NULL::TEXT,
         NULL::TEXT, NULL::BOOLEAN
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL)
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN public_profiles pp ON pp.id = b.client_id
  WHERE b.pro_id = v_user_id
    AND b.day BETWEEN p_from AND p_to
    AND b.status IN ('pending', 'accepted')
  ORDER BY 3, 4;
END;
$$;
REVOKE ALL ON FUNCTION get_pro_agenda(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_pro_agenda(DATE, DATE) TO authenticated;

-- ---------- (4j) get_my_bookings (client) ----------
CREATE OR REPLACE FUNCTION get_my_bookings()
RETURNS TABLE (
  id UUID,
  offering_id UUID,
  offering_title TEXT,
  pro_id UUID,
  pro_name TEXT,
  day DATE,
  period TEXT,
  party_size INTEGER,
  status TEXT,
  conversation_id UUID,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE bookings SET status = 'expired'
  WHERE client_id = v_user_id AND status = 'pending' AND bookings.day < current_date;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  RETURN QUERY
  SELECT b.id, b.offering_id, po.title, b.pro_id, pp.display_name,
         b.day, b.period, b.party_size, b.status,
         (SELECT c.id FROM conversations c
          WHERE c.type = 'dm' AND c.status = 'active'
            AND c.user_1 = LEAST(v_user_id, b.pro_id)
            AND c.user_2 = GREATEST(v_user_id, b.pro_id)),
         b.created_at
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN public_profiles pp ON pp.id = b.pro_id
  WHERE b.client_id = v_user_id
  ORDER BY b.day DESC, b.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION get_my_bookings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_bookings() TO authenticated;

-- ---------- (5) Garde-fous : pas de suppression avec réservations vivantes ----------
CREATE OR REPLACE FUNCTION delete_pro_offering(p_offering_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- 00416 : refuser tant que des réservations futures vivantes existent.
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE offering_id = p_offering_id
      AND status IN ('pending', 'accepted')
      AND day >= current_date
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  DELETE FROM pro_offerings WHERE id = p_offering_id;
END;
$$;

CREATE OR REPLACE FUNCTION unregister_as_pro()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- 00416 : refuser tant que des réservations futures vivantes existent
  -- (le CASCADE pro_profiles → pro_offerings → bookings serait silencieux).
  IF EXISTS (
    SELECT 1 FROM bookings
    WHERE pro_id = v_user_id
      AND status IN ('pending', 'accepted')
      AND day >= current_date
  ) THEN
    RAISE EXCEPTION 'junto.offering_has_bookings';
  END IF;

  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$$;

-- ---------- (6) Préférences de notifications : 4 nouveaux types ----------
ALTER TABLE users
  ALTER COLUMN notification_preferences SET DEFAULT '{
    "join_request": true,
    "participant_joined": false,
    "request_accepted": true,
    "request_refused": true,
    "participant_removed": true,
    "participant_left": false,
    "participant_left_late": true,
    "activity_cancelled": true,
    "activity_updated": false,
    "rate_participants": true,
    "presence_pre_warning": true,
    "presence_pre_warning_10min": true,
    "presence_validate_warning": true,
    "presence_validate_overdue": true,
    "presence_confirmed": true,
    "badge_unlocked": true,
    "qr_create_reminder": true,
    "peer_review_closing": true,
    "seat_request": true,
    "seat_request_accepted": true,
    "seat_request_declined": true,
    "seat_request_expired": true,
    "driver_left": true,
    "contact_request": true,
    "contact_request_accepted": true,
    "alert_match": true,
    "review_received": true,
    "review_reply": true,
    "booking_request": true,
    "booking_accepted": true,
    "booking_declined": true,
    "booking_cancelled": true
  }'::jsonb;

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET notification_preferences =
    '{"booking_request": true, "booking_accepted": true, "booking_declined": true, "booking_cancelled": true}'::jsonb
    || notification_preferences
  WHERE notification_preferences IS NOT NULL
    AND NOT (notification_preferences ? 'booking_request');
END;
$$;
