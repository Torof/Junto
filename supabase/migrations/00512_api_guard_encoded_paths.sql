-- ============================================================================
-- 00512 — TX-2 (HIGH) : le filtre d'API de 00504 se contournait avec un chemin
-- encodé (« /spatial%5Fref%5Fsys », « /%73patial_ref_sys » : PostgREST route
-- sur le chemin décodé mais expose le chemin brut). Vérifié en réel : DELETE
-- accepté (204). Désormais : toute écriture dont le chemin contient un « % »
-- est refusée (l'app n'en envoie jamais), barres obliques normalisées, et les
-- noms protégés sont cherchés n'importe où dans le chemin.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.junto_pre_request()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_method TEXT := upper(coalesce(current_setting('request.method', true), 'GET'));
  v_path TEXT := lower(regexp_replace(coalesce(current_setting('request.path', true), ''), '/+', '/', 'g'));
BEGIN
  IF v_method IN ('GET', 'HEAD', 'OPTIONS') THEN RETURN; END IF;
  IF position('%' in v_path) > 0
     OR v_path ~ '(^|/)(spatial_ref_sys|geometry_columns|geography_columns)(/|$|\?)' THEN
    RAISE EXCEPTION 'Operation not permitted' USING ERRCODE = '42501';
  END IF;
END;
$function$;
