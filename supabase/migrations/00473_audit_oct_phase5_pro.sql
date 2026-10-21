-- ============================================================================
-- 00473 — Audit octobre 2026, phase 5 (docs/AUDIT_2026-10.md L13, L14).
-- Base = définitions vivantes (00422, 00444).
-- L13 set_booking_participant_info : les réponses sont stockées nettoyées
--     (balises HTML + caractères de contrôle), comme la doc le promettait.
-- L14 update_pro_profile : longueurs vérifiées APRÈS nettoyage (« <b></b> »
--     ne passe plus pour finir en chaîne vide sur une erreur de contrainte
--     brute) ; primary_location_name nettoyé comme les autres champs.
-- ============================================================================

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
  IF v_bk.day < current_date THEN RAISE EXCEPTION 'junto.booking_date'; END IF;

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
$function$;

CREATE OR REPLACE FUNCTION public.update_pro_profile(p_display_name text DEFAULT NULL::text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text, p_company_name text DEFAULT NULL::text, p_real_name text DEFAULT NULL::text, p_clear text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_existing RECORD;
  v_location_changing BOOLEAN := false;
  v_clear TEXT[] := COALESCE(p_clear, ARRAY[]::TEXT[]);
  v_col TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_existing IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00443 B3 : une fois APPROUVÉ, raison sociale et identité sont gelées —
  -- les renvoyer inchangées est permis, les changer passe par nous.
  IF v_existing.status = 'approved' THEN
    IF (p_company_name IS NOT NULL
        AND regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g') IS DISTINCT FROM v_existing.company_name)
       OR (p_real_name IS NOT NULL
        AND regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g') IS DISTINCT FROM v_existing.real_name) THEN
      RAISE EXCEPTION 'junto.pro_identity_locked';
    END IF;
  END IF;

  -- 00444 (1) : liste blanche des colonnes vidables. ≤ 7 entrées, toutes connues.
  IF array_length(v_clear, 1) > 7 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  FOREACH v_col IN ARRAY v_clear LOOP
    IF v_col IS NULL OR v_col NOT IN ('tagline', 'description', 'website', 'email', 'phone', 'instagram', 'facebook') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END LOOP;

  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00444 (2) : cooldown seulement pour une enseigne publique (approved).
    IF v_existing.status = 'approved'
       AND v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'junto.pro_location_cooldown';
    END IF;
    v_location_changing := true;
  END IF;

  IF p_display_name IS NOT NULL AND (char_length(regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g')) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g')) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g')) < 2 OR char_length(p_real_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(regexp_replace(trim(p_primary_location_name), '<[^>]*>', '', 'g')) < 1 OR char_length(p_primary_location_name) > 200) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET
    display_name = COALESCE(regexp_replace(trim(p_display_name), '<[^>]*>', '', 'g'), display_name),
    company_name = CASE WHEN p_company_name IS NOT NULL THEN regexp_replace(trim(p_company_name), '<[^>]*>', '', 'g') ELSE company_name END,
    real_name = CASE WHEN p_real_name IS NOT NULL THEN regexp_replace(trim(p_real_name), '<[^>]*>', '', 'g') ELSE real_name END,
    tagline = CASE WHEN 'tagline' = ANY(v_clear) THEN NULL
                   WHEN p_tagline IS NOT NULL THEN regexp_replace(trim(p_tagline), '<[^>]*>', '', 'g') ELSE tagline END,
    description = CASE WHEN 'description' = ANY(v_clear) THEN NULL
                       WHEN p_description IS NOT NULL THEN regexp_replace(trim(p_description), '<[^>]*>', '', 'g') ELSE description END,
    website = CASE WHEN 'website' = ANY(v_clear) THEN NULL ELSE COALESCE(p_website, website) END,
    email = CASE WHEN 'email' = ANY(v_clear) THEN NULL ELSE COALESCE(p_email, email) END,
    phone = CASE WHEN 'phone' = ANY(v_clear) THEN NULL ELSE COALESCE(p_phone, phone) END,
    instagram = CASE WHEN 'instagram' = ANY(v_clear) THEN NULL ELSE COALESCE(p_instagram, instagram) END,
    facebook = CASE WHEN 'facebook' = ANY(v_clear) THEN NULL ELSE COALESCE(p_facebook, facebook) END,
    primary_lng = CASE WHEN v_location_changing THEN p_primary_lng ELSE primary_lng END,
    primary_lat = CASE WHEN v_location_changing THEN p_primary_lat ELSE primary_lat END,
    primary_location = CASE WHEN v_location_changing
                            THEN ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography
                            ELSE primary_location END,
    primary_location_name = CASE WHEN v_location_changing THEN regexp_replace(trim(p_primary_location_name), '<[^>]*>', '', 'g') ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$function$;
