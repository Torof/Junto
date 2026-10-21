-- ============================================================================
-- 00476 — URGENCE (audit complet 2026-10-21, ID-1, CRITIQUE) : les vues de
-- `public` héritaient des privilèges par défaut de Supabase (INSERT, UPDATE,
-- DELETE, TRUNCATE pour anon et authenticated). `public_profiles` est une vue
-- auto-modifiable sur `users`, possédée par postgres (BYPASSRLS) : n'importe
-- quel compte connecté pouvait réécrire le nom, la bio, l'avatar de n'importe
-- qui, ou supprimer n'importe quel compte (cascade sur ~40 tables). Confirmé
-- par un essai neutre annulé. L'app n'écrit jamais à travers une vue.
-- Correctif : toutes les vues de public deviennent en lecture seule pour les
-- rôles clients. Les SELECT existants sont inchangés.
-- ============================================================================
DO $$
DECLARE v RECORD;
BEGIN
  FOR v IN SELECT table_name FROM information_schema.views WHERE table_schema = 'public' LOOP
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.%I FROM anon, authenticated, PUBLIC', v.table_name);
  END LOOP;
END $$;
