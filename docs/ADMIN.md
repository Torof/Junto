# Junto — Rôle Admin (charte)

Statut : **charte validée par Scott (2026-07-13)**. Définit ce que l'admin peut, doit, et ne doit jamais pouvoir faire. Toute évolution du pouvoir admin doit respecter cette charte. Issu de l'audit admin du 2026-07-13.

## Principe directeur

La tension est *efficacité de modération* vs *vie privée*. **Par défaut la vie privée gagne.** Le pouvoir admin n'est pas un « mode dieu » : ce sont des capacités **scopées** (liées à une action de modération précise), **auditées** (tout est journalisé : qui, quoi, cible, raison, quand), et **motivées** (une raison est exigée pour toute action lourde).

## Comment on devient admin

- `users.is_admin BOOLEAN NOT NULL DEFAULT false`.
- **Verrouillé** : `is_admin` est dans la whitelist du trigger `handle_user_update` (forcé à OLD). Aucun client ne peut se l'attribuer — même un `UPDATE users SET is_admin = true` est silencieusement annulé.
- Attribution **uniquement** via une session SQL superuser/service_role (SQL Editor du dashboard) avec `set_config('junto.bypass_lock','true',true)` puis `UPDATE users SET is_admin = TRUE …`. **Aucun chemin d'attribution depuis l'app**, et c'est voulu.

## Ce que l'admin PEUT faire (état actuel)

- **`sports`** : insert / update / delete (référentiel) — RLS `sports_*_admin`.
- **Signalements** : lire tous les `reports` (RLS `reports_select`) ; `moderate_report(...)` → classer `dismissed`/`actioned`, et suspendre un utilisateur.
- **Pros** : `approve_pro` / `reject_pro` ; voir les PP `pending`/`rejected` (RLS `pro_profiles_select`).
- **Blocages** : lire toutes les relations (`blocked_users_select_own` inclut l'admin).
- **Bypass** de la limite de création d'activités.

## Ce que l'admin ne DOIT JAMAIS pouvoir faire (frontières dures)

1. **Lire les messages privés (DM).** Jamais, même pour modérer. Si un DM est signalé, la **preuve est jointe par le signaleur** (capture/snapshot au moment du report) — on ne donne pas d'accès DM global.
2. **Se faire passer pour un utilisateur** (impersonation) — aucune fonction « agir en tant que ».
3. **Naviguer librement dans les données perso.** L'email / l'identité ne se révèlent que via un **lookup scopé à une action de modération** et **audité** — pas d'annuaire de tous les utilisateurs.
4. **S'auto-attribuer admin** (ou attribuer admin à un autre) depuis l'app — reste SQL/superuser.
5. **Modifier/supprimer du contenu sans laisser de trace** — toute action lourde passe par le journal d'audit.

Aujourd'hui, l'admin ne peut déjà PAS lire : DM, messages de mur des autres, emails/téléphone/date de naissance des autres, présence, activités privées. **Cette posture est à conserver.**

## Ce que l'admin DEVRAIT pouvoir faire (feuille de route)

Capacités manquantes identifiées par l'audit, toutes **auditées** :

- **Lookup propriété / identité** dans un contexte de modération : résoudre la cible d'un report (user / activité / PP / avis) en identité lisible (pseudo, email si nécessaire), et « qui possède cette PP / activité ».
- **Dé-suspension** + **suspension avec raison** (aujourd'hui : suspension sans raison, et aucune levée possible hors SQL brut).
- **Retrait de contenu** : masquer/supprimer une activité, un message de mur, un avis, une PP/offre abusive — avec **raison obligatoire** + audit.
- **Aperçu du contenu signalé** en contexte (aujourd'hui l'admin ne voit qu'un UUID opaque).
- **Journal d'audit** append-only (`admin_actions` : acteur, action, type+id de cible, raison, horodatage). Fondation de tout le reste.
- Hygiène : garde-fou de route sur les écrans admin, recherche d'utilisateur, pagination des reports, retour au signaleur (optionnel).

## Notes d'implémentation

- Toute nouvelle fonction admin : `SECURITY DEFINER` + `SET search_path = public`, check `auth.uid()` puis check `is_admin`, `REVOKE EXECUTE FROM anon`, et **écriture dans `admin_actions`** avant/après la mutation.
- Le lookup d'identité ne doit **jamais** être une lecture large : une fonction par besoin précis (résoudre une cible de report, résoudre le propriétaire d'une PP), qui journalise l'accès.
- Les DM ne passent jamais par une fonction admin. Le contenu de preuve d'un report DM est capturé côté client au moment du signalement.
