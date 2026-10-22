# Migration vers un nouveau projet Supabase — plan v7

> **Répétition générale d'abord** sur un projet jetable, avec le kit `scripts/migration/` (mode d'emploi : `scripts/migration/REPETITION.md`). Les mots de passe restent chez Scott : il lance `export.sh` et `build.sh` ; préparation, preuves et tests se font sans mot de passe.

> v7 du 2026-10-22, après la répétition à blanc du plan v6 contre la base réelle. Elle a trouvé des étapes qui auraient échoué ou cassé sans bruit ; elles sont corrigées ici (§13 liste les changements). Remplace `docs/REBUILD_PLAN.md` (v5).

## 0. Décisions et principes

**Décisions de Scott**
1. **Base vide.** On migre les règles, pas les données : seules les données de référence sont chargées (`sports`, `gear_catalog`, `app_config`). Aucun compte, aucune sortie, aucun message, aucun fichier n'est copié. Les comptes réels (Scott) sont recréés ; la démo (~150 sorties, ~25 comptes) est régénérée **après** la migration.
2. **Le nom de l'app n'attend pas.** La migration garde l'identité « Junto » (domaine getjunto.app, e-mails, `junto://`). Le changement de nom sera une bascule de configuration séparée, plus tard. Les étiquettes internes (`junto.bypass_lock`, codes `junto.*`, noms de tâches) restent telles quelles.
3. **Pas de testeurs aujourd'hui** : on valide sur **preview** ; la production est mise à jour à la fin, en une fois.
4. **Le filtre d'API `junto_pre_request` n'est pas recréé** (2026-10-22) : il ne servait qu'à protéger les tables PostGIS de `public`, qui n'y seront plus.

**Principes**
1. **L'ancien projet reste intact et en service** jusqu'à la validation complète du nouveau. Seuls contacts : l'export en lecture, et deux écritures décidées (E.0 et F.3).
2. **La source de vérité est la base vivante**, jamais les fichiers de migration ni l'ancien plan.
3. **Rien n'est « bon » sans preuve automatique** : comparaison ancien / nouveau objet par objet (`scripts/catalog-diff.mjs`), vérificateur statique, suite de tests (2 060 vérifications).
4. **Chaque phase a une porte de sortie** (critères mesurables). On ne passe à la suivante que si tous sont remplis.
5. **Retour arrière possible à chaque phase** : tant que l'app n'est pas basculée, il suffit d'abandonner le nouveau projet.
6. **Gel du schéma** de l'ancien projet pendant la fenêtre. Tout correctif urgent est un même fichier SQL appliqué aux deux projets.
7. **Ce qui peut être fait sur l'ancien projet avant la fenêtre l'est** (00524) : moins d'étapes le jour J, et chacune déjà prouvée par la suite de tests.

## État — répétition du 2026-10-22 sur le vrai nouveau projet (`fajfigpwfdwmchhzecwe`, Irlande)

