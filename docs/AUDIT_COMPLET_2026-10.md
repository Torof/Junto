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
| BUG | Sorties / contacts | **Les demandes de covoiturage et de contact n'expirent jamais** : la tâche planifiée appelle `transition_statuses_only`, qui n'inclut pas `expire_idle_seat_requests` / `expire_stale_contact_requests` (seule une fonction jamais appelée les lance). | Ajouter les deux expirations au balayage planifié. |

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

## Plan de correction proposé (validation Scott par phase)

1. **Urgence** : TX-2 (filtre d'API), TX-4 (privilèges par défaut), CL-2 (Next.js).
2. **Comptes et admin** : ID-2, ID-3, ID-4, CL-1, puis LOW identité.
3. **Vie privée** : AC-2, DC-1, MS-1, TX-3, puis DC-2, DC-4, AC-6, AC-8.
4. **Équité de la fiabilité** : PR-1 à PR-6, BUG expirations, puis LOW présence.
5. **Intégrité des sorties** : AC-1, puis LOW sorties.
6. **Anti-spam** : PO-1, PO-2, DC-3, AC-4, AC-10, MS-3, MS-6.
7. **Reste des LOW et documentation.**

Chaque phase : reconstruction depuis la définition vivante, puis contre-audit indépendant des correctifs.
