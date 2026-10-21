# Reconstruction de la base dans un nouveau projet Supabase — plan v3

> Décision Scott 2026-10-21 : construire une nouvelle base propre à côté de l'actuelle, **sans toucher à l'actuelle**, puis basculer après tests. Origine : audit complet d'octobre (TX-2 PostGIS exposé et non corrigeable sur place, TX-4 privilèges par défaut). v2 intégrait un premier pré-audit indépendant.
>
> **v3 — simplification décidée par Scott le 2026-10-21 : on reconstruit les RÈGLES, pas les données.** Aucun compte ni donnée utilisateur n'est copié (ni démo, ni comptes réels, ni fichiers) : on reconstruira ce qu'il faut ensuite. Seules les **données de référence** nécessaires au fonctionnement sont chargées (`sports`, `gear_catalog`, `app_config`). Les e-mails, les notifications push, les Edge Functions et tout ce qui est relié à l'ancien projet passent en **étape 2**, après validation du schéma. Les sections du plan v2 qui portaient sur la copie de données (§4) sont remplacées ci-dessous ; le reste est conservé et ordonné en deux étapes.

## Les deux étapes

**Étape 1 — les règles (cette passe)** : nouveau projet, réglages de départ (§2), schéma de départ et transformations (§3), données de référence uniquement (§4 v3), comparaison automatique et contre-audit (§6.1, §6.2), tests automatiques sans compte et avec un compte de test créé pour l'occasion (§6.3). L'ancien projet n'est pas touché ; l'app et le site ne sont pas basculés.

**Étape 2 — le branchement (après validation de l'étape 1)** : Edge Functions et secrets, configuration d'authentification et serveur d'envoi d'e-mails, buckets de stockage vides, régénération de la démo, recréation des comptes (Scott, testeurs) et de la page pro, fichiers d'environnement par canal, test de Scott sur preview, bascule (§5, §6.4, §7, §8).

## 0. Principes

1. **L'ancien projet reste intact et en service** jusqu'à la validation complète du nouveau. Seule exception, consciente, après la bascule : couper ses notifications push (§7).
2. **Même comportement, mêmes règles, mêmes identifiants.** Seuls changent : l'emplacement de PostGIS, les droits par défaut, l'adresse du projet. Tout autre nettoyage est **reporté** après la bascule.
3. **La source de vérité est la base vivante**, pas la relecture des 471 migrations.
4. **Rien n'est considéré comme bon sans comparaison automatique** ancien / nouveau, objet par objet (§6).
5. **Retour arrière possible à chaque étape.**
6. **Gel des changements de schéma** sur l'ancien projet pendant la reconstruction ; tout correctif urgent est appliqué aux deux projets, et la comparaison est relancée juste avant la bascule.

## 1. Ce que Scott fait (tableau de bord Supabase)

- Créer le nouveau projet : même organisation, région UE, même offre ; me donner sa référence.
- **Serveur d'envoi d'e-mails** : un projet neuf avec l'envoi par défaut de Supabase n'envoie qu'aux membres de l'organisation. Sans serveur d'envoi personnalisé (SMTP), les testeurs ne recevraient ni confirmation ni réinitialisation. Vérifier si l'ancien projet en a un ; sinon, en choisir un (offres gratuites suffisantes) **avant** toute étape qui touche les testeurs.
- Me donner un jeton d'accès à l'API d'administration Supabase (lecture de la configuration d'authentification et de l'API des deux projets, pour un diff automatique au lieu d'une liste à cocher).
- Au moment de la bascule : variables Vercel du site **puis redéploiement** (elles sont figées au build).
- Mettre à jour les identifiants « accès à l'app » des testeurs de la Play Console si besoin.

## 2. Nouveau projet : réglages de départ

