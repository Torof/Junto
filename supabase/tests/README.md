# Tests automatiques de la base

Lancer : `npm run test:db` (tout) ou `npm run test:db -- identite` (un fichier).

- Chaque fichier `NN_domaine.test.sql` joue des scénarios **en se faisant passer pour des utilisateurs** (compte normal, suspendu, admin, démo, visiteur sans compte) sur la base liée, puis **tout est annulé** : aucun compte, aucune ligne, aucune notification ne reste. Le lanceur vérifie à la fin qu'aucun compte de test (`@junto.test`) n'a survécu.
- Pas de Docker ni de Postgres local : le lanceur passe par la ligne de commande Supabase (API d'administration).
- Résultats : `pass` (OK), `fail` (régression à corriger), `xfail` (faille connue d'un audit, attendue en échec tant qu'elle n'est pas corrigée — l'identifiant renvoie aux documents d'audit), `xpass` (une faille connue ne se reproduit plus : corriger le test en retirant l'identifiant). Code de sortie non nul si `fail`, `xpass`, plantage ou résidu.
- Règles d'écriture : jamais de `COMMIT` / `ROLLBACK`, jamais d'appel direct à `net.*` ; uniquement les utilitaires de `_prelude.sql` (`pg_temp.user`, `as_`, `ok`, `denied`, `eq`).
- Identifiants des défauts trouvés par les tests eux-mêmes : `DB-n` (voir docs/AUDIT_COMPLET_2026-10.md).
