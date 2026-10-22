-- ============================================================================
-- 00422 — Chantiers pro A + B (maquette validée Scott 2026-09-29).
--   A · Matériel sur l'offre : equipment_provided / equipment_required
--       (listes libres, affichage fiche offre + rappel billet client).
--   B · Fiche participant : le pro choisit les champs par offre
--       (participant_fields) ; le client remplit APRÈS confirmation
--       (bookings.participant_info) ; le pro lit dans sa fiche jour.
--   Compat : AUCUN DROP des RPC d'offres existantes (create/update_pro_offering
--   restent telles quelles — le build production continue de marcher) ; une
--   RPC dédiée set_offering_details porte les nouveaux champs.
-- ============================================================================

-- ---------- (1) Colonnes ----------
ALTER TABLE pro_offerings
  ADD COLUMN IF NOT EXISTS equipment_provided JSONB NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(equipment_provided) = 'array'),
  ADD COLUMN IF NOT EXISTS equipment_required JSONB NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(equipment_required) = 'array'),
  ADD COLUMN IF NOT EXISTS participant_fields JSONB NOT NULL DEFAULT '{"std":[],"custom":[]}'::jsonb
    CHECK (jsonb_typeof(participant_fields) = 'object');

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS participant_info JSONB
    CHECK (participant_info IS NULL OR jsonb_typeof(participant_info) = 'array');
-- participant_info n'entre PAS dans la whitelist bookings : aucune policy
-- d'écriture client n'existe (writes 100 % RPC), la RPC dédiée écrit sous
-- bypass comme les autres.

