-- ============================================================================
-- 00502 — Hygiène des droits.
-- TX-4  Nouvelles tables de public : plus aucun droit d'écriture accordé par
--       défaut aux clients (SELECT reste, protégé par la RLS). Toute écriture
--       client passe par une fonction ou une policy explicite + GRANT explicite.
-- PV-3  Aucun TRUNCATE / TRIGGER / REFERENCES pour les clients sur les tables
--       existantes (TRUNCATE ignore la RLS).
-- PV-4  File d'envoi HTTP de pg_net : aucun droit pour les clients (si le rôle
--       de migration le permet ; la table appartient à supabase_admin).
-- ============================================================================

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon, authenticated;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT c.oid::regclass AS t FROM pg_class c
           WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p')
  LOOP
    BEGIN
      EXECUTE format('REVOKE TRUNCATE, TRIGGER, REFERENCES ON %s FROM anon, authenticated', r.t);
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE WARNING 'not owner of %, skipped', r.t;
    END;
  END LOOP;
END $$;

DO $$
BEGIN
  REVOKE ALL ON net.http_request_queue FROM anon, authenticated;
  REVOKE ALL ON net._http_response FROM anon, authenticated;
EXCEPTION WHEN insufficient_privilege OR undefined_table THEN
  RAISE WARNING 'pg_net tables: %', SQLERRM;
END $$;