- **Clés d'API** : un projet neuf peut n'émettre que les nouvelles clés (publishable / secret) et des JWT signés asymétriquement. Décision explicite, puis test des 4 Edge Functions et du client avec ces clés (supabase-js 2.103 gère les deux).
- **Désactiver `pg_graphql`** (absent de l'ancien projet, activé par défaut sur un neuf : ouvrirait `/graphql/v1`).
- **API de données** : schémas exposés identiques (jamais `extensions` ni `private`), chemin de recherche, plafond de lignes.
- **Temps réel** : réglage « canaux privés » identique.
- **Règle** : on n'installe plus jamais rien dans `public` (les droits par défaut de `supabase_admin` dans `public` restent ouverts et ne sont pas modifiables par nous).

## 3. Schéma de départ

**Ordre impératif :**
1. Activer les extensions dans leurs schémas : `pg_cron`, `pg_net`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `supabase_vault` comme aujourd'hui ; **PostGIS dans `extensions`** (T1).
2. **Fermer les privilèges par défaut** (T4) *avant* de restaurer quoi que ce soit.
3. Restaurer le schéma exporté (`public`, `private`) après les réécritures T2 / T3.
4. **Réappliquer les droits exacts de l'ancien projet par script**, objet par objet — fonctions, tables, colonnes (37 colonnes ont des droits propres), schémas — **y compris `PUBLIC` et y compris les absences**, sans se fier aux GRANT du dump. Raison : le dump écrit les droits par rapport au défaut intégré de Postgres ; avec des défauts fermés, 22 fonctions perdraient leur exécution par `PUBLIC`, dont `private.user_is_suspended`, `demo_content_visible`, `private.is_conversation_member`, `private.message_author_visible`, appelées par les règles d'accès : toute lecture échouerait.
5. Recréer ce qui n'est pas dans le dump : trigger `on_auth_user_created` sur `auth.users` ; buckets et 12 policies de stockage ; policies de `realtime.messages` ; publication `supabase_realtime` (**6 tables** : `activities`, `activity_gear`, `activity_gear_missing`, `notifications`, `participations`, `seat_requests` — les partitions de `realtime.messages` sont gérées par Supabase et ne se recréent pas) ; `REPLICA IDENTITY FULL` sur `activities`, `notifications`, `activity_gear`, `wall_messages`, `private_messages` ; réglages de rôles (`anon` 3 s, `authenticated` 8 s, `authenticator` safeupdate / 8 s / verrou 8 s, chemin de recherche de `postgres`) ; 4 tâches planifiées identiques (utilisateur, actif).

**Transformations, et seulement celles-ci :**

| # | Transformation | Détail |
|---|---|---|
| T1 | PostGIS dans `extensions` | Plus aucune écriture possible sur `spatial_ref_sys` via l'API (TX-2) |
| T2 | Références PostGIS requalifiées | Le dump écrit `public.geography(...)` (9 colonnes : `activities` ×4, `activity_alerts`, `pro_profiles`, `pro_offerings`, `discovery_availabilities`, `channels`) et `public.st_*` dans les vues → réécriture `public.(st_*|geography|geometry|postgis_*)` vers `extensions.` ; **contrôle : zéro `public.st_`, `public.geograph`, `public.geometr` dans le schéma final**. 4 fonctions ont encore `search_path = public` seul et passent à `public, extensions` : `get_activity_detail`, `get_activity_by_invite_token`, `register_as_pro`, `update_pro_profile` (liste tirée d'une requête, pas d'un comptage à la main). |
| T3 | Adresse du projet lue dans `app_config` | 7 fonctions : URL de `send-push` dans `push_notification_to_device`, `broadcast_and_push_message`, `notify_participant_joined`, `invite_users_to_activity` ; hôte de stockage dans `private.pro_photo_url_ok` (qui reçoit `SET search_path = public`), `create_channel`, `set_channel_photo`. Corrige B16. |
| T4 | Privilèges par défaut fermés | Nouveaux objets sans INSERT / UPDATE / DELETE / TRUNCATE pour `anon` / `authenticated`, fonctions sans EXECUTE pour `authenticated`. **Ne corrige que les objets futurs** : les droits actuels sont recopiés tels quels (étape 4). |
| T6 (option) | Retirer TRUNCATE / TRIGGER / REFERENCES à `anon` et `authenticated` | Inutilisables via l'API : aucun effet sur l'app, surface réduite. Décision Scott. |

(T5 du plan v1 est déjà en production depuis 00476 : il n'est plus un écart attendu.)

**Historique** : les 471 migrations sont archivées dans `supabase/migrations_archive/` ; le nouveau projet démarre avec une migration de base unique. `supabase link` vers le nouveau projet avec un garde-fou qui affiche le projet visé avant tout `db push`.

## 4. Données (v3) : référentiels seulement

- **Chargés** : `sports` (48 lignes), `gear_catalog` (63), `app_config` (`demo_mode` = false ; `push_webhook_secret` et adresses de T3 renseignés à l'étape 2). Copiés à l'identique depuis l'ancien projet, identifiants compris (les migrations démo et le client référencent les `sports.key`).
- **Non chargés** : comptes (`auth.users` et `public.users`), sorties, participations, messages, conversations, réservations, pro, avis, dispos, canaux, fichiers, démo, jetons push. La base démarre vide de toute donnée utilisateur.
- **Conséquences assumées** : liens `/u/{id}` et `/pro/{id}` existants invalides ; comptes réels à recréer (Scott + 2 testeurs) ; page pro et offre de Scott à recréer ; démo régénérée à l'étape 2 par les scripts existants (identifiants démo fixes) ; buckets de stockage créés vides.
- Les risques de la copie de données du pré-audit n°1 (clés étrangères, triggers actifs au chargement, comptes en double, URL de fichiers à réécrire) **disparaissent**. Le trigger `on_auth_user_created` reste indispensable : c'est lui qui crée la ligne `public.users` à chaque inscription.

## 5. Hors base

- **Edge Functions** : réglage « vérification du JWT » de chacune lu sur l'ancien projet et reproduit (`send-push` sans vérification JWT, protégée par son secret) ; `npm run push:templates` avant le déploiement de `send-push` ; secrets `PUSH_WEBHOOK_SECRET` (nouveau, identique dans `app_config`) et `ORS_API_KEY`.
- **Authentification** : diff automatique de la configuration (ancien / nouveau) via l'API d'administration : confirmation d'e-mail, mot de passe, durée des sessions (3600 s), MFA, hooks, limites de débit, adresses de retour (`junto://…`, `https://getjunto.app/auth/…`), modèles d'e-mail **qui doivent garder `{{ .TokenHash }}`** (lu par `web/app/auth/callback` et `web/app/auth/reset-password`), serveur d'envoi.
- **App** : un fichier d'environnement par canal (preview / production) au lieu du `.env` unique, et un garde-fou qui affiche l'hôte Supabase embarqué avant chaque publication OTA. **Règle : aucune mise à jour de production publiée depuis un environnement pointé vers le nouveau projet avant la bascule.** Types TypeScript régénérés après T1.
- **Site** : redéploiement Vercel après changement des variables (figées au build) ; retour arrière par « instant rollback ».

## 6. Vérification avant toute bascule

1. **Comparaison automatique ancien / nouveau.** Le rapport doit être vide hormis T1, T2, T3, T4 (et T6 si retenu), listés un par un. Périmètre :
   - fonctions : corps normalisé, propriétaire, `SECURITY DEFINER`, volatilité, STRICT, LEAKPROOF, tous les réglages (`proconfig`), droits EXECUTE comparés en ensembles (bénéficiaire, droit) avec `PUBLIC` ;
   - tables : colonnes, types, défauts, contraintes, actions et report des clés étrangères, index, triggers (clause WHEN, état), RLS activée et forcée, propriétaire, identité de réplication ;
   - policies : texte, rôles, permissive / restrictive ;
   - droits de table, de colonne, de schéma (USAGE sur `private`, `extensions`), privilèges par défaut ;
   - vues : définition, options (`public_participants` en `security_invoker`), droits ;
   - réglages de rôles et de base ; extensions, schémas et versions ; triggers d'événement ; trigger sur `auth.users` ;
   - stockage, publication temps réel, policies de `realtime.messages` ;
   - tâches planifiées (commande, utilisateur, actif) ; Edge Functions (code, vérification JWT) ; configuration d'authentification et de l'API ;
   - données : comptages par table, intégrité de chaque clé étrangère, zéro ancienne adresse.
2. **Contre-audit indépendant** du nouveau projet.
3. **Tests automatiques** : sans compte (lectures prévues autorisées, tout le reste refusé, écriture sur `spatial_ref_sys` impossible car hors API) ; avec un compte de test (créer une sortie, rejoindre, écrire, réserver, présence, notifications, canal privé temps réel).
4. **Test de Scott** sur la build preview pointée vers le nouveau projet. Les liens d'e-mail ouvrent l'app de production (schéma `junto://`), pas la preview (`juntodev`) : confirmation et réinitialisation se testent par une build de variante production pointée vers le nouveau projet, ou en saisissant le jeton à la main — la voie utilisée est notée.

## 7. Bascule

1. Copie définitive des données (§4) avec gel court des écritures ; **les écritures faites sur l'ancien projet après ce moment sont perdues** (fenêtre acceptée, quelques minutes, testeurs prévenus).
2. Preview, puis production : mise à jour de l'app des testeurs (avec le REVOKE de `real_name`, L16) et redéploiement du site.
3. **Nouvelle build native de production rapidement après** : en cas d'échec de mise à jour OTA, l'app retombe sur le bundle embarqué, qui pointerait encore vers l'ancien projet.
4. **Couper les notifications push de l'ancien projet** (retirer son secret `PUSH_WEBHOOK_SECRET`, ou suspendre ses tâches planifiées) : sinon les testeurs recevraient des notifications en double ou fantômes. Exception consciente au principe « intact ».
5. L'ancien projet reste en service quelques semaines ; décision ensuite (Scott).

## 8. Retour arrière

Remettre l'adresse et la clé de l'ancien projet dans l'app (OTA) et le site (rollback Vercel), réactiver ses notifications. Les sessions de l'ancien projet sont conservées sur les téléphones (clé de stockage propre à chaque projet) : les testeurs se retrouvent connectés comme avant. Aucune donnée de l'ancien projet n'a été modifiée.

## 9. Pendant la fenêtre de reconstruction

TX-2 reste ouvert sur l'ancien projet : **décision Scott** entre le filtre provisoire devant l'API et un risque accepté et documenté jusqu'à la bascule.

## 10. Risques identifiés

| Risque | Parade |
|---|---|
| Une vérification de sécurité perdue en route | Comparaison automatique fonction par fonction + contre-audit |
| Lectures cassées par des droits `PUBLIC` perdus | Défauts fermés d'abord, puis droits exacts réappliqués par script, comparés en ensembles |
| Une fonction qui ne trouve plus PostGIS (erreur seulement à l'exécution) | Réécriture du dump + contrôle « zéro `public.st_` » + test d'exécution de chaque fonction géographique |
| Une adresse de l'ancien projet oubliée | Zéro occurrence dans le schéma, les fonctions et toutes les colonnes texte |
| Notifications envoyées pendant le chargement | Chargement triggers coupés |
| E-mails non reçus par les testeurs | Serveur d'envoi personnalisé configuré avant, diff de la configuration d'authentification |
| Publication OTA de production vers la mauvaise base | Fichiers d'environnement par canal + garde-fou d'hôte |
| Notifications en double après bascule | Push coupé sur l'ancien projet |
| Dérive du schéma pendant la fenêtre | Gel, correctifs appliqués aux deux, comparaison relancée à la bascule |

## Annexe — bug préexistant hors périmètre

La liste d'attente iOS du site appelle une fonction `join_ios_waitlist` qui n'existe pas (déjà au backlog).
