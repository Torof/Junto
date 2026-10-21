-- ============================================================================
-- 00510 — Re-sécurisation, lot 1 (droits et protections par défaut).
-- * users : protection des colonnes en LISTE BLANCHE (6 champs de profil
--   modifiables par le client ; toute autre colonne, y compris une colonne
--   ajoutée plus tard, est figée sauf fonction autorisée).
-- * Droits d'écriture inutiles retirés : sur chaque table de public, un client
--   ne garde INSERT / UPDATE / DELETE que si une policy l'autorise ; aucun
--   droit d'écriture pour anon.
-- * Fonctions : plus d'EXECUTE accordé par défaut aux clients sur une nouvelle
--   fonction (public et private) — une RPC client doit être accordée
--   explicitement ; fonctions de déclencheur et 4 utilitaires internes fermés
--   aux clients ; search_path fixé sur les utilitaires qui n'en avaient pas.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_user_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  -- 00510: WHITELIST, not a pin list — a client may change only its profile
  -- fields; every other column (including any column added later) keeps its
  -- old value unless a SECURITY DEFINER function sets junto.bypass_lock.
  NEW := jsonb_populate_record(OLD, jsonb_build_object(
    'display_name', NEW.display_name,
    'avatar_url', NEW.avatar_url,
    'bio', NEW.bio,
    'sports', NEW.sports,
    'notification_preferences', NEW.notification_preferences,
    'language', NEW.language));
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DO $$
DECLARE r RECORD; v_priv TEXT;
BEGIN
  FOR r IN SELECT c.oid, c.oid::regclass AS t, c.relname FROM pg_class c
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p')
             AND c.relname <> 'spatial_ref_sys'
  LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON %s FROM anon', r.t);
    FOREACH v_priv IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE'] LOOP
      IF NOT EXISTS (
        SELECT 1 FROM pg_policies p
        WHERE p.schemaname = 'public' AND p.tablename = r.relname
          AND p.cmd IN (v_priv, 'ALL')
          AND (p.roles && ARRAY['authenticated', 'public']::name[])
      ) THEN
        EXECUTE format('REVOKE %s ON %s FROM authenticated', v_priv, r.t);
      END IF;
    END LOOP;
  END LOOP;
END $$;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS f FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public', 'private') AND p.prorettype = 'trigger'::regtype
             AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.f);
  END LOOP;
END $$;

REVOKE EXECUTE ON FUNCTION public.badge_label_fr(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.badge_tier_for(integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sanitize_notif_text(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.is_messaging_eligible(uuid, uuid) FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.badge_label_fr(text, text) SET search_path = public;
ALTER FUNCTION public.badge_tier_for(integer) SET search_path = public;
ALTER FUNCTION public.reliability_tier(double precision) SET search_path = public;
ALTER FUNCTION public.sanitize_notif_text(text) SET search_path = public;
