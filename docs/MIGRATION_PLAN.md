# Migration vers un nouveau projet Supabase — plan v6

> Remplace `docs/REBUILD_PLAN.md` (v5), dont l'inventaire est en partie dépassé. Établi le 2026-10-22 après le dernier audit (couverture des tests, chaînes d'autorisation, scénarios d'attaque, inventaire de migration) et les décisions de Scott du même jour.

## 0. Décisions et principes

**Décisions de Scott**
1. **Base vide.** On migre les règles, pas les données : seules les données de référence sont chargées (`sports`, `gear_catalog`, `app_config`). Aucun compte, aucune sortie, aucun message, aucun fichier n'est copié. Les comptes réels (Scott) sont recréés ; la démo (~150 sorties, ~25 comptes) est régénérée **après** la migration.
2. **Le nom de l'app n'attend pas.** La migration garde l'identité « Junto » (domaine getjunto.app, e-mails, `junto://`). Le changement de nom sera une bascule de configuration séparée, plus tard. Les étiquettes internes (`junto.bypass_lock`, codes `junto.*`, noms de tâches) restent telles quelles : personne ne les voit.
3. **Pas de testeurs aujourd'hui** : pas de contrainte sur la production. On travaille et on valide sur **preview** ; la production est mise à jour à la fin, en une fois.

**Principes**
1. **L'ancien projet reste intact et en service** jusqu'à la validation complète du nouveau. Seul contact : l'export en lecture.
2. **La source de vérité est la base vivante**, jamais les 521 fichiers de migration ni l'ancien plan.
3. **Rien n'est « bon » sans preuve automatique** : comparaison ancien / nouveau objet par objet, vérificateur statique, suite de tests (1 752 vérifications).
4. **Chaque phase a une porte de sortie** (critères mesurables). On ne passe à la suivante que si tous sont remplis.
5. **Retour arrière possible à chaque phase** : tant que l'app n'est pas basculée, il suffit d'abandonner le nouveau projet.
6. **Gel du schéma** de l'ancien projet pendant la fenêtre. Tout correctif urgent est un même fichier SQL appliqué aux deux projets.

## 1. Prérequis (actions de Scott)

| # | Action | Pourquoi |
|---|---|---|
| P1 | Installer l'outil d'export PostgreSQL 17 (`pg_dump` / `psql`), par exemple `sudo apt install postgresql-client-17` (dépôt officiel PostgreSQL) | Il n'est pas installé ; l'export du schéma en dépend. Docker reste inutile. |
| P2 | Créer le nouveau projet Supabase : même organisation, **région UE**, même offre, **Postgres 17**. Me donner sa référence | Locale (ICU en-US) et version non modifiables ensuite |
| P3 | Me donner un jeton d'accès à l'API d'administration Supabase | Lire et comparer automatiquement les réglages d'authentification et d'API des deux projets |
| P4 | Récupérer les identifiants du serveur d'envoi d'e-mails (SMTP) configuré sur l'ancien projet | Sans eux, le nouveau projet n'envoie d'e-mails qu'aux membres de l'organisation |
| P5 | Au moment de la bascule : variables d'environnement Vercel du site, puis redéploiement | Elles sont figées à la construction du site |

## 2. Inventaire vérifié de l'ancien projet (2026-10-22)

