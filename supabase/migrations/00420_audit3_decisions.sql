-- ============================================================================
-- 00420 — AUDIT 2026-09 : les 3 décisions produit (déléguées à Claude,
-- Scott 2026-09-27 : « résous-les de la façon la plus sensible »).
--
--   D1  Cancels suspendus → BLOQUER + AUTO-ANNULATION à la suspension.
--       Doctrine maison : toute RPC commence par auth + suspension (les deux
--       cancel_booking* étaient l'anomalie). Et un suspendu qui garde des
--       réservations vivantes laisse des pros attendre quelqu'un qui ne peut
--       plus ni chatter ni être fiable → admin_suspend_user annule ses
--       réservations futures (2 sens) + notifie les contreparties (copy
--       neutre : la suspension n'est JAMAIS révélée à un tiers).
--   D2  Blanchiment d'avis (M5) → surfacer l'historique admin_actions dans
--       la file d'approbation : admin_get_pending_pro_applications renvoie
--       le nombre d'anciens approve/reject + le dernier + sa date. L'admin
--       voit « déjà approuvé puis reparti » AVANT de re-valider.
--   D3  booking_expired → NOTIFIER le client. Logistique (comme le decline
--       notifié, déviation assumée sprint-booking) et actionnable : il peut
--       redemander un autre créneau. Émise au flip lazy côté pro
--       (get_pro_agenda) ; le flip côté client (get_my_bookings) reste
--       silencieux — il a l'info sous les yeux.
-- ============================================================================

-- ---------- D1a : suspension check sur les deux cancels ----------
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
  -- 00420 D1 : un suspendu n'annule plus lui-même — ses réservations ont été
  -- auto-annulées à la suspension (admin_suspend_user).
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.client_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

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
  -- 00420 D1 : idem côté pro.
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_bk FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_bk IS NULL OR v_bk.pro_id != v_user_id
     OR v_bk.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

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

-- ---------- D1b : auto-annulation des réservations futures à la suspension ----------
CREATE OR REPLACE FUNCTION admin_suspend_user(p_user_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
      AND b.day >= current_date
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
          jsonb_build_object('booking_id', v_bk.b_id, 'by', 'pro')
        );
      END IF;
    ELSIF v_bk.b_status = 'accepted' THEN
      PERFORM create_notification(
        v_bk.b_pro,
        'booking_cancelled',
        'Réservation annulée',
        'La réservation de « ' || coalesce(v_bk.b_title, 'une sortie') || ' » du '
          || to_char(v_bk.b_day, 'DD/MM') || ' a été annulée.',
        jsonb_build_object('booking_id', v_bk.b_id, 'by', 'client')
      );
    END IF;
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM log_admin_action(v_admin, 'suspend_user', 'user', p_user_id, v_reason, NULL);
END;
$$;

-- ---------- D2 : historique admin dans la file d'approbation pro ----------
DROP FUNCTION admin_get_pending_pro_applications();
CREATE FUNCTION admin_get_pending_pro_applications()
RETURNS TABLE (
  user_id UUID, display_name TEXT, company_name TEXT, real_name TEXT,
  email TEXT, phone TEXT, website TEXT, primary_location_name TEXT,
  created_at TIMESTAMPTZ,
  prior_review_count INTEGER,   -- anciens approve/reject sur CE user
  last_review_action TEXT,      -- 'approve_pro' | 'reject_pro' | NULL
  last_review_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00420 D2 (contre-mesure blanchiment M5) : un pro qui a déjà été
  -- approuvé/refusé puis s'est désinscrit (CASCADE avis/photos) réapparaît
  -- ici avec son passif visible — l'admin re-valide en connaissance de cause.
  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.email, pp.phone, pp.website, pp.primary_location_name, pp.created_at,
         coalesce(h.cnt, 0)::INTEGER, h.last_action, h.last_at
  FROM pro_profiles pp
  LEFT JOIN LATERAL (
    SELECT count(*)::INTEGER AS cnt,
           (ARRAY_AGG(a.action ORDER BY a.created_at DESC))[1] AS last_action,
           max(a.created_at) AS last_at
    FROM admin_actions a
    WHERE a.target_id = pp.user_id
      AND a.action IN ('approve_pro', 'reject_pro')
  ) h ON true
  WHERE pp.status = 'pending'
  ORDER BY pp.created_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION admin_get_pending_pro_applications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_get_pending_pro_applications() TO authenticated;

-- ---------- D3 : notif booking_expired au flip lazy côté pro ----------
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

  -- Expiration paresseuse : les pending dont la date est passée.
  -- 00420 D3 : le client Junto est prévenu (logistique + actionnable — il
  -- peut redemander un créneau). Les résas manuelles (client_id NULL) non.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  FOR v_flip IN
    WITH flipped AS (
      UPDATE bookings SET status = 'expired'
      WHERE bookings.pro_id = v_user_id AND bookings.status = 'pending'
        AND bookings.day < current_date
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
        || to_char(v_flip.b_day, 'DD/MM') || ' ' || v_period_label
        || ' a expiré sans réponse. Tu peux demander un autre créneau.',
      jsonb_build_object('booking_id', v_flip.b_id, 'offering_id', v_flip.b_off)
    );
  END LOOP;
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

-- ---------- D3 : préférence booking_expired (default + backfill, pattern 00417) ----------
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
    "booking_cancelled": true,
    "booking_expired": true
  }'::jsonb;

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET notification_preferences =
    '{"booking_expired": true}'::jsonb || notification_preferences
  WHERE notification_preferences IS NOT NULL
    AND NOT (notification_preferences ? 'booking_expired');
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