-- ---------- (2) set_offering_details — matériel + champs demandés ----------
-- Chaîne : auth → non suspendu → tier pro → profil existe → ownership →
-- validation stricte (listes ≤15 items ≤60 car. strip HTML ; std ⊆ catalogue ;
-- custom ≤3 questions ≤80 car. strip) → bypass UPDATE.
CREATE FUNCTION set_offering_details(
  p_offering_id UUID,
  p_equipment_provided TEXT[],
  p_equipment_required TEXT[],
  p_participant_std TEXT[],
  p_participant_custom TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_provided JSONB := '[]'::jsonb;
  v_required JSONB := '[]'::jsonb;
  v_std JSONB := '[]'::jsonb;
  v_custom JSONB := '[]'::jsonb;
  v_item TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Matériel : listes libres, 15 items max, 60 car. max, HTML strippé.
  IF coalesce(array_length(p_equipment_provided, 1), 0) > 15
     OR coalesce(array_length(p_equipment_required, 1), 0) > 15 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  FOREACH v_item IN ARRAY coalesce(p_equipment_provided, '{}') LOOP
    v_item := nullif(regexp_replace(trim(v_item), '<[^>]*>', '', 'g'), '');
    IF v_item IS NULL THEN CONTINUE; END IF;
    IF char_length(v_item) > 60 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_provided := v_provided || to_jsonb(v_item);
  END LOOP;
  FOREACH v_item IN ARRAY coalesce(p_equipment_required, '{}') LOOP
    v_item := nullif(regexp_replace(trim(v_item), '<[^>]*>', '', 'g'), '');
    IF v_item IS NULL THEN CONTINUE; END IF;
    IF char_length(v_item) > 60 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_required := v_required || to_jsonb(v_item);
  END LOOP;

  -- Fiche participant : champs standard ⊆ catalogue, questions libres ≤3.
  IF coalesce(array_length(p_participant_std, 1), 0) > 5
     OR coalesce(array_length(p_participant_custom, 1), 0) > 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  FOREACH v_item IN ARRAY coalesce(p_participant_std, '{}') LOOP
    IF v_item NOT IN ('shoe_size', 'height', 'weight', 'age', 'level') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF NOT v_std ? v_item THEN v_std := v_std || to_jsonb(v_item); END IF;
  END LOOP;
  FOREACH v_item IN ARRAY coalesce(p_participant_custom, '{}') LOOP
    v_item := nullif(regexp_replace(trim(v_item), '<[^>]*>', '', 'g'), '');
    IF v_item IS NULL THEN CONTINUE; END IF;
    IF char_length(v_item) > 80 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    v_custom := v_custom || to_jsonb(v_item);
  END LOOP;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_offerings
  SET equipment_provided = v_provided,
      equipment_required = v_required,
      participant_fields = jsonb_build_object('std', v_std, 'custom', v_custom),
      updated_at = now()
  WHERE id = p_offering_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;
REVOKE ALL ON FUNCTION set_offering_details(UUID, TEXT[], TEXT[], TEXT[], TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_offering_details(UUID, TEXT[], TEXT[], TEXT[], TEXT[]) TO authenticated;

-- ---------- (3) set_booking_participant_info — le client remplit sa fiche ----------
-- Chaîne : auth → non suspendu → booking FOR UPDATE → caller = client de LA
-- réservation (ou le pro pour une résa manuelle sans compte) → status accepted
-- (la fiche se remplit APRÈS confirmation — décision maquette) → date non
-- passée → validation stricte contre les champs demandés par l'offre →
-- bypass UPDATE. Les données ne sont relues QUE par get_pro_agenda (le pro
-- concerné) et get_my_bookings (le client lui-même).
CREATE FUNCTION set_booking_participant_info(
  p_booking_id UUID,
  p_info JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

  v_fields := coalesce(v_bk.fields, '{"std":[],"custom":[]}'::jsonb);
  v_allowed_std := coalesce(v_fields->'std', '[]'::jsonb);
  v_allowed_custom := coalesce(v_fields->'custom', '[]'::jsonb);
  IF jsonb_array_length(v_allowed_std) = 0 AND jsonb_array_length(v_allowed_custom) = 0 THEN
    RAISE EXCEPTION 'Operation not permitted'; -- l'offre ne demande pas de fiche
  END IF;

  -- Validation : tableau ≤ party_size ; par participant, un objet dont les
  -- clés ⊆ champs std demandés (valeurs texte ≤ 30) + 'custom' (objet
  -- question⊆demandées → réponse ≤ 120). Tout est strippé.
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
  UPDATE bookings SET participant_info = p_info WHERE id = p_booking_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;
REVOKE ALL ON FUNCTION set_booking_participant_info(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_booking_participant_info(UUID, JSONB) TO authenticated;

-- ---------- (4) Vue coords : + les 3 colonnes (fiche offre client) ----------
CREATE OR REPLACE VIEW pro_offerings_with_coords AS
SELECT
  o.id,
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
  (
    SELECT photo_url
    FROM pro_offering_photos p
    WHERE p.offering_id = o.id
    ORDER BY order_index ASC
    LIMIT 1
  ) AS image_url,
  o.created_at,
  o.updated_at,
  ST_X(o.location::geometry) AS lng,
  ST_Y(o.location::geometry) AS lat,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  pp.display_name AS pro_name,
  o.price_eur,
  o.price_unit,
  o.min_participants,
  o.equipment_provided,
  o.equipment_required,
  o.participant_fields
FROM pro_offerings o
JOIN sports s ON o.sport_id = s.id
JOIN pro_profiles pp ON o.pro_id = pp.user_id
WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.id = o.pro_id AND u.suspended_at IS NOT NULL
)
AND (o.is_demo = false OR demo_content_visible());

-- ---------- (5) get_pro_agenda : + participant_fields / participant_info ----------
DROP FUNCTION get_pro_agenda(DATE, DATE);
CREATE FUNCTION get_pro_agenda(p_from DATE, p_to DATE)
RETURNS TABLE (
  kind TEXT,
  id UUID,
  day DATE,
  period TEXT,
  status TEXT,
  offering_id UUID,
  offering_title TEXT,
  party_size INTEGER,
  client_id UUID,
  client_name TEXT,
  manual_phone TEXT,
  message TEXT,
  is_manual BOOLEAN,
  sport_key TEXT,
  sport_category TEXT,
  participant_fields JSONB,
  participant_info JSONB
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
$$;
REVOKE ALL ON FUNCTION get_pro_agenda(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_pro_agenda(DATE, DATE) TO authenticated;

-- ---------- (6) get_my_bookings : + fiche (à remplir / remplie) + matériel ----------
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
  sport_category TEXT,
  equipment_required JSONB,
  participant_fields JSONB,
  participant_info JSONB
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
         s.key::TEXT, s.category::TEXT,
         po.equipment_required, po.participant_fields, b.participant_info
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