**Base**
- Postgres 17.6, ICU en-US, fuseau UTC. Extensions : `postgis 3.3.7` **dans `public`** (à déplacer), `pg_net 0.20.0`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements` dans `extensions`, `pg_cron 1.6.4`, `supabase_vault` (inutilisé). `pg_graphql` absent.
- Schémas `public` et `private`. 59 tables et vues, 9 colonnes `geography`, 6 index GiST, 5 vues de carte (`activities_with_coords`, `my_activities`, `my_joined_activities`, `my_pending_activities`, `pro_offerings_with_coords`).
- **6 fonctions qui utilisent PostGIS sans `extensions` dans leur chemin de recherche** : `get_activity_detail`, `get_activity_by_invite_token`, `register_as_pro`, `update_pro_profile`, `handle_activity_update`, `broadcast_map_activity`. Les deux dernières sont des déclencheurs sur `activities` : oubliées, **toute modification de sortie échouerait**.
- **Adresse du projet écrite en dur** dans 7 fonctions : envoi des notifications (`push_notification_to_device`, `broadcast_and_push_message`, `notify_participant_joined`) et contrôle des adresses de photo (`private.pro_photo_url_ok`, `create_channel`, `set_channel_photo`, `private.check_avatar_url`). Aussi dans 3 fichiers de tests.
- **2 déclencheurs sur `auth.users`** : `on_auth_user_created` (création du profil) et `junto_refuse_banned_email_change` (e-mail interdit).
- Déclencheur sur `storage.objects` : `junto_storage_object_quota` (plafond de fichiers).
- **6 tâches planifiées** : `junto-presence-sweep` (chaque minute), `junto-notif-purge`, `junto-booking-participant-purge`, `junto-contact-archive-purge`, `junto-throttle-purge`, `junto-cron-log-purge`.
- Temps réel : publication `supabase_realtime` = **`notifications` et `seat_requests`** seulement ; `REPLICA IDENTITY FULL` sur `notifications` seulement ; 4 policies de lecture sur `realtime.messages`.
- Stockage : 3 espaces publics (`avatars`, `pro-photos`, `channel-photos`), 5 Mo, jpeg / png / webp, 12 policies (dossier personnel).
- `app_config` : `push_webhook_secret` (**saisi à la main, dans aucune migration**), `email_ban_pepper`, `demo_mode`.
- Réglages de rôles : `authenticator` (safeupdate, délais 8 s, **`pgrst.db_pre_request = public.junto_pre_request`**), `anon` 3 s, `authenticated` 8 s, `postgres` chemin de recherche `"$user", public, extensions`.
- Droits par défaut fermés (00502, 00510, 00511) : nouvelles fonctions exécutables par personne, nouvelles tables en lecture seule pour les clients.

**Hors base**
- Fonctions Edge : `send-push` (vérification JWT **désactivée**, protégée par secret), `delete-account`, `snap-trail`, `trace-elevation` (vérification JWT activée). Secrets : `PUSH_WEBHOOK_SECRET`, `ORS_API_KEY`.
- Authentification : e-mail uniquement (pas d'OAuth), session 3 600 s, serveur SMTP personnalisé, modèles d'e-mail avec `{{ .TokenHash }}`, adresses de retour `https://getjunto.app/auth/…` → `junto://` (production) et `juntodev://` (preview).
- App : `EXPO_PUBLIC_SUPABASE_URL` et `EXPO_PUBLIC_SUPABASE_ANON_KEY` dans le `.env` local (publications OTA) et dans les variables EAS `preview` / `production` (constructions). Site : `NEXT_PUBLIC_SUPABASE_*` sur Vercel.

**Pourquoi on ne rejoue pas les 521 migrations** : la n° 00332 lève une erreur sur une base vide (compte inexistant), la n° 00001 installe PostGIS dans `public`, la démo est dispersée dans une centaine de fichiers. On part donc d'un **export de la structure réelle**, transformé, puis d'une migration de base unique.

## 3. Phase A — Préparer (aucun changement)

1. Figer la version de la ligne de commande Supabase (2.121.0). Créer un **dossier de travail séparé** lié au nouveau projet ; le dépôt reste lié à l'ancien. Un garde-fou affiche la référence du projet visé avant toute commande d'écriture.
2. **Vérifications précoces sur le projet neuf** (avant de construire) : versions identiques (Postgres 17.6, PostGIS 3.3.7 disponible), locale, droit de `postgres` de créer des déclencheurs sur `auth.users` et `storage.objects`, des policies sur `storage.objects` et `realtime.messages`, propriétaire de la publication temps réel, état de départ des droits par défaut, `pg_graphql` présent ou non.
3. Exporter la **structure** de l'ancien projet (`public`, `private`) avec `pg_dump --schema-only`, et les **données de référence** (`sports`, `gear_catalog`) avec `pg_dump --data-only`. Vérifier que les corps de fonction n'ont rien perdu (aucune ligne vide de commentaire tronquée).

**Porte A** : export complet ; vérifications précoces conformes, ou écart décidé avec Scott.

## 4. Phase B — Construire la structure sur le nouveau projet

Chaque étape est une migration séparée du dossier de travail, appliquée dans cet ordre :

