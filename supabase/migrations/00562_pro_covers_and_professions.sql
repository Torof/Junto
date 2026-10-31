-- ============================================================================
-- 00562 — Couvertures choisies par le pro + plusieurs métiers (Scott 2026-10-31).
--
--   (1) Couverture : pro_profiles.cover_url et pro_offerings.cover_url. La
--       couverture n'est plus « la première photo » : c'est le pro qui la
--       choisit, sinon pas de photo (teinte + picto). Écrites uniquement par
--       set_pro_cover / set_offering_cover, URL ancrée au dossier du pro
--       (private.pro_photo_url_ok, comme le pin). pro_offerings_with_coords.
--       image_url = la couverture choisie. Reprise : la couverture actuelle de
--       chaque page et sortie (= sa première photo) est recopiée, rien ne
--       disparaît. Une photo de galerie supprimée qui servait de couverture
--       vide la couverture (pas d'image cassée).
--
--   (2) Métiers : pro_profiles.professions text[] (liste fermée, sans
--       doublon). Le premier est le métier mis en avant (pin, page) et reste
--       recopié dans `profession` — les clients déjà publiés lisent toujours
--       cette colonne. Écrit par set_pro_professions (propriétaire, tout
--       statut : le formulaire d'inscription s'en sert). Un client ancien qui
--       ne change que `profession` via update_pro_profile garde une liste
--       cohérente (trigger de synchro).
--
--   (3) admin_get_pending_pro_applications renvoie aussi `professions`.
-- ============================================================================

-- (1) Couvertures --------------------------------------------------------------
ALTER TABLE public.pro_profiles ADD COLUMN cover_url text
  CONSTRAINT pro_profiles_cover_url_len CHECK (cover_url IS NULL OR char_length(cover_url) <= 1000);
ALTER TABLE public.pro_offerings ADD COLUMN cover_url text
  CONSTRAINT pro_offerings_cover_url_len CHECK (cover_url IS NULL OR char_length(cover_url) <= 1000);

-- Colonnes privilégiées : seules les fonctions ci-dessous les écrivent.
-- (Aucune écriture client sur ces tables ; défense en profondeur.)
GRANT SELECT(cover_url) ON TABLE public.pro_profiles TO authenticated;

UPDATE public.pro_profiles pp SET cover_url = (
  SELECT ph.photo_url FROM public.pro_profile_photos ph
  WHERE ph.pro_id = pp.user_id ORDER BY ph.order_index LIMIT 1
) WHERE pp.cover_url IS NULL;

UPDATE public.pro_offerings o SET cover_url = (
  SELECT ph.photo_url FROM public.pro_offering_photos ph
  WHERE ph.offering_id = o.id ORDER BY ph.order_index LIMIT 1
) WHERE o.cover_url IS NULL;

CREATE FUNCTION public.set_pro_cover(p_url text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- NULL retire ; sinon URL ancrée au dossier du caller.
  IF p_url IS NOT NULL AND NOT private.pro_photo_url_ok(p_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET cover_url = p_url WHERE user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.set_pro_cover(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pro_cover(text) TO authenticated;

CREATE FUNCTION public.set_offering_cover(p_offering_id uuid, p_url text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_url IS NOT NULL AND NOT private.pro_photo_url_ok(p_url, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_offerings SET cover_url = p_url WHERE id = p_offering_id AND pro_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.set_offering_cover(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_offering_cover(uuid, text) TO authenticated;

-- Une photo de galerie supprimée qui servait de couverture la vide.
CREATE FUNCTION public.clear_cover_on_photo_delete()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF TG_TABLE_NAME = 'pro_offering_photos' THEN
    UPDATE pro_offerings SET cover_url = NULL WHERE id = OLD.offering_id AND cover_url = OLD.photo_url;
  ELSE
    UPDATE pro_profiles SET cover_url = NULL WHERE user_id = OLD.pro_id AND cover_url = OLD.photo_url;
  END IF;
  RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.clear_cover_on_photo_delete() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pro_offering_photos_clear_cover AFTER DELETE ON public.pro_offering_photos
  FOR EACH ROW EXECUTE FUNCTION public.clear_cover_on_photo_delete();
CREATE TRIGGER pro_profile_photos_clear_cover AFTER DELETE ON public.pro_profile_photos
  FOR EACH ROW EXECUTE FUNCTION public.clear_cover_on_photo_delete();

-- image_url = la couverture choisie (définition live reprise telle quelle,
-- seule l'expression de image_url change).
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
    extensions.st_x((o.location)::extensions.geometry) AS lng,
    extensions.st_y((o.location)::extensions.geometry) AS lat,
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
   FROM ((public.pro_offerings o
     JOIN public.sports s ON ((o.sport_id = s.id)))
     JOIN public.pro_profiles pp ON ((o.pro_id = pp.user_id)))
  WHERE ((NOT (EXISTS ( SELECT 1
           FROM public.users u
          WHERE ((u.id = o.pro_id) AND (u.suspended_at IS NOT NULL))))) AND ((o.is_demo = false) OR public.demo_content_visible()) AND ((pp.status = 'approved'::text) OR (o.pro_id = auth.uid())));

-- (2) Plusieurs métiers ----------------------------------------------------------
ALTER TABLE public.pro_profiles ADD COLUMN professions text[] NOT NULL DEFAULT '{}'::text[];
ALTER TABLE public.pro_profiles ADD CONSTRAINT pro_profiles_professions_check CHECK (
  professions <@ ARRAY[
    'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
    'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
    'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other'
  ]::text[]
  AND cardinality(professions) <= 13
);
GRANT SELECT(professions) ON TABLE public.pro_profiles TO authenticated;

UPDATE public.pro_profiles SET professions = ARRAY[profession]
WHERE profession IS NOT NULL AND cardinality(professions) = 0;

-- `profession` = le premier de la liste. Un client qui ne change que
-- `profession` (builds publiés, update_pro_profile) le place en tête.
CREATE FUNCTION public.pro_profiles_sync_professions()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.professions IS NOT DISTINCT FROM OLD.professions
     AND NEW.profession IS DISTINCT FROM OLD.profession THEN
    NEW.professions := CASE WHEN NEW.profession IS NULL THEN '{}'::text[]
                            ELSE ARRAY[NEW.profession] || array_remove(OLD.professions, NEW.profession) END;
  ELSIF TG_OP = 'INSERT' AND cardinality(NEW.professions) = 0 AND NEW.profession IS NOT NULL THEN
    NEW.professions := ARRAY[NEW.profession];
  END IF;
  NEW.profession := NEW.professions[1];
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.pro_profiles_sync_professions() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER pro_profiles_sync_professions_trg BEFORE INSERT OR UPDATE ON public.pro_profiles
  FOR EACH ROW EXECUTE FUNCTION public.pro_profiles_sync_professions();

CREATE FUNCTION public.set_pro_professions(p_professions text[])
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_list text[];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Dédoublonné en gardant l'ordre (le premier = mis en avant).
  SELECT coalesce(array_agg(x ORDER BY first_pos), '{}'::text[]) INTO v_list
  FROM (SELECT x, min(ord) AS first_pos
        FROM unnest(coalesce(p_professions, '{}'::text[])) WITH ORDINALITY AS t(x, ord)
        GROUP BY x) d;

  IF NOT (v_list <@ ARRAY[
    'mountain_guide', 'mountain_leader', 'climbing_instructor', 'canyoning_instructor',
    'paragliding_instructor', 'ski_instructor', 'mtb_instructor', 'whitewater_instructor',
    'diving_instructor', 'surf_instructor', 'wellness_instructor', 'school_office', 'other'
  ]::text[]) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE pro_profiles SET professions = v_list WHERE user_id = v_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.set_pro_professions(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pro_professions(text[]) TO authenticated;

-- (3) Fiche admin + métiers ------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_get_pending_pro_applications();

CREATE FUNCTION public.admin_get_pending_pro_applications()
RETURNS TABLE(
  user_id uuid, display_name text, company_name text, real_name text,
  profession text, professions text[], tagline text, description text,
  email text, phone text, website text, instagram text, facebook text,
  primary_location_name text, primary_lng double precision, primary_lat double precision,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  account_created_at timestamp with time zone,
  prior_review_count integer, last_review_action text, last_review_at timestamp with time zone
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions
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

  RETURN QUERY
  SELECT pp.user_id, pp.display_name, pp.company_name, pp.real_name,
         pp.profession, pp.professions, pp.tagline, pp.description,
         pp.email, pp.phone, pp.website, pp.instagram, pp.facebook,
         pp.primary_location_name,
         extensions.st_x(pp.primary_location::extensions.geometry),
         extensions.st_y(pp.primary_location::extensions.geometry),
         pp.created_at, pp.updated_at,
         u.created_at,
         coalesce(h.cnt, 0)::INTEGER, h.last_action, h.last_at
  FROM pro_profiles pp
  JOIN users u ON u.id = pp.user_id
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
REVOKE ALL ON FUNCTION public.admin_get_pending_pro_applications() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_pending_pro_applications() TO authenticated;
