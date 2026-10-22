-- ============================================================================
-- 00504 — TX-2 (HIGH) : filtre d'API sur les tables PostGIS.
-- spatial_ref_sys (et les vues geometry_columns / geography_columns)
-- appartiennent à supabase_admin : on ne peut ni retirer les droits d'écriture
-- de anon / authenticated, ni y activer la RLS. Un DELETE anonyme de
-- srid=4326 par l'API casserait toute requête géographique (carte, présence).
-- En attendant la migration (PostGIS déplacé dans « extensions »), PostgREST
-- refuse toute requête autre qu'une lecture sur ces chemins, avant même
-- d'exécuter quoi que ce soit (hook db_pre_request).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.junto_pre_request()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_method TEXT := upper(coalesce(current_setting('request.method', true), 'GET'));
  v_path TEXT := lower(coalesce(current_setting('request.path', true), ''));
BEGIN
  IF v_method NOT IN ('GET', 'HEAD', 'OPTIONS')
     AND v_path ~ '^/(spatial_ref_sys|geometry_columns|geography_columns)(/|$|\?)' THEN
    RAISE EXCEPTION 'Operation not permitted' USING ERRCODE = '42501';
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.junto_pre_request() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.junto_pre_request() TO anon, authenticated, service_role;

ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.junto_pre_request';
NOTIFY pgrst, 'reload config';