1. **Extensions** dans leurs schémas : `pg_cron`, `pg_net`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements` ; **PostGIS dans `extensions`**. Désactiver `pg_graphql` s'il est présent.
2. **Droits par défaut fermés** avant toute restauration, écrits comme un état final exact (global : fonctions sans `PUBLIC` ; `public` et `private` : fonctions sans `anon` ni `authenticated`, tables en lecture seule ; `anon` nommé explicitement).
3. **Restauration de la structure** transformée :
   - retirer de l'export `CREATE EXTENSION postgis … public` et toutes les lignes `ALTER DEFAULT PRIVILEGES` ;
   - requalifier les références PostGIS de l'export (`"public"."geography"`, `"public"."st_x"`, `OPERATOR("public"…)`) vers `extensions` ; contrôles : zéro référence PostGIS restante dans `public`, exactement 9 colonnes `"extensions"."geography"`.
4. **Chemin de recherche des 6 fonctions PostGIS** : `ALTER FUNCTION … SET search_path = public, extensions` (corps inchangés).
5. **Adresse du projet** : nouvelle clé `app_config.project_url` ; les 7 fonctions la lisent au lieu de l'adresse en dur, **en échec fermé** (clé absente → photo refusée, notification non envoyée sans casser la transaction). Les 3 fichiers de tests lisent aussi cette clé.
6. **Droits exacts recopiés** de l'ancien projet, objet par objet et en ensembles (fonctions, tables, colonnes, schémas, `PUBLIC` compris). Droits d'exécution PostGIS nécessaires aux vues de carte pour `anon` et `authenticated` (`st_x`, `st_y`, `geometry(geography)`, usage du schéma `extensions`).
7. **Ce que l'export ne contient pas** : les 2 déclencheurs sur `auth.users` ; le déclencheur de quota sur `storage.objects` ; les 3 espaces de stockage et leurs 12 policies ; les 4 policies de `realtime.messages` ; la publication temps réel (2 tables) et `REPLICA IDENTITY FULL` sur `notifications` ; les réglages de rôles (dont `pgrst.db_pre_request`) ; les 6 tâches planifiées, **désactivées** à ce stade.
8. **Données de référence** : `sports` (48), `gear_catalog` (63), `app_config` (`demo_mode` = false, `project_url`, `email_ban_pepper` régénéré ; `push_webhook_secret` en phase D).
9. **Historique** : les 521 migrations sont archivées dans `supabase/migrations_archive/` ; le nouveau projet démarre avec la migration de base.

**Porte B** : chaque étape appliquée sans erreur ; aucune ligne hors données de référence.

## 5. Phase C — Prouver (avant tout branchement)

1. **Vérificateur statique** `plpgsql_check` installé temporairement, passé sur toutes les fonctions (déclencheurs avec leur table) ; contrôle témoin : `handle_activity_update` doit être signalée **avant** l'étape B.4 et propre après. Fonctions SQL validées séparément.
2. **Comparaison automatique ancien / nouveau**, dans les deux sens : fonctions (signature, corps exact, propriétaire, `SECURITY DEFINER`, volatilité, réglages, droits), tables (colonnes, types, défauts, contraintes et leur état de validation, clés étrangères, index, déclencheurs et leur état, RLS activée et forcée, identité de réplication), policies, vues (définition et options), droits de schéma et de colonne, droits par défaut, réglages de rôles et de base, extensions, stockage, temps réel, tâches planifiées, données de référence (empreinte de ligne). **Les seuls écarts admis** sont listés un par un : emplacement de PostGIS, chemin de recherche des 6 fonctions, lecture de `project_url` dans les 7 fonctions, droits par défaut.
3. **Suite de tests complète** sur le nouveau projet : les 1 752 vérifications passent ; **les 12 failles connues liées à PostGIS et aux droits internes doivent basculer en « corrigées »** (`spatial_ref_sys` hors API, fonctions PostGIS non exposées, file de `pg_net`, droits par défaut de `supabase_admin`). Celles qui ne basculent pas sont traitées ou acceptées explicitement.
4. **Contrôles réels via l'API** avec la clé publique du nouveau projet : lectures autorisées, écritures refusées, aucune écriture possible sur PostGIS.
5. **Contre-audit indépendant** du nouveau projet.

**Porte C** : vérificateur propre ; comparaison sans écart non listé ; suite verte ; contre-audit sans point bloquant.

## 6. Phase D — Brancher les services (nouveau projet seulement)

1. **Fonctions Edge** : déployer les 4 fonctions avec les mêmes réglages de vérification JWT ; `npm run push:templates` avant `send-push` ; secrets `ORS_API_KEY` et un **nouveau** `PUSH_WEBHOOK_SECRET`, identique dans `app_config`.
2. **Authentification** : comparer et reproduire la configuration par l'API d'administration (confirmation d'e-mail, mots de passe, durée de session, limites de débit, adresses de retour, modèles d'e-mail à jeton haché, serveur SMTP).
3. **Point faible des liens de connexion** : à fermer ici ou lors du changement de nom (modèles qui n'envoient que des liens à jeton haché).
4. **Activer les 6 tâches planifiées** et vérifier leurs premières exécutions.

**Porte D** : une notification de test arrive ; un e-mail de confirmation et un de réinitialisation arrivent ; les tâches s'exécutent sans erreur.

## 7. Phase E — Basculer l'app sur preview

1. **Variables** : un fichier d'environnement par canal au lieu du `.env` unique ; garde-fou qui affiche l'hôte Supabase avant chaque publication. Variable EAS `preview` vers le nouveau projet ; **production inchangée**.
2. Types TypeScript régénérés depuis le nouveau projet.
3. Publication OTA sur preview. Au premier lancement, vider la file de présence hors ligne et les zones de géolocalisation (anciens identifiants).
4. Scott crée son compte → droit admin donné par SQL → page pro recréée.
5. **Démo régénérée** : un seed consolidé et rejouable (≈150 sorties, ≈25 comptes, photos démo copiées dans le stockage), activé par le mode démo.

**Porte E** : parcours de validation de Scott réussis sur son téléphone (liste au §9).

## 8. Phase F — Production et clôture

1. Variable EAS `production` et site Vercel vers le nouveau projet ; redéploiement du site.
2. Mise à jour OTA de production, puis **nouvelle construction native de production** (une app qui retombe sur son paquet embarqué pointerait encore vers l'ancien projet).
3. **Couper les notifications de l'ancien projet** (retirer son secret, suspendre ses tâches planifiées).
4. L'ancien projet reste disponible quelques semaines, en lecture, puis est mis en pause (décision Scott).
5. Documentation mise à jour (`CLAUDE.md`, `SECURITY.md`, mémoire du projet, adresse de stockage dans les tests).

## 9. Parcours de validation (phase E, téléphone de Scott)

Inscription et confirmation par e-mail · connexion, déconnexion, réinitialisation du mot de passe · carte et filtres (sorties et pros, mode démo) · créer, modifier, annuler une sortie (avec trace) · rejoindre, quitter, demander, accepter · covoiturage (proposer des places, demander, accepter, annuler) · matériel · mur de sortie et messages privés, groupes, discussions ouvertes, partages · notifications et notifications push · présence (QR, géolocalisation) · évaluations après une sortie · Découverte (dispo, cartes, invitation) · page pro, offres, disponibilités, réservations, avis · signaler, bloquer · suppression de compte (compte jetable).

## 10. Retour arrière

- **Phases A à D** : abandonner le nouveau projet ; rien n'a changé pour l'app.
- **Phase E** : republier l'OTA preview pointée vers l'ancien projet.
- **Phase F** : remettre l'adresse et la clé de l'ancien projet (OTA + variables EAS + rollback Vercel) et réactiver ses notifications. Ce qui a été créé dans le nouveau projet entre-temps est perdu.

## 11. Risques et parades

| Risque | Parade |
|---|---|
| Une fonction ne trouve plus PostGIS (erreur seulement à l'exécution) | Les 6 fonctions corrigées ; vérificateur statique avec témoin ; chaque fonction géographique et chaque vue exécutée en test |
| Les vues de la carte reviennent vides en silence | Droits PostGIS des vues vérifiés pour `anon` et `authenticated` ; vues testées via l'API |
| Une adresse de l'ancien projet oubliée | `project_url` lue partout, échec fermé ; zéro `.supabase.co` dans les corps de fonction et les tests |
| Les photos et avatars refusés après bascule | `check_avatar_url` inclus dans la lecture de `project_url` ; test d'envoi d'avatar en phase E |
| Une règle de sécurité perdue en route | Comparaison automatique stricte + suite de 1 752 tests + contre-audit |
| Notifications silencieuses | Secret identique fonction Edge / `app_config` ; test en porte D |
| E-mails non reçus | SMTP reproduit ; test en porte D |
| Publication vers la mauvaise base | Un fichier d'environnement par canal + garde-fou d'hôte |
| Notifications en double après bascule | Notifications coupées sur l'ancien projet (F.3) |
| Dérive de schéma pendant la fenêtre | Gel ; correctifs appliqués aux deux ; comparaison relancée avant F |
| File `pg_net` et droits de `supabase_admin` pas fermés d'office | Vérifiés en phase C sur le nouveau projet, pas supposés |

## 12. Ordre de grandeur

Phases A à C : une à deux sessions de travail (l'essentiel est automatisé, la preuve est longue à faire tourner). Phase D : une session, avec Scott pour les e-mails. Phase E : une session plus les essais de Scott. Phase F : courte. Aucune phase n'est commencée sans la porte précédente.
