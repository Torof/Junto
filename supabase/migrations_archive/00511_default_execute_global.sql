-- ============================================================================
-- 00511 — 00510 suite : le droit d'exécution donné à PUBLIC sur toute nouvelle
-- fonction est un défaut GLOBAL de PostgreSQL ; il ne se retire pas schéma par
-- schéma. Retiré globalement pour le rôle propriétaire de nos objets
-- (postgres) — service_role garde son droit par le défaut du schéma.
-- ============================================================================

ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
