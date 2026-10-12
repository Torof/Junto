-- ============================================================================
-- 00444 — update_pro_profile : champs vidables + cooldown enseigne lisible
-- (lot 1 du durcissement Pro, feu vert Scott 2026-10-12).
--
-- Base live : 00443 (elle-même 00278). Signature CHANGÉE (+ p_clear TEXT[])
-- → DROP de l'ancienne d'abord, sinon PGRST203 (surcharge ambiguë).
--
--   (1) p_clear TEXT[] : noms de colonnes à remettre à NULL. Jusqu'ici le
--       client envoyait undefined pour un champ vidé et la RPC faisait
--       COALESCE(p_x, x) → impossible de retirer un téléphone ou un Facebook
--       (vécu comme un bug : « je supprime, il revient »). Liste blanche
--       stricte : tagline, description, website, email, phone, instagram,
--       facebook. Tout autre nom → erreur générique (tentative de toucher
--       une colonne privilégiée ou obligatoire).
--   (2) Cooldown 30 j du déplacement de l'enseigne : seulement une fois
--       APPROUVÉ. Il démarrait à l'inscription (défaut de la colonne) et
--       bloquait un pro refusé qui doit corriger sa vallée. Un profil
--       pending/rejected n'est visible de personne : aucune surface d'abus.
--       Et le refus devient `junto.pro_location_cooldown` (user-actionable,
--       c'est son propre état) au lieu du générique — audit B12.
--
-- Chaîne (validée 2026-10-12) : auth → non suspendu → propre ligne FOR UPDATE
-- → gel identité si approved (00443) → p_clear ⊆ liste blanche → si lng/lat :
-- triple complet + bornes + cooldown 30 j si approved → longueurs → bypass
-- UPDATE (NULL = conserver, sauf colonnes de p_clear → NULL).
-- ============================================================================

DROP FUNCTION IF EXISTS update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION update_pro_profile(
  p_display_name TEXT DEFAULT NULL,
  p_tagline TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_website TEXT DEFAULT NULL,
  p_email TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_instagram TEXT DEFAULT NULL,
  p_facebook TEXT DEFAULT NULL,
  p_primary_lng FLOAT DEFAULT NULL,
  p_primary_lat FLOAT DEFAULT NULL,
  p_primary_location_name TEXT DEFAULT NULL,
  p_company_name TEXT DEFAULT NULL,
  p_real_name TEXT DEFAULT NULL,
  p_clear TEXT[] DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  IF p_display_name IS NOT NULL AND (char_length(trim(p_display_name)) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(trim(p_company_name)) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(trim(p_real_name)) < 2 OR char_length(p_real_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(trim(p_primary_location_name)) < 1 OR char_length(p_primary_location_name) > 200) THEN
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
    primary_location_name = CASE WHEN v_location_changing THEN trim(p_primary_location_name) ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_pro_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, TEXT, TEXT[]) TO authenticated;
