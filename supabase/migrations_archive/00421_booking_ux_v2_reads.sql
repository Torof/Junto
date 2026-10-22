-- ============================================================================
-- 00421 — Booking UX v2 (maquette validée Scott 2026-09-28) : lectures
-- enrichies + écriture bulk des dispos.
--   (1) get_pro_availability : + `taken` (places prises par créneau — affichage
--       INFORMATIF côté client ; la capacité reste non bloquante, décision v1)
--   (2) get_pro_agenda : + sport_key / sport_category (code couleur univers
--       sur le calendrier pro)
--   (3) get_my_bookings : + lieu / prix / sport (carte « billet » côté client)
--   (4) set_pro_availability_bulk : raccourcis d'ouverture de saison
--       (week-ends, mois, copie de semaine) sans 60 appels réseau
-- ============================================================================

-- ---------- (1) get_pro_availability + taken ----------
DROP FUNCTION get_pro_availability(UUID);
CREATE FUNCTION get_pro_availability(p_pro_id UUID)
RETURNS TABLE (day DATE, period TEXT, taken INTEGER)
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
  WHERE a.pro_id = p_pro_id AND a.day >= current_date
  ORDER BY a.day, a.period;
END;
$$;
REVOKE ALL ON FUNCTION get_pro_availability(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_pro_availability(UUID) TO authenticated;

-- ---------- (2) get_pro_agenda + sport (base 00420 : notif booking_expired conservée) ----------
DROP FUNCTION get_pro_agenda(DATE, DATE);
CREATE FUNCTION get_pro_agenda(p_from DATE, p_to DATE)
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
  is_manual BOOLEAN,
  sport_key TEXT,
  sport_category TEXT
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

  -- Expiration paresseuse + notif client (00420 D3).
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
         NULL::TEXT, NULL::BOOLEAN, NULL::TEXT, NULL::TEXT
  FROM pro_availabilities a
  WHERE a.pro_id = v_user_id AND a.day BETWEEN p_from AND p_to
  UNION ALL
  SELECT 'booking'::TEXT, b.id, b.day, b.period, b.status,
         b.offering_id, po.title, b.party_size, b.client_id,
         coalesce(pp.display_name, b.manual_name),
         b.manual_phone, b.message, (b.client_id IS NULL),
         s.key::TEXT, s.category::TEXT
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
REVOKE ALL ON FUNCTION get_pro_agenda(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_pro_agenda(DATE, DATE) TO authenticated;

-- ---------- (3) get_my_bookings + lieu / prix / sport (base 00416, flip silencieux) ----------
DROP FUNCTION get_my_bookings();
CREATE FUNCTION get_my_bookings()
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
  created_at TIMESTAMPTZ,
  location_name TEXT,
  price_eur NUMERIC,
  price_unit TEXT,
  sport_key TEXT,
  sport_category TEXT
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
         b.created_at,
         po.location_name, po.price_eur, po.price_unit::TEXT,
         s.key::TEXT, s.category::TEXT
  FROM bookings b
  JOIN pro_offerings po ON po.id = b.offering_id
  LEFT JOIN sports s ON s.id = po.sport_id
  LEFT JOIN public_profiles pp ON pp.id = b.pro_id
  WHERE b.client_id = v_user_id
  ORDER BY b.day DESC, b.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION get_my_bookings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_bookings() TO authenticated;

-- ---------- (4) set_pro_availability_bulk — raccourcis d'ouverture ----------
-- Chaîne : auth → assert_approved_pro → tableaux parallèles 1..200 → chaque
-- period ∈ am/pm, chaque date ∈ [aujourd'hui, +6 mois] → upsert/delete own.
-- Fermer un créneau ne touche JAMAIS les réservations (elles référencent
-- day/period, pas la ligne de dispo) — même sémantique que l'unitaire.
CREATE FUNCTION set_pro_availability_bulk(
  p_days DATE[],
  p_periods TEXT[],
  p_available BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    WHERE d IS NULL OR d < current_date OR d > current_date + INTERVAL '6 months'
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
$$;
REVOKE ALL ON FUNCTION set_pro_availability_bulk(DATE[], TEXT[], BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_pro_availability_bulk(DATE[], TEXT[], BOOLEAN) TO authenticated;
