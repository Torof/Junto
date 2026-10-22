# Audit complet — octobre 2026

> Protocole : inventaire exhaustif de la base vivante (255 fonctions, 60 tables et vues, 53 policies, 12 policies Storage, 3 buckets, 13 tables publiées en temps réel, 4 tâches cron, 4 Edge Functions), réparti en 8 domaines ; 8 auditeurs adverses en lecture seule avec obligation de couverture (une ligne par élément) ; contre-vérification par Claude, sur la base vivante, de chaque trouvaille CRITIQUE / HIGH / MEDIUM. Les décisions déjà prises par Scott (présence géo déclarée par le téléphone, tri Découverte par score brut, admin autorisé à écrire dans la démo, remplissage des créneaux visible, L16 différé) ne sont pas re-signalées.
>
> **Correctif d'urgence déjà appliqué** : ID-1 (mig 00476). Rien d'autre n'est corrigé : validation de Scott phase par phase.

## CRITIQUE — corrigé en urgence

| # | Trouvaille | Statut |
|---|---|---|
| ID-1 / TX-1 | **Tout compte connecté pouvait réécrire ou supprimer n'importe quel profil, donc tout compte** (cascade sur ~40 tables), via la vue `public_profiles` : vue auto-modifiable sur `users`, possédée par un rôle qui contourne la RLS, et laissée avec les droits d'écriture par défaut de Supabase. Confirmé par un essai neutre annulé. | ✅ 00476 : les 14 vues de `public` en lecture seule pour les rôles clients. L'app n'écrit jamais à travers une vue. |

## HIGH

| # | Trouvaille | Correctif proposé |
|---|---|---|
| TX-2 | **Sans compte, une seule requête peut supprimer le système de coordonnées 4326** dans `spatial_ref_sys` (table PostGIS de `public`, propriété de `supabase_admin`, RLS off, DELETE accordé à `anon`). Toutes les requêtes géographiques tomberaient. Notre rôle ne peut pas retirer ces droits (vérifié). | Filtre `pgrst.db_pre_request` qui refuse toute écriture sur `spatial_ref_sys` (touche toutes les requêtes API → testé avant/après, réversible en une ligne) ; à terme, ticket Supabase pour déplacer PostGIS dans le schéma `extensions`. |

## MEDIUM

| # | Domaine | Trouvaille | Correctif proposé |
|---|---|---|---|
| ID-2 | Comptes | Un compte suspendu lève sa suspension en appelant directement `delete_own_account` (exécutable, sans vérification de suspension) ; l'app recrée un compte vierge au lancement suivant. Blanchit aussi fiabilité et votes négatifs. | Retirer l'exécution aux clients (seule la fonction serveur la lance) ; `ensure_user_row` refuse de recréer un compte supprimé. |
| ID-3 | Comptes | `avatar_url` accepte n'importe quelle adresse → pixel espion (IP de chaque visiteur du profil) ; `sports` sans forme → fait planter l'écran profil. | Ancrer l'avatar au bucket du projet ; CHECK sur `sports`. |
| ID-4 | Admin | Suspendre depuis l'écran de modération (`moderate_report`) saute l'annulation des réservations décidée en 00420 et accepte n'importe quelle cible. | Déléguer à `admin_suspend_user`, cible = celle du signalement, motif obligatoire. |
| AC-1 | Sorties | Écriture directe sur `activities` hors de `update_activity` : changer le sport d'une sortie terminée (transfert de votes de niveau), modifier sans notifier, éditer étant suspendu. | Retirer l'UPDATE direct ; geler `sport_id`. |
| AC-2 | Sorties | Points de départ des conducteurs (souvent le domicile) lisibles par tout compte sur toute sortie publique, même terminée ; un participant retiré garde l'accès. | Coordonnées de covoiturage réservées au créateur et aux acceptés. |
| PR-1 | Présence | Créateur suspendu : n'importe qui peut déclencher la clôture à la demande et tous les non-validés sont marqués absents. | Garde « créateur suspendu » dans `close_presence_window_for` ; retirer `transition_single_activity` / `check_activity_transitions` aux clients. |
| PR-2 | Présence | Les votes de réputation ne sont jamais comptés sur une sortie où tout le monde est validé (le balayage ne la sélectionne pas). | Passe séparée de validation des votes. |
| PR-3 | Réputation | Votes négatifs : le visé voit qui a voté contre lui (représailles), et `get_voters_for_badge` liste les votants de n'importe quel badge, sans seuil. | Votants visibles seulement pour les badges positifs au-dessus du seuil ; seuils appliqués côté serveur. |
| PR-4 | Fiabilité | Se réinscrire efface une pénalité d'annulation tardive. | Pénalités dans un registre que la réinscription ne touche pas. |
| PR-5 | Fiabilité | Retirer une simple demande d'inscription restée sans réponse < 12 h avant est pénalisé comme une annulation tardive. | Pas de pénalité pour une demande en attente. |
| PR-6 | Fiabilité | Lever la pénalité d'un participant est impossible depuis l'app (la liste lue par le créateur est toujours vide). | Lire via la vue réservée au créateur. Fonctionnel. |
| DC-1 | Découverte | La base d'une dispo peut être une adresse exacte (la recherche propose les numéros de rue) et elle est renvoyée sans arrondi → localisation d'un domicile. Contredit la décision #5. | Arrondir la base (~1 km) et la distance ; recherche limitée aux villes et lieux-dits. |
| MS-1 | Messagerie | Un blocage n'est pas appliqué dans les groupes et les canaux : la personne bloquée rejoint tes canaux et y écrit, tu la lis. | Masquer les auteurs bloqués ou suspendus dans groupes et canaux (comme les murs). |
| PO-1 | Pro | Avis publié / supprimé en boucle → notifications push illimitées au pro, même s'il a bloqué l'auteur. | Compter les publications, pas les avis restants ; notifier une seule fois par auteur ; respecter le blocage. |
| TX-3 / PO-3 | Stockage | Les 3 buckets publics sont listables sans compte : identifiants des utilisateurs et photos retirées de l'app restent trouvables et téléchargeables. | Remplacer la lecture publique par la lecture de son propre dossier (les liens publics restent valides) ; purger les fichiers orphelins. |
| CL-1 | App | Un lien de réinitialisation piégé fait basculer un utilisateur connecté sur le compte de l'attaquant, sans le prévenir. | Refuser ces liens si une session existe ; vider le cache à tout changement d'utilisateur. |
| CL-2 | Site | Next.js 15.5.15 : faille connue de déni de service sur le rendu serveur. | Mettre à jour Next.js. |
| BUG (corrigé par le 2e passage) | Sorties / contacts | Les expirations de demandes de covoiturage et de contact ne sont pas dans la tâche planifiée : elles ne tournent que lorsque l'app appelle `check_activity_transitions` à l'ouverture (19 demandes bien expirées, aucune en attente > 48 h). Dépendance au trafic, pas un arrêt. | Les déplacer dans le balayage planifié et retirer la fonction aux clients (PR-1). |

