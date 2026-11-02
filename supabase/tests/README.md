# Tests automatiques de la base

Lancer : `npm run test:db` (tout) ou `npm run test:db -- identite` (un fichier).

- Chaque fichier `NN_domaine.test.sql` joue des scénarios **en se faisant passer pour des utilisateurs** (compte normal, suspendu, admin, démo, visiteur sans compte) sur la base liée, puis **tout est annulé** : aucun compte, aucune ligne, aucune notification ne reste. Le lanceur vérifie à la fin qu'aucun compte de test (`@junto.test`) n'a survécu.
- Pas de Docker ni de Postgres local : le lanceur passe par la ligne de commande Supabase (API d'administration).
- Résultats : `pass` (OK), `fail` (régression à corriger), `xfail` (faille connue d'un audit, attendue en échec tant qu'elle n'est pas corrigée — l'identifiant renvoie aux documents d'audit), `xpass` (une faille connue ne se reproduit plus : corriger le test en retirant l'identifiant). Code de sortie non nul si `fail`, `xpass`, plantage ou résidu.
- Règles d'écriture : jamais de `COMMIT` / `ROLLBACK`, jamais d'appel direct à `net.*` ; uniquement les utilitaires de `_prelude.sql` (`pg_temp.user`, `as_`, `ok`, `denied`, `eq`).
- Identifiants des défauts trouvés par les tests eux-mêmes : `DB-n` (voir docs/AUDIT_COMPLET_2026-10.md). Audit pro de novembre 2026 (`BOOKINGS-n`, `SESSIONS-n`, `VITRINE-n`, `CALENDAR-n`, `GRANTS-n`, `CLIENT-1`, `DB-WP-1`, `DOC-WAYPOINTS`) : docs/AUDIT_PRO_2026-11.md — corrigés en 00578 (doc DOC-WAYPOINTS écrite) sauf `CALENDAR-7-PLATFORM` (droits du schéma `net`, propriété de `supabase_admin` : hors de notre portée, gardé en xfail). Seconde passe du même audit (`SESSIONS-A..D`, `BOOKINGS-R1..R4`, `VITRINE-5..7`, `CLIENT-1/3/4`, `GRANTS-2`) : corrigée en 00580, prouvée dans `22_pro_audit2` (GRANTS-2 dans `00_socle`, listes de fonctions dans `13_sweep_trous`).