- **Phase A** : export fait par Scott (pg_dump 18.6 sur Postgres 17.6) ; vérifications précoces conformes.
- **Phase B** : construction passée **du premier coup**, 9 étapes « ok », journaux sans avertissement.
- **Phase C** : comparaison objet par objet = **0 écart inattendu** (17 écarts admis, tous décidés : PostGIS déplacé, filtre d'API retiré, tâches désactivées, réglage interne de la plateforme, une contrainte imprimée sans parenthèses par Postgres 17.11) ; suite complète **2 063 pass, 0 fail, 5 trous connus** (12 sur l'ancien) ; API réelle conforme (PostGIS et schéma `extensions` hors d'atteinte, écritures anonymes refusées) ; vérificateur statique : 245 fonctions, 0 erreur.
- Trouvé en route : partitions du temps réel absentes tant que le service n'a pas démarré (→ D.5) ; un test qui ne passait que grâce aux données réelles (réécrit).
- **Phase D faite** (2026-10-22) : 4 fonctions Edge déployées (mêmes réglages), nouveau secret des notifications aux deux endroits, clé ORS saisie par Scott, configuration d'authentification et d'API copiée (145 + 4 réglages, vérifiés identiques ; mot de passe SMTP ressaisi par Scott — la valeur lue par l'API était masquée), 6 tâches actives.
- **Phase E en cours** : canal preview séparé chez Expo (production inchangée), app preview sur le nouveau projet, compte de Scott créé (admin), démo recopiée à l'identique (`scripts/migration/copy-demo.py`, 24 comptes bloqués à vie), tests manuels de Scott en cours. Publications preview : **toujours** `bash scripts/ota-preview.sh "message"` (sans cache Metro, adresse vérifiée).
- **F.6 fait par anticipation** (2026-10-22) : migrations archivées, `00526_baseline.sql` seule migration, dépôt lié au nouveau projet (`~/junto-migration/link-old` pour lire l'ancien).
- **Chaîne push prouvée côté serveur** (2026-10-22) : notification de test → déclencheur → `send-push` (secret accepté) → Expo (réponse `DeviceNotRegistered` pour le faux jeton, que `send-push` a ensuite supprimé lui-même) ; traces nettoyées. La preview ne peut pas recevoir de push : elle est construite sans fichier Firebase (préexistant, sans lien avec la migration). **Puis prouvé jusqu'au téléphone** : l'app preview a reçu Firebase (app `app.getjunto.preview` ajoutée au projet junto-5e1e3, clé FCM V1 dans les identifiants EAS preview, construction native du 2026-10-22) ; jeton enregistré sur le nouveau projet, notification reçue par Scott. Première sauvegarde du nouveau projet faite par Scott.
- **Reste** : phase F (production, site, arrêt des notifications de l'ancien projet, test push réel sur le téléphone).

## 0 bis. Ce qui se fige — à ne pas rater une seconde fois

L'ancienne base est irréparable pour deux raisons : **PostGIS installé dans `public`** (ses objets appartiennent au rôle interne de la plateforme : impossible de les protéger ni de les déplacer) et des droits par défaut de ce même rôle. Tout ce qui suit se décide **une fois**, à la création ou au premier chargement :

| Choix figé | Décision | Garde |
|---|---|---|
| Région | **Irlande (eu-west-1)** — choix de Scott le 2026-10-22 (UE, RGPD ; l'ancien est à Francfort, écart de latence imperceptible). Projet `fajfigpwfdwmchhzecwe`, Postgres 17.11 | Création du projet (P3) |
| Version, locale, fuseau | Postgres 17, ICU en-US, UTC — identiques à l'ancien | Vérifications précoces (A.2) |
| Emplacement des extensions | Toutes dans `extensions` (`pg_cron` dans son schéma propre), **jamais** activées depuis le tableau de bord | Étape 10 du kit ; test « aucune extension dans public » |
| Propriétaire de nos objets | `postgres` seulement — tout changement de structure passe par une migration, jamais par l'éditeur de tables | Test « aucun objet de public/private à un autre rôle » (00_socle) |
| Noms des espaces de stockage | `avatars`, `pro-photos`, `channel-photos` inchangés (ils sont dans les adresses des photos) | Étape 50 ; comparaison |
| Clés d'API dans l'app | **Les nouvelles clés (publiable / secrète) dès le départ** si la répétition montre que les 4 fonctions Edge marchent avec (elles lisent aujourd'hui `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`). Les anciennes clés JWT sont appelées à disparaître : changer de clé plus tard, c'est une OTA **et** une construction native, avec des utilisateurs réels | Répétition (A.2 / D.1) ; décision de Scott |
| Règles d'écriture des fonctions | `SET search_path = public, extensions` pour toute nouvelle fonction (CLAUDE.md, 2026-10-22) — sinon une fonction géographique échoue à l'exécution | CLAUDE.md ; vérificateur statique |
| Historique des migrations | **Une seule migration de base, déjà marquée appliquée** ; les anciennes archivées. Sinon le premier `db push` rejouerait les 520 anciennes, à commencer par celle qui met PostGIS dans `public` | Étape 80 du kit ; F.6 |

## 0 ter. Le contrôle reste à nous

| Sujet | Ce qui garantit qu'on ne dépend de personne |
|---|---|
| Structure de la base | Le dépôt la porte entière (`00526_baseline.sql` + migrations suivantes) : on peut la reconstruire sur n'importe quel Postgres 17 + PostGIS, chez Supabase ou ailleurs |
| Données | **Nos propres sauvegardes** : `bash scripts/db-backup.sh <référence>` (Scott ; complète, restaurable table par table), chaque semaine et avant toute opération risquée, en plus de celles de Supabase ; une restauration d'essai de temps en temps |
| Règles de sécurité | Uniquement les nôtres (RLS, fonctions, déclencheurs, droits), testées par notre suite — jamais un réglage par défaut de la plateforme |
| Limites de temps des requêtes | Posées par nous (étape 55), pas laissées aux valeurs par défaut |
| Secrets | Tenus par Scott dans son gestionnaire de mots de passe : mot de passe de la base, clé des empreintes d'e-mails bannis (perdue = interdictions invérifiables), secret des notifications, clé ORS, identifiants SMTP, clé secrète d'API |
| Compte Supabase | Scott seul propriétaire de l'organisation, double authentification activée |
| Ce que la plateforme garde (inévitable) | Les objets PostGIS (dans `extensions`, non exposé), les droits par défaut de son rôle interne, la file de `pg_net`, ses propres réglages de rôles. **Aucun n'est atteignable par l'API** (prouvé en C.4) et notre sécurité ne s'appuie sur aucun d'eux |

## 1. Prérequis (actions de Scott)

| # | Action | Pourquoi |
|---|---|---|
| P1 | Installer `pg_dump` / `psql` : `sudo apt install postgresql-client` (version 18 sur Ubuntu 26.04 ; elle lit une base 17, l'export est fait sans statistiques ; la reconstruction sur une base 17 est vérifiée par la répétition) | L'export et la restauration en dépendent. `supabase db dump` n'est pas utilisable (il demande Docker). |
| P2 | Mot de passe de la base de l'ancien projet + son adresse de connexion **« session pooler »** (port 5432, IPv4) | `pg_dump` se connecte directement à la base ; la connexion directe est en IPv6 seulement |
| P3 | Créer le nouveau projet : même organisation, **région UE**, même offre, **Postgres 17**. Me donner sa référence, son mot de passe de base et son adresse « session pooler » | Locale et version non modifiables ensuite |
| P4 | Un jeton d'accès à l'API d'administration Supabase | Lire et comparer la configuration d'authentification, d'API, de temps réel et de stockage des deux projets |
| P5 | Les identifiants du serveur d'envoi d'e-mails (SMTP) de l'ancien projet | Sans eux, le nouveau projet n'envoie d'e-mails qu'aux membres de l'organisation |
| P6 | Au moment de la bascule : variables d'environnement Vercel du site, puis redéploiement | Elles sont figées à la construction du site |

## 2. Inventaire vérifié de l'ancien projet (2026-10-22)

**Base**
- Postgres 17.6, ICU en-US, fuseau UTC. Extensions : `postgis 3.3.7` **dans `public`** (à déplacer), `pg_net 0.20.0`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements` dans `extensions`, `pg_cron 1.6.4`, `supabase_vault` (inutilisé). `pg_graphql` absent.
- Schémas `public` et `private` : 278 fonctions (277 sans `junto_pre_request`), 59 relations, 9 colonnes `geography`, 6 index GiST, 5 vues de carte. Le corps des fonctions n'appelle jamais `public.st_*` ; les références PostGIS de l'export sont **sans guillemets** (`public.geography(Point,4326)`, `public.st_x`, `::public.geometry`) dans les 9 colonnes et les 5 vues.
- **35 relations n'ont pas de droit de lecture sur la table entière** pour les clients ; `activities` (28 colonnes), `bookings` (15) et `pro_profiles` (19) reposent sur des **droits par colonne** (ex. `activities.invite_token` n'est lisible par personne). Un droit de table accordé par erreur annulerait cette protection.
- **Fait sur l'ancien projet par 00524** : les 6 fonctions PostGIS (`get_activity_detail`, `get_activity_by_invite_token`, `register_as_pro`, `update_pro_profile`, `handle_activity_update`, `broadcast_map_activity`) ont `extensions` dans leur chemin de recherche ; l'adresse du projet est lue dans `app_config.project_url` par les 7 fonctions qui l'écrivaient en dur, en échec fermé ; `private.pro_photo_url_ok` a un chemin de recherche fixé. Les tests lisent aussi l'adresse depuis la base. Ces corrections arrivent donc **avec l'export**.
- **2 déclencheurs sur `auth.users`** : `on_auth_user_created` et `junto_refuse_banned_email_change`. Déclencheur sur `storage.objects` : `junto_storage_object_quota`.
- **6 tâches planifiées** : `junto-presence-sweep` (chaque minute), `junto-notif-purge`, `junto-booking-participant-purge`, `junto-contact-archive-purge`, `junto-throttle-purge`, `junto-cron-log-purge`.
- Temps réel : publication `supabase_realtime` (propriétaire `postgres`) = `notifications` et `seat_requests` ; `REPLICA IDENTITY FULL` sur `notifications` ; 4 policies sur `realtime.messages`.
- Stockage : 3 espaces publics (`avatars`, `pro-photos`, `channel-photos`), 5 Mo, jpeg / png / webp, 12 policies.
- `app_config` : `project_url`, `push_webhook_secret` (**saisi à la main**), `email_ban_pepper`, `demo_mode`. Les clients ont un droit de lecture sur la table mais la RLS ne leur montre rien (testé).
- Réglages de rôles : `authenticator` (délais, `pgrst.db_pre_request`), `anon` 3 s, `authenticated` 8 s.
- Droits par défaut de `postgres` fermés (00502, 00510, 00511). Ceux de `supabase_admin` (ouverts) et l'accès à `net.http_request_queue` appartiennent à la plateforme : un projet neuf les reproduit à l'identique (TX-4, PV-4 restent des trous connus, non corrigibles par nous).

**Hors base**
- Fonctions Edge : `send-push` (vérification JWT **désactivée**, protégée par secret ; **aucun `config.toml`** dans le dépôt, le réglage n'existe qu'à la commande de déploiement), `delete-account`, `snap-trail`, `trace-elevation` (vérification JWT activée). Secrets : `PUSH_WEBHOOK_SECRET`, `ORS_API_KEY`.
- Authentification : e-mail uniquement, session 3 600 s, SMTP personnalisé, modèles avec `{{ .TokenHash }}`, adresses de retour `https://getjunto.app/auth/…`. La page `web/app/auth/callback` ouvre **toujours** `junto://` (l'app de production), jamais `juntodev://`.
- App : `EXPO_PUBLIC_SUPABASE_URL` et `EXPO_PUBLIC_SUPABASE_ANON_KEY` dans le `.env` local (OTA) et les variables EAS `preview` / `production`. Session stockée sous `sb-<ref>-auth-token` : changer de projet déconnecte proprement. Site : `NEXT_PUBLIC_SUPABASE_*` sur Vercel.

**Pourquoi on ne rejoue pas les migrations** : la n° 00332 lève une erreur sur une base vide, la n° 00001 installe PostGIS dans `public`, la démo est dispersée dans une centaine de fichiers. On part d'un **export de la structure réelle**, transformé.

## 3. Phase A — Préparer (aucun changement)

1. Figer la ligne de commande Supabase (2.121.0). **Dossier de travail séparé** lié au nouveau projet ; le dépôt reste lié à l'ancien. Le lanceur de tests affiche le projet visé et refuse de tourner si `JUNTO_DB_REF` en désigne un autre.
2. **Vérifications précoces sur le projet neuf** : versions (Postgres 17.6, PostGIS 3.3.7 disponible), locale ; droits de `postgres` sur `auth.users` (TRIGGER, REFERENCES, INSERT, DELETE — la clé étrangère `users.id`, les 2 déclencheurs, les tests et le seed en dépendent), sur `storage.objects` (TRIGGER, policies) et `realtime.messages` (policies) ; propriétaire de la publication temps réel ; droits par défaut de départ ; `pg_graphql` ; **modèle de clés d'API** (clés « anon / service_role » classiques disponibles ou seulement les nouvelles clés publiables / secrètes) — décision avec Scott avant D.
3. **Export à blanc dès que P1-P2 sont là** (lecture seule) :
   - structure : `pg_dump "$OLD" --schema-only -n public -n private --no-owner -f schema.sql`
   - référence : `pg_dump "$OLD" --data-only -t public.sports -t public.gear_catalog --column-inserts -f ref.sql`
   - contrôles sur le vrai fichier : lignes `\restrict` / `\unrestrict` ; présence ou non de lignes de publication ; lignes `ALTER DEFAULT PRIVILEGES` (celles de `supabase_admin` échoueraient) ; instructions GRANT / REVOKE ; formes et nombre exacts des références PostGIS ; 270 fonctions ; aucune ligne `CREATE EXTENSION` (normal avec `-n`).
4. **Base de comparaison** : `node scripts/catalog-diff.mjs snapshot > old.json` sur l'ancien projet. Le script est déjà prouvé : ancien contre ancien = 0 écart sur 3 954 objets ; `node scripts/catalog-diff.mjs selftest` détecte un droit ajouté, un chemin de recherche modifié et une policy supprimée (injectés dans une transaction annulée).
5. **Référence du vérificateur statique** : `plpgsql_check` passé sur l'ancien projet dans une transaction annulée, pour séparer les avertissements préexistants des régressions. C'est la seule commande de structure (`CREATE EXTENSION`, annulé) lancée sur l'ancien projet : **accord de Scott avant**.

**Porte A** : export lisible et conforme aux contrôles ; vérifications précoces conformes, ou écart décidé avec Scott ; `old.json` et la référence du vérificateur enregistrés.

## 4. Phase B — Construire la structure sur le nouveau projet

Chaque étape est appliquée avec `psql -v ON_ERROR_STOP=1 --single-transaction -f …`, **dans sa propre session** (l'export règle `search_path` et `check_function_bodies` pour la session).

1. **Extensions** dans leurs schémas : `pg_cron`, `pg_net`, `pgcrypto`, `uuid-ossp`, `pg_stat_statements` ; **PostGIS dans `extensions`**. Désactiver `pg_graphql` s'il est présent.
2. **Droits par défaut d'origine de Postgres pendant la restauration** (ni ouverts, ni vides) : pour `postgres`, aucun droit par défaut vers `anon`, `authenticated`, `service_role` (global et `public`), et l'exécution des fonctions rendue à `PUBLIC` comme à l'origine. Raison : l'export écrit chaque droit **par rapport aux droits d'origine de Postgres**. Sous des droits ouverts, une table gagnerait une lecture complète et **contournerait les droits par colonne** (ex. `invite_token`) ; sous des droits vides, un droit `PUBLIC` que l'export laisse implicite (`demo_content_visible` aujourd'hui) disparaîtrait sans bruit (corrigé le 2026-10-22 : la v7 disait « vides »). Après cette étape, un contrôle vérifie qu'aucun droit par défaut ne vise un autre rôle que `postgres`.
3. **Restauration de la structure** transformée :
   - retirer les lignes `\restrict` / `\unrestrict` et toutes les lignes `ALTER DEFAULT PRIVILEGES` ; vérifier l'absence de `CREATE EXTENSION` ;
   - requalifier les références PostGIS vers `extensions`, à partir de la **liste des objets membres de l'extension** (types, fonctions, opérateurs), formes sans **et** avec guillemets ;
   - contrôles après transformation : zéro référence `public.` à un objet PostGIS sous aucune forme (`public\.("?)(st_|geograph|geometr|postgis|box[23]d|spatial_ref_sys)`), 9 colonnes `extensions.geography`, 5 vues de carte qui compilent.
4. **Droits exacts** : ce sont ceux de l'export, rejoués sous les droits d'origine (B.2) — aucun ajout, aucun retrait à la main. PostGIS reste exécutable par `PUBLIC` comme à l'installation ; les vues de carte s'exécutent avec les droits de leur propriétaire. Aucun droit n'est ajouté sur le schéma `extensions`.
5. **Droits par défaut définitifs** = ceux de l'ancien projet pour `postgres` (global : fonctions sans `PUBLIC` ; `public` : tables en lecture pour les clients, tout pour `service_role`, fonctions pour `service_role`, séquences).
6. **Ce que l'export ne contient pas** : les 2 déclencheurs sur `auth.users` ; le déclencheur de quota sur `storage.objects` ; les 3 espaces de stockage et leurs 12 policies ; les 4 policies de `realtime.messages` ; la publication temps réel (2 tables) si elle n'est pas dans l'export, et `REPLICA IDENTITY FULL` sur `notifications` ; **aucun** réglage de rôle (les délais sont les valeurs par défaut de Supabase, déjà présentes sur un projet neuf — la comparaison le vérifie), en particulier pas `pgrst.db_pre_request` (décision 4 : la fonction `junto_pre_request` n'est pas restaurée ; ses tests se changent d'eux-mêmes en « filtre absent et PostGIS hors de public ») ni `session_preload_libraries` (réglage de la plateforme, interdit à `postgres`) ; noms entièrement qualifiés ; les 6 tâches planifiées, créées puis **désactivées dans la même transaction** (`cron.alter_job(…, active := false)`).
7. **Données de référence et de sécurité** : `sports` (48), `gear_catalog` (63), **`banned_email_hashes`** (empreintes des e-mails bannis — ce ne sont pas des données d'utilisateur : sans elles, un compte supprimé pendant sa suspension pourrait se réinscrire) ; `app_config` : `demo_mode` = false, `project_url` = adresse du **nouveau** projet, `email_ban_pepper` **repris de l'ancien projet** (les empreintes en dépendent), `push_webhook_secret` provisoire (remplacé en D).
8. **Historique** : les migrations sont archivées dans `supabase/migrations_archive/` ; le nouveau projet démarre avec la migration de base.

**Porte B** : chaque étape appliquée sans erreur ; aucune ligne hors données de référence ; contrôles de B.3 à zéro.

## 5. Phase C — Prouver (avant tout branchement)

1. **Vérificateur statique** `plpgsql_check` sur toutes les fonctions (déclencheurs avec leur table), comparé à la référence de A.5 : aucun nouvel avertissement. Fonctions SQL validées séparément.
2. **Comparaison automatique** : `snapshot > new.json` sur le nouveau projet, puis `JUNTO_DB_REF=<nouveau> node scripts/catalog-diff.mjs old.json new.json`. Le script refuse deux instantanés du même projet (ligne d'identité = `project_url`) et un nouvel instantané qui n'est pas celui attendu. Le script compare relations, colonnes, contraintes, index, policies (dont `storage.objects` et `realtime.messages`), déclencheurs (dont `auth.users` et `storage.objects`), fonctions (définition complète : arguments et valeurs par défaut, STRICT, LEAKPROOF, PARALLEL, coût, sécurité, volatilité, réglages, corps), propriétaires, réglages de la base, options de la publication, droits de table / colonne / fonction / schéma, droits par défaut, publication, extensions, tâches planifiées, espaces de stockage, réglages de rôles, clés de `app_config`. Le préfixe de schéma des objets PostGIS (`public.` / `extensions.`) est neutralisé des deux côtés. **Seuls écarts admis**, listés un par un dans `scripts/catalog-allowed.json` **avec leur empreinte exacte avant et après** (un nom seul ne suffit pas : il cacherait un autre changement du même objet) : extension `postgis` (public → extensions), fonction `junto_pre_request` et ses 3 droits, réglage du rôle `authenticator`, les 6 tâches (`active=false` jusqu'en D), éventuellement `pg_graphql` et les droits par défaut du schéma `storage` (plateforme). Plus la comparaison des réglages hors base par l'API d'administration (API de données : schémas exposés, `max_rows` ; temps réel ; stockage ; authentification).
3. **Suite de tests complète** sur le nouveau projet, depuis le dépôt : `JUNTO_DB_WORKDIR=~/junto-migration/link JUNTO_DB_REF=<nouveau> npm run test:db` (le lanceur exige les deux et demande à la base quel projet elle est). **TX-2 disparaît** (PostGIS hors de `public` : ses marqueurs ne s'appliquent plus). **Restent** : TX-4 et PV-4 (plateforme) et **PV-1** — `anon` garde l'usage du schéma `extensions` et l'exécution PostGIS par `PUBLIC` (réglages de la plateforme) ; ce qui compte est qu'elles ne soient **pas atteignables par l'API**, prouvé en C.4. Limite connue : sur une base vide, les essais d'écriture directe de la section 6 de `00_socle` ne trouvent aucune ligne — d'où la **2e exécution complète après le seed (E.5), condition de la porte E**.
4. **Contrôles réels via l'API** avec la clé publique du nouveau projet : lectures autorisées, écritures refusées, aucune écriture possible sur PostGIS ; `POST /rest/v1/rpc/st_x` et `/rpc/_postgis_stats` répondent 404 (PV-1 hors d'atteinte) ; schémas exposés par l'API de données sans `extensions`. **Relancés après le seed de démo (E.5)** : sur une base vide, une lecture « 0 ligne » ne prouve rien.
5. **Contre-audit indépendant** du nouveau projet.

**Porte C** : vérificateur sans nouvel avertissement ; comparaison sans écart non listé ; suite verte ; contre-audit sans point bloquant.

## 6. Phase D — Brancher les services (nouveau projet seulement)

1. **Fonctions Edge** : `npm run push:templates`, puis `npx supabase functions deploy send-push --no-verify-jwt --project-ref <nouveau>` (**le drapeau est obligatoire** : sans lui, chaque notification est refusée sans bruit), et les 3 autres avec vérification JWT. Secrets `ORS_API_KEY` et un **nouveau** `PUSH_WEBHOOK_SECRET`, identique dans `app_config`. Les fonctions lisent `SUPABASE_ANON_KEY` (3 usages) et `SUPABASE_SERVICE_ROLE_KEY` (2) : vérifier qu'elles existent sous ce nom avec le modèle de clés choisi en A.2.
2. **Authentification** : reproduire la configuration par l'API d'administration (confirmation d'e-mail, mots de passe, durée de session, limites de débit, adresses de retour, modèles d'e-mail à jeton haché, SMTP, CAPTCHA, confirmation du changement d'e-mail ; aucun « hook » d'authentification aujourd'hui). **API de données et temps réel** : schémas exposés (`public` seulement), chemin de recherche supplémentaire, `max_rows`, réglage d'accès du temps réel **identique à l'ancien projet** — pas « canaux privés seulement » : le badge des notifications et la boîte des demandes de covoiturage écoutent sur des canaux non privés (protégés par la RLS des tables) et se figeraient. **Réglages à poser dès le départ** (gratuits, pénibles à rattraper avec des utilisateurs) : connexion SSL obligatoire à la base ; protection contre les mots de passe divulgués si l'offre le permet ; sauvegardes selon l'offre (restauration à un instant précis à décider avant l'ouverture au public).
3. **Point faible des liens de connexion** : à fermer ici ou lors du changement de nom (modèles qui n'envoient que des liens à jeton haché).
4. **Activer les 6 tâches planifiées** et vérifier leurs premières exécutions réussies.
5. **Démarrer le temps réel** avant toute vérification : une connexion temps réel (même brève) fait créer les partitions par jour de `realtime.messages`. Sans elles, chaque signal envoyé par la base est perdu sans bruit (constaté pendant la répétition : 12 tests en échec, tous verts après une connexion).

**Porte D** : une notification de test arrive ; un e-mail de confirmation et un de réinitialisation arrivent ; `delete-account` (compte jetable), `snap-trail` et `trace-elevation` répondent avec une vraie session ; les 6 tâches sont actives et ont tourné sans erreur ; contrôle de santé : `project_url`, `push_webhook_secret`, `email_ban_pepper`, `demo_mode` présents et bien formés.

## 7. Phase E — Basculer l'app sur preview

0. **Sur l'ancien projet** (écriture décidée) : retirer les jetons push du téléphone de Scott, pour que l'ancien projet n'envoie plus de notifications vers l'app preview.
1. **Variables** : un fichier d'environnement par canal au lieu du `.env` unique ; garde-fou qui affiche l'hôte Supabase avant chaque publication. Variable EAS `preview` vers le nouveau projet ; **production inchangée**.
2. Types TypeScript régénérés depuis le nouveau projet.
3. Publication OTA sur preview. **Scott vide les données de l'app preview** (déconnexion, file de présence hors ligne, zones de géolocalisation : tous liés à l'ancien projet ; une présence en attente vers l'ancien projet serait de toute façon refusée puis abandonnée).
4. Scott crée son compte. Le lien de confirmation ouvrirait l'app de production : **compte confirmé directement en base**, puis droit admin donné par SQL, puis page pro recréée.
5. **Démo régénérée** : un seed consolidé et rejouable (≈150 sorties, ≈25 comptes, photos démo dans le stockage, adresses construites depuis `project_url`, dates relatives), activé par le mode démo. Puis relancer C.4.

**Porte E** : parcours de validation de Scott réussis sur son téléphone (§9).

## 8. Phase F — Production et clôture

1. Variable EAS `production` et site Vercel vers le nouveau projet ; redéploiement du site.
2. Mise à jour OTA de production, puis **nouvelle construction native de production** (une app qui retombe sur son paquet embarqué pointerait encore vers l'ancien projet).
3. **Couper les notifications de l'ancien projet** (retirer son secret, suspendre ses tâches planifiées).
4. L'ancien projet reste disponible quelques semaines, en lecture, puis est mis en pause (décision Scott). Les liens de partage et d'invitation créés avant la bascule ne fonctionnent plus (données non migrées).
5. Documentation mise à jour (`CLAUDE.md`, `SECURITY.md`, mémoire du projet).
6. **Historique du dépôt** : `supabase/migrations/*` → `supabase/migrations_archive/` ; le fichier `00526_baseline.sql` produit par la préparation (secrets masqués) devient la seule migration ; le dépôt est lié au nouveau projet ; `npx supabase migration list` doit montrer `00526` appliquée des deux côtés avant tout nouveau `db push`.

## 9. Parcours de validation (phase E, téléphone de Scott)

Inscription et confirmation · connexion, déconnexion, réinitialisation du mot de passe · carte et filtres (sorties et pros, mode démo) · créer, modifier, annuler une sortie (avec trace) · rejoindre, quitter, demander, accepter · covoiturage (proposer des places, demander, accepter, annuler, quitter la sortie en étant passager) · matériel · mur de sortie et messages privés, groupes, discussions ouvertes, partages, modification d'un message · notifications et notifications push (toucher chaque type) · présence (QR, géolocalisation) · évaluations après une sortie · Découverte (dispo, cartes, invitation) · page pro, offres, disponibilités, réservations, avis · photos (avatar, pro, discussion) · signaler, bloquer, débloquer depuis un profil · suppression de compte (compte jetable).

## 10. Retour arrière

- **Phases A à D** : abandonner le nouveau projet ; rien n'a changé pour l'app.
- **Phase E** : republier l'OTA preview pointée vers l'ancien projet ; Scott se reconnecte (ses jetons push se réenregistrent).
- **Phase F** : remettre l'adresse et la clé de l'ancien projet (OTA + variables EAS + rollback Vercel) et réactiver ses notifications. Ce qui a été créé dans le nouveau projet entre-temps est perdu.

## 11. Risques et parades

| Risque | Parade |
|---|---|
| Une table gagne une lecture complète pendant la restauration (droits par colonne contournés), ou une fonction perd un droit implicite | Droits par défaut **d'origine** pendant la restauration (B.2, contrôlés) ; droits de l'export rejoués tels quels ; comparaison des droits lus dans les ACL, MAINTAIN compris (C.2) |
| La preuve tourne en fait sur l'ancien projet (« 0 écart » trompeur) | Ligne d'identité dans chaque instantané, refus si identiques ; lanceur de tests qui exige la référence et la demande à la base |
| La construction s'applique au mauvais projet | `build.sh <référence>` : adresse et fichiers préparés vérifiés ; étape 05 : refus si `public` n'est pas vide ou si `private` existe |
| Une fonction ne trouve plus PostGIS (erreur seulement à l'exécution) | Chemins corrigés sur l'ancien projet (00524) ; vérificateur statique comparé à sa référence ; chaque fonction géographique et chaque vue exécutée en test |
| La transformation PostGIS rate des références | Requalification pilotée par la liste des objets PostGIS, formes avec et sans guillemets ; contrôle « zéro référence » en B.3 |
| Les vues de la carte reviennent vides en silence | Droits PostGIS des vues vérifiés ; vues testées via l'API **après** le seed |
| Une adresse de l'ancien projet oubliée | `project_url` partout, échec fermé (testé : URL absente ou mal formée → photo refusée, push non envoyé) ; zéro `.supabase.co` dans les fonctions et les tests |
| Les tests passent… sur l'ancienne base | Le lanceur affiche le projet visé et refuse si `JUNTO_DB_REF` diffère |
| Une règle de sécurité perdue en route | Comparaison automatique stricte (prouvée par son autotest) + 2 060 tests + contre-audit |
| Notifications silencieuses | `--no-verify-jwt` sur `send-push` ; secret identique fonction Edge / `app_config` ; test en porte D |
| Tâches planifiées jamais réactivées | Porte D : 6 tâches actives avec une exécution réussie |
| E-mails non reçus | SMTP reproduit ; test en porte D |
| Publication vers la mauvaise base | Un fichier d'environnement par canal + garde-fou d'hôte |
| Notifications de l'ancien projet vers l'app preview | Jetons de Scott retirés de l'ancien projet (E.0) |
| Notifications en double après bascule | Notifications coupées sur l'ancien projet (F.3) |
| Dérive de schéma pendant la fenêtre | Gel ; correctifs appliqués aux deux ; comparaison relancée avant F |

## 12. Ordre de grandeur

Phases A à C : une à deux sessions (l'essentiel est automatisé, la preuve est longue à faire tourner). Phase D : une session, avec Scott pour les e-mails. Phase E : une session plus les essais de Scott. Phase F : courte. Aucune phase n'est commencée sans la porte précédente.

## 13. Ce qui a changé depuis la v6 (répétition à blanc du 2026-10-22)

1. Prérequis : mot de passe et adresse « session pooler » des deux projets ; `supabase db dump` écarté.
2. Commandes d'export exactes ; export à blanc et contrôles sur le vrai fichier en phase A.
3. Restauration par `psql` dans sa propre session ; lignes `\restrict` retirées ; absence de `CREATE EXTENSION` vérifiée au lieu d'être supposée.
4. Droits par défaut **d'origine de Postgres** pendant la restauration, définitifs après (la v6 les ouvrait en lecture : fuite des colonnes protégées ; la première v7 les fermait : perte de droits implicites).
5. Motifs PostGIS : la v6 ne visait que la forme avec guillemets, absente de l'export réel.
6. Chemins de recherche PostGIS et `project_url` faits sur l'ancien projet (00524) au lieu du jour J ; `pro_photo_url_ok` ajouté (il n'avait pas de chemin fixé).
7. Droits : ceux de l'export, rejoués sous les droits d'origine (plus de `REVOKE ALL` manuel).
8. Filtre d'API abandonné (décision 4) ; tâches créées désactivées dans la même transaction ; droits de `postgres` sur `auth.users` vérifiés en A.2.
9. `push_webhook_secret` provisoire en B.7.
10. Référence du vérificateur statique prise sur l'ancien projet.
11. Comparaison : script réel, prouvé ; liste d'écarts admis en fichier ; réglages hors base comparés par l'API.
12. Tests : lanceur protégé contre la mauvaise base ; tests PostGIS indépendants de l'emplacement ; TX-4 et PV-4 acceptés comme trous de la plateforme.
13. Lectures via l'API relancées après le seed.
14. `--no-verify-jwt` écrit en toutes lettres ; décision sur les clés d'API ; 3 fonctions Edge testées avec une vraie session.
15. Vidage des données de l'app preview par Scott au lieu d'un code de nettoyage.
16. Confirmation du compte de Scott en base (le lien ouvrirait l'app de production).
17. Jetons push de Scott retirés de l'ancien projet avant la bascule (E.0).
18. **Contre-audit du kit (2026-10-22)** : empreintes d'e-mails bannis et leur clé reprises (données de sécurité) ; historique de modération (`admin_actions`, 41 lignes) et registre d'annulations tardives archivés en fichier, non restaurés ; mot de passe saisi à part (jamais en ligne de commande) ; fichiers de construction en accès privé ; contrôle PostGIS indépendant + 9 colonnes + 5 vues ; comparaison à empreintes complètes et ACL réelles ; PV-1 prouvé par l'API au lieu d'attendre qu'il bascule.