## LOW (résumé)

- **Comptes** : ID-5 admin peut éditer `reports` sans trace ; ID-6 trigger `users` en liste noire (une nouvelle colonne privilégiée serait modifiable) ; ID-7 suppression de compte oublie `channel-photos` ; ID-8 doublons de signalement, `admin_note` lisible par le signaleur ; ID-9 quatre lectures de profil sans prélude suspension, une sans rideau démo ; ID-10 invitations réelles vers une sortie démo.
- **Sorties** : AC-3 `level` sans longueur max ; AC-4 demande de place refusée renvoyable aussitôt ; AC-5 covoiturage et matériel non nettoyés au départ / retrait ; AC-6 notes privées de demande de place lisibles par les co-participants ; AC-7 personnes en attente non prévenues des changements ; AC-8 / TX-5 `invite_token` lisible, un ancien lien public reste valable en privé ; AC-9 erreurs Postgres brutes ; AC-10 notifications de modification sans limite ; AC-11 sortie d'un créateur suspendu encore rejoignable.
- **Présence** : PR-7 badges de progression comptent absences et sorties non vérifiées ; PR-8 QR de présence partageable 30 min ; PR-10 fiabilité ignore sorties supprimées / annulées ; PR-11 seuils comptent les votes, pas les votants ; PR-12 erreur brute sur vote en double ; PR-13 / CL-6 file hors ligne non liée au compte ; TX-6 / PR-14 score brut renvoyé par `get_user_public_stats` (décision à confirmer).
- **Découverte** : DC-2 `get_discovery_count` oracle de localisation sans limite ; DC-3 changement de trace et calcul de trace sans limite (la notification « Itinéraire modifié » peut être répétée) ; DC-4 toutes les colonnes de `activities_with_coords` lisibles sans compte ; DC-6 `create_alert` sans validation ; DC-7 deux dispos possibles pour un même compte.
- **Messagerie** : MS-2 oracle de blocage entre tiers via les groupes ; MS-3 refuser une invitation ne tient pas ; MS-4 anciennes tables de messages encore lisibles ; MS-5 push de message sans nettoyage ; MS-6 canaux : diffusion push sans limite et coupure silencieuse à 50 destinataires ; MS-7 trace partagée non bornée ; MS-8 message supprimé ou canal impossibles à signaler.
- **Pro** : PO-2 réponse / effacement en boucle → notifications ; PO-4 blocage ignoré pour avis et photos communautaires ; PO-5 offre modifiée après réservation sans prévenir ; PO-6 deux lectures sans suspension ; PO-8 adresse de photo contournable par `..` ; PO-9 avis d'un pro suspendu encore lisibles ; PO-11 avis réécrit après la réponse du pro.
- **Socle** : TX-4 privilèges par défaut qui rouvrent l'écriture sur chaque nouvel objet (cause racine d'ID-1) ; app : CL-3 aucun en-tête de sécurité sur le site, CL-4 coordonnées dans les fils d'Ariane Sentry, CL-5 position IP via un service HTTP non chiffré, CL-7 liste d'attente iOS appelle une fonction inexistante.
- **Toujours ouverts des audits précédents** : PRO_HARDENING B8, B9, B10, B11, B15, B16, B17, B6 bis, B18 ; septembre : C1 à C5 messagerie, `admin_set_demo_mode` sans remise à zéro du drapeau ; L16 (différé).

## SAIN (vérifié en profondeur)

RLS activée et forcée sur les 47 tables ; aucune écriture client possible sur les tables réservées aux fonctions ; 248 fonctions privilégiées toutes avec `search_path` ; seules des fonctions de trigger et `demo_content_visible` exécutables sans compte ; toutes les fonctions internes fermées aux clients ; fonctions admin toutes gardées et journalisées ; temps réel : canaux privés, contenu jamais diffusé, sujets réservés aux membres ; push : secret comparé en temps constant, jetons illisibles ; Edge Functions authentifiées, quotas avant lecture, aucune SSRF ; aucun secret dans le dépôt ni l'historique ; rideau démo tenu sur toutes les surfaces de lecture ; aucune conversation active créée sans consentement hors QR ; app : pas de `service_role`, pas de `select('*')`, pas de lien automatique sur le texte utilisateur, session en stockage sécurisé, cache vidé à la déconnexion, Sentry sans données personnelles par défaut.

