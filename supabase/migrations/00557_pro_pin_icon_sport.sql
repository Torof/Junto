-- ============================================================================
-- 00557 — Pin de la page pro : le picto s'élargit (Scott 2026-10-26, DECISIONS
-- « Pin de la page pro : l'écusson » + « métier et choix élargi »).
--
--   pro_profiles.pin_icon disait l'univers (5 valeurs). Désormais quatre voies
--   pour le pin : NULL = le picto du MÉTIER (profession, défaut), une clé
--   d'univers (les 5 glyphes), une clé de SPORT du catalogue (le picto de la
--   sortie), ou la photo (pin_image_url, inchangé). La teinte de l'écusson se
--   déduit côté app (métier → univers, sport → catégorie).
--
--   Le CHECK de colonne devient un contrôle de forme ; la liste vit dans
--   set_pro_pin_icon (seule écriture : aucun grant client sur la colonne),
--   comme profession dans update_pro_profile. Signature inchangée → CREATE OR
--   REPLACE garde le GRANT authenticated (S2 du test 13 intact). Rebâtie
--   depuis la définition live (00281, 00461) ; search_path complété.
-- ============================================================================

ALTER TABLE public.pro_profiles DROP CONSTRAINT pro_profiles_pin_icon_check;
ALTER TABLE public.pro_profiles
  ADD CONSTRAINT pro_profiles_pin_icon_check CHECK (pin_icon IS NULL OR pin_icon ~ '^[a-z][a-z0-9-]{1,31}$');

CREATE OR REPLACE FUNCTION public.set_pro_pin_icon(p_pin_icon text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- NULL = métier ; un univers ; ou un sport actif du catalogue.
  IF p_pin_icon IS NOT NULL
     AND p_pin_icon NOT IN ('mountain', 'water', 'air', 'cycling', 'wellness')
     AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = p_pin_icon AND s.is_active) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_icon = p_pin_icon WHERE user_id = v_user_id;
END;
$function$;