**Non vérifiable en lecture seule** : réglages Auth du tableau de bord Supabase (confirmation d'email, longueur de mot de passe, URL de redirection, limites de débit) et restrictions des clés Google / Mapbox.

## Second passage (2026-10-21) — 5 angles transverses

Même méthode (lecture seule, base vivante), mais découpage par angle et non par domaine, avec consigne de ne remonter que ce que le premier passage a manqué : **droits** (matrice complète : 95 lignes, 204 fonctions), **accès croisés** (127 fonctions à identifiant), **fuite de données** (matrice colonne sensible → chemins), **règles métier et cycles de vie**, **abus et coûts**. Aucune critique ; le premier passage n'était pas exhaustif.

### HIGH (nouvelles)

| # | Trouvaille | Correctif proposé |
|---|---|---|
| AB-1 | **Inscription / désinscription en boucle** : la limite de 10 inscriptions / h compte des lignes, et une réinscription réutilise la même ligne → un compte peut envoyer des dizaines de milliers de push par heure à un organisateur, avec 200 caractères de texte libre (motif de départ). | Compter les événements ; délai après désinscription ; un seul push « a quitté » par personne et par sortie et par jour. |
| AB-2 | **Diffusion temps réel non filtrée de `activities`** : chaque carte ouverte reçoit toute modification de toute sortie et recharge la carte ; un organisateur qui modifie en boucle sature le temps réel et la base pour tous. | Remplacer par une diffusion limitée en fréquence ; limiter `update_activity` ; supprimer l'écriture directe (AC-1). |
| AB-3 | **Aucun plafond journalier ni de taille sur les messages et les traces partagées** : un compte peut remplir la base (73 Mo aujourd'hui) en moins d'une journée → passage en lecture seule pour toute l'app sur l'offre gratuite. | Plafonds journaliers ; taille maximale des traces partagées (garde existante `trace_geojson_ok`). |

### MEDIUM (nouvelles ou aggravées)

| # | Trouvaille | Correctif proposé |
|---|---|---|
| IX-1 / AC-8 aggravé | Une sortie privée par lien se rejoint avec son seul identifiant : le jeton d'invitation n'est jamais vérifié. Quiconque a vu la sortie quand elle était publique peut la rejoindre. | Exiger le jeton (ou une invitation existante) pour les sorties privées. |
| IX-2 / BR-1 | Une demande de place rouvre une conversation dont la demande de contact avait été refusée, et y dépose un message. Contredit « jamais de conversation active sans les deux consentements ». | Ne toucher à la conversation qu'à l'acceptation du conducteur. |
| BR-2 | Votes de réputation sur une sortie sans vérification de présence : enregistrés, jamais comptés. | Les compter à fin + 24 h, ou ne pas les solliciter. |
| BR-3 | Covoiturage garanti seulement par l'app : un passager peut tenir plusieurs places ; un conducteur peut devenir passager et abandonner ses passagers. | Contrôles dans `request_seat` / `accept_seat_request`. |
| BR-4 | Âge ≥ 18 ans et conditions d'utilisation vérifiés seulement par l'app : un compte qui contourne l'app agit sans les avoir validés (sujet légal). | Contrôle commun dans les fonctions d'action. |
| PV-1 | **Sans compte**, des fonctions statistiques de PostGIS lisent les statistiques internes : rectangle englobant des bases de dispo à quelques mètres près, répartition des points de rendez-vous (sorties privées comprises), nombres de lignes. Non révocable par notre rôle. | Fermé par le déplacement de PostGIS (reconstruction) ; contrôle explicite après. |
| DX-1 | Les absences (`confirmed_present = false`) sont lisibles par tout compte, pour toujours, sur toute sortie publique : historique d'absences constituable. | Ne jamais renvoyer `false` hors créateur ; limiter aux sorties en cours. |
| DX-2 | Le correctif prévu de DC-1 (arrondir à l'affichage) ne suffit pas : en déplaçant sa base pas à pas (sans limite), on retrouve le point exact d'une autre base par les apparitions / disparitions de correspondance. | Arrondir la base **à l'enregistrement** ; limiter les changements de base. |
| AB-4 | Demande de place / annulation en boucle → push et messages illimités vers un conducteur. | Délai après annulation, ou comptage d'événements. |
| AB-5 | Buckets publics utilisables comme hébergeur de fichiers gratuit (aucun plafond d'objets, aucun contrôle « est pro » sur `pro-photos`). | Plafond par dossier ; `pro-photos` réservé aux pros. |
| AB-6 | Un jeton push étranger enregistré par un membre fait échouer silencieusement les push de toute une conversation (lots Expo mixtes). | Envoyer par projet ; écarter les jetons étrangers. |
| AB-7 | Le quota partagé du service d'itinéraire (ORS) épuisable par un seul compte ; pas de délai d'attente. | Plafond global, quota individuel réduit, délai. |
| AB-8 | Texte sans limite (`avatar_url`, `sports`, `level`) servi à chaque affichage de carte, y compris sans compte. | Contraintes de taille. |
| AB-9 | Invocations de fonctions serveur multipliées (une par notification ou message) : quota mensuel épuisable. | Fermer AB-1 / AB-3 / AB-4 ; budget de push par destinataire. |
| AB-10 | Mise à jour du matériel en boucle → tempête temps réel sur tous les écrans de sortie ouverts. | Diffusion limitée ; limite de fréquence. |

**LOW nouvelles** : IX-3 / DX-5 rideau démo absent de 3 lectures de profil ; DX-3 suspension détectable par les lectures de statistiques ; DX-4 date exacte des sorties privées révélée par les niveaux par sport ; BR-5 dispos jamais expirées ; BR-6 réservations en attente passées expirées seulement à la lecture ; BR-7 sortie « en cours » déplaçable dans le futur ; BR-8 sortie retirée par l'admin encore modifiable ; BR-9 deux plafonds sans verrou ; BR-10 place non rendue lors d'un blocage ; BR-11 aucun retrait possible d'un statut pro approuvé ; AB-11 jetons push illimités ; AB-12 quitter un groupe ne tient pas ; AB-13 push « nouveau participant » ignore les préférences ; AB-14 recherche de canaux sans borne ; AB-15 requête carte sans index ; PV-2 744 fonctions PostGIS appelables sans compte (fermé par la reconstruction) ; PV-3 tables avec les droits complets par défaut (seule la RLS protège ; TRUNCATE l'ignore) ; PV-4 file d'envoi HTTP de pg_net lisible par les rôles clients (non exposée aujourd'hui).

**Aggravations confirmées** : AC-1 (écriture directe : aussi date hors limites et visibilité), AC-2 (aussi les sorties privées pour une personne retirée, et les personnes bloquées), AC-6, PR-1, PR-4 (aussi par réinvitation), ID-9, MS-7, CL-1 (aussi par la page de confirmation d'e-mail), CL-4, TX-2 (aussi modification, pas seulement suppression).

## Défauts trouvés par la suite de tests automatiques

| # | Défaut | Détail |
|---|---|---|
| DB-1 | **La recherche de compte par l'admin (`admin_resolve_user`) est cassée pour tout le monde depuis le 2026-07-13** | `WHERE id = v_admin` est ambigu avec la colonne de sortie `id` de `RETURNS TABLE` : erreur SQL avant même la vérification admin. Correctif : qualifier (`users.id`). |
| DB-DC-1 | **« Inviter » depuis Découverte cassé pour tout le monde** (`get_invitable_activities_for_dispo`) | Même cause qu'DB-1 : `WHERE id = v_user_id` ambigu avec la colonne de sortie `id`. Qualifier la colonne. |
| DB-PO-1 | **« Mes réservations » et le formulaire participant ne se chargent pour aucun client** (`get_my_bookings`) | `status` non qualifié dans l'UPDATE d'expiration, ambigu avec la colonne de sortie. Dernière définition : 00422 (2026-09-29). Écrire `bookings.status`. |
| DB-PR-1 / DB-AC-1 | **Rejoindre une sortie déjà quittée échoue** avec une erreur brute de doublon ; accepter une invitation par `join_activity` aussi ; « déjà inscrit » et « retiré » renvoient l'erreur brute | `IF v_existing IS NOT NULL` sur un enregistrement est faux dès qu'un champ est NULL (`refused_at`) → la branche « ligne existante » est sautée. Remplacer par `FOUND` ou `v_existing.id IS NOT NULL`. |
| DB-AC-2 | **Redemander une place au même conducteur après un refus ou une annulation est toujours refusé** (`request_seat`) | Même piège `IS NOT NULL` sur enregistrement : la branche de réactivation est du code mort. |
| DB-PO-2 | **Re-réserver le même créneau chez un pro après une annulation échoue** (`create_booking`) | Même piège (trouvé par recherche systématique : 42 tests NULL sur enregistrement dans 39 fonctions ; seules ces 3 formes `IS NOT NULL` sont fausses, les 39 `IS NULL` sont correctes). |
| DB-TX-1 | Écart de doc : suppression directe de ses propres alertes autorisée (`alerts_delete_own`, voulu depuis 00288) | Corriger la doc (CLAUDE.md, SECURITY.md), pas la base. |
| PO-9 | **Fausse alerte de l'audit** : les avis des offres d'un pro suspendu ne sont pas lisibles (la sous-requête passe par la RLS de `pro_offerings`). | Gardé comme test de non-régression. |

## Phase A des correctifs — livrée (mig 00477, 2026-10-21)

Les 6 bugs trouvés par la suite de tests, chacun corrigé avec la faille qu'il masquait par accident : DB-1, DB-DC-1, DB-PO-1 (colonnes qualifiées) ; DB-PO-2, DB-PR-1/DB-AC-1, DB-AC-2 (test de l'identifiant au lieu de l'enregistrement) ; **AB-1** (délai de 15 min avant de rejoindre une sortie quittée + une seule notification « a quitté » par participant et sortie sur 24 h) ; **PR-4** (colonne `late_cancel_at` : l'annulation tardive survit à une réinscription, reprise des annulations existantes) ; **PR-5** (retirer une demande en attente n'est pas pénalisé) ; **AC-4 / AB-4** (redemande de place : 24 h après un refus, 1 h après une annulation ou une expiration). Codes d'erreur `junto.rejoin_cooldown`, `junto.seat_request_cooldown` (5 langues). Suite : 1 381 pass, 0 fail, 88 failles connues restantes.

## Phase A2 — livrée (mig 00478, 2026-10-21) — résidus de la contre-vérification de A

- **DB-MS-1** (nouveau bug trouvé par `plpgsql_check`) : la liste « partenaires récents » (inviter, créer un groupe) était cassée pour tout le monde (`get_recent_partners`, colonne ambiguë). Corrigé. `plpgsql_check` ne signale plus aucune fonction de l'app.
- **PR-4 complété** : la colonne de 00477 s'effaçait avec la ligne (refus d'une nouvelle invitation, cascade de blocage) et comptait double après un retour suivi d'un verdict → table `late_cancels` (une ligne par personne et sortie), comptée sans verdict de présence et hors sorties annulées / retirées ; une nouvelle annulation tardive réarme une levée.
- **PR-6 corrigé** : levée de pénalité possible après réinscription ; l'organisateur voit enfin ses départs tardifs (`get_late_leavers`, créateur seul — la lecture directe était limitée par la RLS à sa propre ligne, liste toujours vide).
- **AB-1 affiné** : au plus une notification de départ **par type** et par 24 h (un départ anticipé ne masque plus l'avis de départ tardif).
- Laissé tel quel (LOW) : le délai après refus de place se mesure depuis la demande, faute d'horodatage de décision.

Suite : 1 405 pass, 0 fail, 87 failles connues restantes.

## Phase B — livrée (mig 00479, 2026-10-21) — les deux HIGH restantes

- **AB-3** : 500 messages / 24 h par compte ; 20 traces et 50 sorties partagées / 24 h ; trace partagée bornée à 1 Mo par la garde commune (**MS-7** corrigé). Codes `junto.message_daily_cap`, `junto.share_daily_cap` (5 langues). Index `messages (sender_id, created_at)`.
- **AB-2** : `activities` et `participations` retirées de la publication postgres_changes ; à la place, un signal sans contenu sur le canal privé `map` (comptes connectés), au plus une fois par sortie toutes les 15 s, seulement pour les sorties publiques / sur demande non démo et un champ visible sur la carte ou une place qui change. Identité de réplication de `activities` et `activity_gear` revenue à DEFAULT. L'app écoute ce signal et recharge la zone (avec anti-rebond). Effet assumé : un visiteur sans compte et un membre d'une sortie privée voient la carte se mettre à jour au déplacement et non en direct.
- **AB-10** : le matériel passe sur le canal privé de la sortie (`activity:<id>`) ; plus de suppressions envoyées à tous les écrans ouverts.
- Noté pour le nettoyage : les écoutes `pro_profiles` / `pro_offerings` de l'app ne reçoivent rien (ces tables ne sont pas publiées).

Suite : 1 421 pass, 0 fail, 85 failles connues restantes. Plus aucune faille HIGH ouverte hors celles liées à PostGIS (TX-2, PV-1 : fermées par la migration).

## Phase B2 — livrée (mig 00480-00482, 2026-10-21) — résidus de la contre-vérification de B

- **Compteur de fréquence commun** `private.rate_hit(type, limite, fenêtre)` sur la table `rate_events` (aucun accès client, verrou par compte et par type, purge quotidienne). Code `junto.too_many_actions` (5 langues).
- **AC-1** : plus aucune écriture directe sur `activities` (UPDATE retiré, policy supprimée ; INSERT/DELETE/TRUNCATE résiduels retirés aussi, de même sur `activity_gear` et `activity_gear_missing`). L'app n'écrivait jamais en direct.
- **AC-10 / DC-3** : `update_activity` 30 / h, `update_activity_trace` 20 / h, `compute_trace_stats` 600 / h (le tracé recalcule à chaque point). Une trace invalide envoyée au calcul est comptée quand même et ne renvoie aucune statistique.
- **AB-10 (suite)** : matériel 20 mises à jour / min et 200 / h, objets manquants 30 / min et 300 / h ; un seul signal par instruction, et un seul pour une mise à jour complète du matériel (au lieu d'un par objet).
- **Signal carte** : lieu d'arrivée, noms de lieu, distance, D+, présence d'une trace et présence exigée déclenchent aussi le signal ; verrou de limitation pris seulement quand la fenêtre est écoulée ; table `map_broadcasts` sans journal et purgée.
- **Traces partagées** : taille et fréquence vérifiées avant le parcours des coordonnées ; budget de 5 Mo / 24 h en octets bruts ; code `junto.trace_too_large`.
- **Points faibles refusés par Scott, corrigés (mig 00483-00484)** :
  - un changement de nom ou d'avatar, une suspension ou une réactivation de l'organisateur émet un signal carte (un seul par changement, ≤ 1 / 15 s et 30 / h par organisateur) ;
  - une trace invalide envoyée à `update_activity_trace` est comptée (la fonction renvoie le code au lieu de lever ; l'app lève côté client) ;
  - `trace_geojson_ok` réécrite en jsonpath : 31 ms → 2 ms sur 10 000 points, donc un appel raté coûte autant qu'une requête ordinaire pour les cinq fonctions qui valident une trace ; trous corrigés au passage (objet sans `type` accepté, objet sans `coordinates` en erreur brute, nombres infinitésimaux qui plantaient le calcul du D+).
- Restent, rares et réservés à l'admin : passage d'un compte en démo, bascule du mode démo, icône ou catégorie d'un sport ne déclenchent pas de signal carte (rafraîchi au déplacement). Les anciennes versions de l'app en production ignorent le code renvoyé par `update_activity_trace` : une trace invalide y semble enregistrée sans l'être.

Suite : 1 459 pass, 0 fail, 80 failles connues restantes.

## Phase vie privée — livrée (mig 00485-00489, 2026-10-21)

- **AC-2** : point de départ des conducteurs (nom et coordonnées) réservé aux membres acceptés d'une sortie à venir ou en cours, jamais à travers un blocage ; les lieux de départ du résumé transport restent visibles par tous (décision Scott, 00490 : on sait d'où partent les voitures, pas qui — le transport par personne est masqué aux non-membres) ; point de prise en charge des passagers réservé au conducteur, au passager et à l'organisateur une fois la sortie terminée.
- **DX-1** : une absence n'est visible que par l'organisateur et la personne ; les non-membres ne reçoivent aucune coche (sinon l'absence se déduisait d'une sortie finalisée) ; la revue entre pairs ne renvoie plus « absent » ; **TX-6** score brut retiré de `get_user_public_stats`.
- **DC-1 / DX-2** : base des dispos arrondie au centième de degré dès l'enregistrement (bases existantes reprises), distance en km entiers, 30 enregistrements / jour. **DC-2** : compteur limité aux rayons de la liste, point sondé arrondi, 300 appels / h (anti-rebond côté app).
- **MS-1** : auteurs bloqués ou suspendus masqués dans les groupes et canaux (messages, aperçus, non-lus, notifications).
- **AC-6** : les co-participants ne lisent plus les demandes de place en direct.
- **IX-1** : une sortie privée (simple ou sur demande) ne se rejoint et ne se lit qu'après avoir ouvert son lien (30 jours), via un partage direct de l'organisateur, ou après s'en être désisté ; jamais pour une personne retirée ou bloquée par l'organisateur. Corrige au passage un bug : une sortie privée partagée par l'organisateur ne s'ouvrait pas chez le destinataire.
- **AC-8** : `invite_token` illisible en direct (droits par colonne) ; passer une sortie en privée change son lien.
- **IX-2 / BR-1** : une demande de place ne rouvre plus un contact refusé ou en attente par le conducteur (notification seulement).
- **TX-3** : buckets non listables (lecture de son propre dossier).
- Erreur de reconstruction rattrapée par la suite : `request_seat` reconstruite depuis une copie antérieure à la phase A (00486), réparée en 00487.
- Restent : **DC-4** (ce qu'un visiteur sans compte voit d'une sortie, décision Scott, demande une version de l'app d'abord) ; finesse de l'arrondi en zone peu dense (option : 2-5 km ou centre de commune) ; photos orphelines du stockage (phase de nettoyage) ; invitation d'un non-contact à une sortie privée sans accès après acceptation (LOW, fonctionnel).

Suite : 1 501 pass, 0 fail, 65 failles connues restantes.

## Phase fiabilité — livrée (mig 00491-00496, 2026-10-21)

- **PR-1** : la sortie d'un organisateur suspendu n'est jamais finalisée (quel que soit l'appelant), ni pendant la suspension ni après réactivation (finalisation seulement entre fin + 24 h et fin + 48 h) ; elle reste figée à l'ouverture (pas de rappel, pas de demande de vote). `check_activity_transitions` retirée aux clients ; la tâche minute l'appelle, étapes isolées.
- **BUG expirations** : demandes de place et de contact expirées chaque minute côté serveur.
- **PR-2** : votes comptés sur une sortie où tous étaient validés. **BR-2** : votes d'une sortie sans validation de présence **non comptés** (deux comptes pouvaient se fabriquer ou salir une réputation) — décision Scott attendue : ne plus les solliciter (recommandé) ou les compter malgré le risque.
- **PR-7 / PR-10** : absences et sorties retirées exclues des trophées, niveaux par sport, badges de progression et de la fiabilité.
- **PR-3 / PR-11 / PR-12 / IX-3** : un vote négatif ne révèle jamais son auteur (votants listés pour les traits positifs à partir de 5 personnes ; traits négatifs renvoyés seulement à partir du seuil d'affichage ; date au mois ; lignes de vote lisibles par leur seul auteur) ; seuils et réputation en personnes ; double vote sans erreur ; rideau démo.
- **BR-4** : âge et CGU exigés pour toute action au niveau des données (déclencheur sur les tables d'action, acceptation d'invitation et de contact).
- **BR-3** : une place par passager (garde-fou unique) ; un conducteur avec passagers ne monte pas ailleurs, un passager placé ne propose pas de places ; ses autres demandes sont retirées quand l'une est acceptée.
- **AC-3, AC-11, BR-5, BR-7, BR-8** : niveaux bornés ; pas de participation chez un organisateur suspendu ; dispos passées ignorées ; date et durée figées pendant la sortie ; sortie retirée figée (ni modification ni vote).
- Reste (LOW) : les votes de niveau par sport s'affichent dès 1 vote (décision Scott du 2026-07-07, conservée).

Suite : 1 528 pass, 0 fail, 44 failles connues restantes.

## Décisions Scott + phase intégrité — livrées (mig 00497-00505, 2026-10-21)

- **Décisions Scott** : plus de demande de vote ni de vote sur une sortie sans validation de présence (écran d'évaluation explicite) ; **pas deux sorties au même créneau** (rejoindre, demander, accepter une invitation, être accepté, créer, déplacer sa sortie) ; lieux de départ des voitures visibles par tous, sans dire qui.
- **TX-2 (HIGH) — filtre d'API** : PostgREST refuse toute écriture sur `spatial_ref_sys` / `geometry_columns` / `geography_columns` (hook `db_pre_request`, vérifié en réel : DELETE / PATCH refusés, lectures intactes). Les droits eux-mêmes (rôle supabase_admin) tombent avec la migration.
- **Intégrité** : DX-3 (suspendu : aucune statistique, niveau, trophée), DX-4 (dates au mois), DC-6 (alertes validées), DC-7 (une dispo par compte), MS-8 (message supprimé et canal signalables), MS-2 (ajout à un groupe sans révéler un blocage), AB-12 (pas de remise dans un groupe quitté pendant 30 jours), MS-3 (invitation refusée jamais renvoyée, même par une demande de contact), MS-5 (caractères de contrôle retirés des notifications, côté base et côté envoi), AB-14, B11, ID-3 (avatar et photos de canal dans son propre dossier, sans « .. »).
- **Pro** : PO-8, PO-4 (personne bloquée : ni avis, ni photo), PO-5 (prix demandé gardé, repris à la re-soumission), PO-6, PO-11 (« avis modifié » notifié, texte propre), PO-1 / PO-2 (pas de notification répétée, par cible), B8 (offres, avis, favoris et vues limités aux pros approuvés ; un pro en attente prépare ses offres, invisibles).
- **Droits** : aucune écriture client par défaut sur les nouvelles tables ; plus de TRUNCATE / TRIGGER / REFERENCES / MAINTAIN pour les clients.
- **Restent** : 17 failles connues — 12 fermées par la migration (PostGIS, droits de supabase_admin, pg_net), 2 de nettoyage (ancienne table des murs, suppression directe de ses alertes = écart de documentation), DC-4 ×2 et ID-2 (décisions Scott), L16 (prochaine version de production). Proposé, non fait : bouton « Signaler » sur message / groupe / canal + fermeture d'un canal par l'admin (interface).

- **ID-2 (décision Scott, mig 00506)** : un compte suspendu peut s'effacer, mais l'empreinte HMAC de son e-mail (pas l'e-mail) bloque la réinscription, variantes « +tag » et majuscules comprises ; réinscription par le support.
- **Signalement (mig 00507 + app)** : bouton « Signaler » sur un message (conversations et murs de sortie), un groupe, une discussion ouverte ; l'admin peut retirer un message ou un groupe et fermer une discussion.

- **DC-4 fermé comme choix assumé (Scott)** : avant connexion, la carte ne montre que les points (sorties et pros), sans clic ; un lien partagé ouvre la page complète d'une sortie publique. Les fiches pros (contacts) ne sont pas lisibles sans compte.

Suite : 1 586 pass, 0 fail, 14 failles connues restantes (12 fermées par la migration, 1 de nettoyage, L16 à la prochaine version de production).

## Phase de nettoyage — livrée (mig 00508-00509, 2026-10-21)

- Anciennes tables des murs et messages privés retirées (les messages de covoiturage vont directement dans la messagerie), 11 fonctions mortes, table `contacts`, vue `public_participants`, table et écran du témoignage de présence entre pairs, colonnes mortes, 6 index en double ; purge quotidienne du journal cron (42 Mo).
- App : 5 composants et les méthodes jamais appelées supprimés, écoutes temps réel muettes retirées, types régénérés et ~160 contournements de typage retirés.
- **Bug trouvé par la régénération des types** : depuis 00441, les listes « Mes sorties » (créées / rejointes / en attente) échouaient — colonne `meeting_locality` absente des vues (00509, test ajouté).
- Stockage : 6 photos orphelines supprimées. Documentation (CLAUDE.md, SECURITY.md, sprint-messaging.md) réécrite depuis la base réelle.
- Pour la re-sécurisation : droits d'écriture inutiles sur ~30 tables ; protection des colonnes de `users` / `activities` par liste de colonnes figées (une nouvelle colonne n'est pas protégée par défaut) ; EXECUTE accordé par défaut aux comptes sur toute nouvelle fonction ; fonctions de déclencheur exécutables par les clients ; 4 fonctions sans `search_path` ; reliquat `wall_message` dans `admin_remove_content`.

## Re-sécurisation — audit neuf en 4 domaines et corrections (mig 00510-00518, 2026-10-22)

- **Lot 1 (00510-00511)** : `users` en vraie liste blanche (6 champs de profil) ; droits d'écriture client seulement là où une policy existe, aucun pour anon ; plus d'EXECUTE par défaut sur une nouvelle fonction (défaut global retiré) ; fonctions de déclencheur et utilitaires internes fermés ; `search_path` fixé.
- **TX-2 (HIGH, 00512)** : le filtre d'API se contournait par un chemin encodé (`DELETE /spatial%5Fref%5Fsys` → 204 en réel). Toute écriture à chemin encodé est refusée ; vérifié en réel.
- **Identité (00513)** : HIGH — un suspendu supprimant son profil par la seule RPC gardait sa connexion et `ensure_user_row` recréait un profil propre ; fermé (refus de l'e-mail interdit, écran suspendu → suppression complète, purge des photos de canal). Empreinte Gmail normalisée, changement d'e-mail vers un e-mail interdit refusé ; ID-4 (signalement → suspension de la seule personne visée, chemin complet) ; CL-1 (lien de connexion refusé si une session est ouverte, cache vidé au changement de compte) ; `users.sports` borné.
- **Messagerie (00514-00515 + send-push)** : une demande de place n'ouvre plus de conversation (seul l'accord du conducteur) ; pas de remise dans une copie de groupe ; groupes modérés et discussions fermées figés ; un suspendu ne lit plus aucune conversation ; invitation Découverte après refus bloquée ; demandes de contact de suspendus masquées ; discussions ≤ 500 membres et notifications à tous ; 10 appareils par compte.
- **Sorties (00516-00517)** : piège de l'annulation tardive refermé (demande acceptée par l'organisateur à moins de 12 h, ou organisateur suspendu) ; demandeurs prévenus des changements ; durée figée avec participants ; sortie modérée figée partout ; coordonnées réelles exigées ; transport et levée limités ; pas d'entrée après départ + 15 min ; suspendus : ni trophées, ni réputation, ni votants.
- **Pro (00518)** : **L16 fermé** + raison sociale et motif de refus non publics ; liens web contrôlés en table ; photos de contributeurs suspendus masquées ; offres bornées ; verrou réservation / suppression ; purge à J+30 des coordonnées saisies.
- Restent (LOW, connus) : MS-2 résiduel (l'absence après ajout trahit un blocage — inhérent, comme `create_group`) ; AB-6 / AB-9 (format des jetons push, budget de notifications par destinataire) ; PRO_HARDENING B9, B10, B15, B16, B17, B18 ; décision produit : un pro approuvé peut renommer sa vitrine sans nouvelle validation.

- **Contre-vérification (00519)** : pas de remise par une copie de groupe quel que soit son auteur ; groupe retiré par la modération en lecture seule ; suppression de compte uniquement par la fonction delete-account (le rôle service l'exécute pour l'utilisateur vérifié : connexion et fichiers toujours effacés) ; erreurs lisibles avant les contrôles de table ; durée figée hors du test de chevauchement et verrouillée à l'écran ; plafond d'appareils par dernier usage.
- Reste (LOW) : un lien de connexion piégé peut connecter une personne *déconnectée* au compte de l'attaquant (login-CSRF) — fermeture possible en n'acceptant que les liens à jeton haché.

Suite : 1 582 pass, 0 fail, 12 failles connues restantes (toutes fermées par la migration : PostGIS, droits de supabase_admin, pg_net).

## Passe finale avant migration — 4 analyses neuves (mig 00523-00524, 2026-10-22)

Contrat app ↔ base vérifié mécaniquement (173 appels de fonctions, 73 lectures et écritures, 109 codes d'erreur dans 5 langues, 42 types de notification, temps réel, stockage, fonctions Edge), chasse aux bugs fonctionnels, qualité de la suite de tests, répétition à blanc du plan de migration.

- **Covoiturage (00523)** : un passager qui quitte la sortie ou en est retiré gardait sa place (compteur faux, conducteur jamais prévenu) ; un conducteur retiré laissait ses passagers assis ; une place annulée par un blocage n'était jamais rendue. Désormais un déclencheur sur `participations` libère les liens (avis `seat_passenger_left` / `driver_left`) et un déclencheur sur `seat_requests` rend la place pour toute fin de place acceptée.
- **Niveaux (00525)** : le calcul des points de niveau du profil ne reconnaissait que « intermédiaire / avancé / expert » en minuscules, alors que l'app enregistre « Intermédiaire » ou des cotations (« 6b »…) — profils bloqués à 1 point. `private.level_tier` traduit chaque valeur vers les 4 niveaux simples (échelles de `src/constants/sport-levels.ts`, à garder synchronisées) ; le profil n'affiche toujours que les points (Scott, après explication).
- **Trophées (00523)** : une présence validée après la fin n'attribuait rien (effet de bord de « présence validée seulement », 00521). Déclencheur sur `confirmed_present`.
- **Jour de Paris (00523)** : 17 fonctions de réservation, disponibilité, alerte et purge comptaient en jour UTC (créneaux de la veille réservables entre minuit et 1-2 h). `private.today_paris()`. Les demandes de réservation dépassées ne bloquent plus le client.
- **Notifications (00523)** : appui sur un push vers le bon écran (`by`, `pro_id`, `offering_id`, `booking_id` transmis) ; une demande retirée emporte sa notification ; **décision Scott F2** : l'organisateur est prévenu quand un blocage retire une demande (`join_request_blocked`, sans dire qui) ; invitations reçues hors du plafond d'inscriptions ; pas d'invitation à une sortie verrouillée ; un message de covoiturage fait réapparaître un fil masqué ; modifications et suppressions de messages diffusées en direct ; « sortie modifiée » activé par défaut (décision Scott).
- **App** : le bouton « Débloquer » n'apparaissait jamais (colonne `id` inexistante sur `blocked_users`) ; les visiteurs lançaient des requêtes interdites ; note sous l'option sans validation de présence (**décision Scott F9**) ; 12 codes d'erreur morts retirés ; formulaire iOS du site retiré (sa fonction n'existait pas).
- **Préparation migration (00524)** : adresse du projet dans `app_config.project_url`, lue par les 7 fonctions en échec fermé (testé : adresse absente ou mal formée → photo refusée, push non envoyé) ; `extensions` dans le chemin des 6 fonctions PostGIS ; `pro_photo_url_ok` avec chemin fixé. Plan v7 (17 corrections, voir `docs/MIGRATION_PLAN.md` §13), script de comparaison prouvé, lanceur de tests protégé contre la mauvaise base.
- **Tests** : `08_garde_fous` (214 vérifications, une par règle de 00467-00522 qu'aucun test ne protégeait) ; `09_passe_finale` (91, chacune échoue sans la correction qu'elle garde) ; une quinzaine de tests trop permissifs resserrés (motif d'erreur exact, ou vérification qui ne pouvait pas échouer).
- Restent (connus) : le refus d'inscription au moment même où un blocage existe n'est pas signalé à l'organisateur (seules les demandes déjà en attente le sont) ; les deux cosmétiques du cycle de vie (expiration d'une sortie solo à départ + 2 h par le chemin à la demande, code mort du balayage).

Suite (à blanc avec 00523-00524) : 2 060 pass, 0 fail, 12 failles connues (migration : PostGIS, droits de supabase_admin, pg_net).

## Audit après migration — nouveau projet `fajfigpwfdwmchhzecwe` (2026-10-22)

- **Objectifs atteints** : PostGIS hors de `public` et hors d'atteinte de l'API (404/406) ; tous nos objets à `postgres` ; aucune extension dans `public` ; structure identique (0 écart inattendu) ; adresse du projet dans `app_config` seulement ; tâches actives (268 exécutions, 0 échec) ; démo fidèle ; clé des empreintes identique ; suite 2 079 pass / 0 fail (10_migration : 16 gardes, prouvés en cassant 8 choses).
- **Failles visées** : TX-2, PV-1/PV-2 fermées côté API ; filtre d'API retiré sans dépendance ; TX-4 et PV-4 = réglages de la plateforme, inatteignables par un client.
- **Corrigé dans la foulée** : historique du dépôt (F.6) ; garde-fou de publication preview (le cache Metro garde les adresses insérées d'une construction à l'autre — prouvé) ; 24 comptes de démo bloqués à vie.
- **Restent (décisions / actions)** : adresse de retour `https://getjunto.app/**` à retirer (tableau de bord) ; captcha et réauthentification au changement de mot de passe = fonctionnalités app à prévoir ; mots de passe divulgués (offre Pro) ; `graphql_public` encore exposé sans l'extension (identique à l'ancien, sans effet) ; clés d'API classiques (nouveau modèle à décider avant F) ; contrainte `reputation_votes_check` NOT VALID (préexistante) ; fichiers de travail locaux à détruire après F (la clé des empreintes y figure en clair, accès réservé).

## Plan de correction proposé (validation Scott par phase)

1. **Urgence** : TX-2 (filtre d'API), TX-4 (privilèges par défaut), CL-2 (Next.js).
2. **Comptes et admin** : ID-2, ID-3, ID-4, CL-1, puis LOW identité.
3. **Vie privée** : AC-2, DC-1, MS-1, TX-3, puis DC-2, DC-4, AC-6, AC-8.
4. **Équité de la fiabilité** : PR-1 à PR-6, BUG expirations, puis LOW présence.
5. **Intégrité des sorties** : AC-1, puis LOW sorties.
6. **Anti-spam** : PO-1, PO-2, DC-3, AC-4, AC-10, MS-3, MS-6.
7. **Reste des LOW et documentation.**

Chaque phase : reconstruction depuis la définition vivante, puis contre-audit indépendant des correctifs.
