# Sprint — Suite de gestion Pro (booking & agenda)

> Créé le 2026-09-17. Vision Scott : remplacer, pour un professionnel du sport, le besoin
> d'un site perso + site de booking + bureau des guides + page Facebook. Les pros sont le
> moteur de revenu (abonnement) ; les utilisateurs paient au plus un déblocage unique.
> Décision de renversement loggée dans DECISIONS.md (2026-09-17).
> **Jamais de paiement in-app** (responsabilité légale) — on paie sur place.

## Principe directeur (Scott, 2026-09-17) — l'outil mono-joueur

Le système booking/organisation doit valoir l'adoption **à lui seul** : un pro qui
n'utilise rien d'autre de Junto doit quand même vouloir ce calendrier. Les clients
venus de Junto sont un bonus, pas un prérequis. Conséquences : la **réservation
manuelle hors-app est v1** (l'agenda = source de vérité unique dès le jour 1, clients
sans compte inclus) ; la **page publique de réservation (P2) monte en priorité** ;
le **flux ICS** (lecture seule vers Google Calendar) est retenu comme pont d'adoption.

## Phasage de la suite (vision)

| Phase | Contenu | Remplace |
|---|---|---|
| **P1 — Booking & agenda (CE sprint)** | Dispos par demi-journée, demandes de réservation, accepter/refuser/annuler, notifs, chat à l'acceptation | Le site de booking, le standard téléphonique |
| P2 — Page pro publique web | La page pro du site web (web/app/pro existe déjà) enrichie + CTA réserver → deep link app | Le site internet perso |
| P3 — Gestion clients | Historique par client, notes privées du pro, stats simples (taux de remplissage) | Le carnet / Excel |
| P4 — Communication | Actualités du pro poussées à ses anciens clients / followers | La page Facebook |

P2-P4 : idées cadrées, non design-ées — ne rien construire sans repasser par la case discussion.

## P1 — Modèle de données (validé sur le principe, en attente du GO final)

### `pro_availabilities`
- `pro_id → users ON DELETE CASCADE` · `day DATE` · `period TEXT CHECK ('am','pm')`
- `UNIQUE (pro_id, day, period)` — présence de ligne = disponible
- Bornes : `day >= current_date`, `day <= current_date + 6 mois`
- RLS ENABLE+FORCE, SELECT own only, zéro write policy, whitelist trigger, écritures via RPC

### `bookings`
- `offering_id → pro_offerings ON DELETE CASCADE` · `pro_id`/`client_id → users ON DELETE CASCADE`
- `day DATE` · `period ('am','pm')` · `party_size` (1 → max_participants de l'offre si défini)
- `message` ≤500 HTML-strippé · `CHECK (client_id != pro_id)`
- `status CHECK ('pending','accepted','declined','cancelled','cancelled_pro','expired')`
- `UNIQUE (offering_id, client_id, day, period)` ; resubmit façon seat_requests (reset si
  declined/cancelled/expired ; refus si pending/accepted) ; slot de rate-limit conservé
  après decline (anti-oracle, pattern 00350)
- RLS : SELECT parties uniquement (`private.user_is_suspended`, jamais de sous-requête users),
  écritures 100 % RPC, whitelist trigger

### Chaînes d'autorisation (à re-valider ligne à ligne au moment du code)

- `set_pro_availability` : auth → non suspendu → triple check pro (tier + pro_profiles + approved) → bornes → upsert/delete own.
- `create_booking` : auth → non suspendu → ≠ soi → pro approuvé + non suspendu → offre du pro + gate démo → blocage bidirectionnel → demi-journée dispo → date future ≤6 mois → party_size dans bornes → strip HTML → advisory lock + caps (5 pending/client, 10/24h) → INSERT → notif `booking_request` (copy générique, message dans data).
- `accept_booking` : auth → non suspendu → caller = pro → client non suspendu → re-check blocage → FOR UPDATE + `WHERE status='pending'` guardé → DM créé/activé (double consentement frais : demande = consentement client, accept = consentement pro — peut réactiver une ligne pending/declined existante) → notif `booking_accepted`.
- `decline_booking` : idem → flip declined → **notif au client** (déviation assumée du decline silencieux : logistique, pas social).
- `cancel_booking` (client, pending|accepted → cancelled, notif pro si accepted) ·
  `cancel_booking_pro` (pro, accepted → cancelled_pro, notif client — cas météo).
- Lectures : `get_pro_availability(pro_id)` (gated : approuvé/non suspendu/futur), `get_pro_agenda(range)` (own), `get_my_bookings()` (client).

### Garde-fous périphériques
- `delete_pro_offering` / `unregister_as_pro` : REFUS si réservations futures pending/accepted (`junto.offering_has_bookings`).
- Expiration : pending à date passée → expired (filtre lazy + sweep).
- Codes : `junto.booking_slot_unavailable`, `booking_pending_cap`, `booking_daily_cap`, `booking_party_size`, `offering_has_bookings` (+ i18n FR/EN).
- 4 types de notifs ajoutés aux préférences (pattern 00168) ; jamais de texte client dans title/body de push.
- Post-v1 à réexaminer : avis conditionnés à une réservation ?

### Décisions v1 validées explicitement (Scott)
- [x] Pas de paiement, jamais (2026-09-17)
- [x] Demi-journée dès la v1 (2026-09-17)
- [x] Tout in-app, pas d'email (2026-09-17)
- [x] Calendrier de dispos pro (pas de demande libre) (2026-09-17)
- [x] Réservation manuelle hors-app en v1 (client sans compte : nom + tél saisis par le pro) (2026-09-17)
- Défauts recommandés, à infirmer sur maquette sinon actés : DM activé à l'acceptation
  (double consentement frais, réactivation d'une ligne declined possible) · decline
  notifie le client (logistique, pas social) · pas de décompte de capacité (le pro
  groupe/juge) · fiche client opérationnelle (questions par offre : poids/pointure/
  niveau) reportée en **v1.5**.

### Ajout modèle pour la réservation manuelle
`bookings.client_id` devient NULLABLE + `manual_name TEXT` / `manual_phone TEXT`
(CHECK : soit client_id, soit manual_name — jamais les deux ni aucun ; manual_* saisis
et visibles par le pro seul). Créée directement `accepted` via `create_manual_booking`
(chaîne : auth → non suspendu → triple check pro → offre à soi → bornes date → strip).
Pas de notif, pas de conversation. Comptée dans l'agenda, pas dans les rate limits client.

## UI (après GO sur le modèle)
Aucune grille calendrier n'existe dans l'app → composant mensuel am/pm fait main.
Écrans (maquettes dans l'artifact booking, 2026-09-17) :
- **« Espace pro » (hub, demandé par Scott 2026-09-17)** — entrée unique de la gestion :
  Agenda · Demandes (badge) · Réservations à venir (7 j) · Messages clients (messagerie
  existante filtrée) · Mes offres (rapatrié) · Ma page publique (prévisualiser/partager).
  Stats + historique clients = P3 (place réservée dans le hub, non construits).
- « Agenda » pro (grille + demandes + confirmés + « Ajouter une résa » manuelle)
- Flux « Réserver » client (grille lecture seule → demi-journée → taille + message).
Méthode : maquette artifact → validation → RN.

## État d'avancement
- ✅ 2026-09-17 : DB v1 complète (migs 00416-00417, chaînes dans SECURITY.md).
- ✅ 2026-09-17 : côté PRO shippé preview (commit b1948be) — Espace pro (hub, menu),
  Agenda (AvailabilityCalendar am/pm fait main, demandes accepter/refuser, à venir,
  résa manuelle), booking-service, i18n FR/EN, types régénérés.
- ✅ 2026-09-20 : côté CLIENT shippé preview (commit 1347be5) — CTA Réserver sur
  offering-detail → écran book/[offeringId] (calendrier pick, stepper, message,
  paiement-sur-place affiché) ; « Mes réservations » (statuts, annulation, chat) +
  entrée menu ; routage notifications booking_* (request→agenda pro,
  accepted→conversation, declined/cancelled→bon écran selon data.by). Clés EN.
  **La boucle booking P1 est COMPLÈTE de bout en bout.**
- ✅ 2026-09-28 : **UX v2 shippée preview** (maquette validée par Scott — artifact
  booking-ux-v2, 3 principes : consulter ≠ éditer · hub = tableau de bord · créneaux
  avant calendrier ; + retours Scott : teinte univers-sport sur les créneaux réservés,
  places prises/libres côté client). Mig 00421 (get_pro_availability+taken,
  agenda/bookings enrichis sport+lieu+prix, set_pro_availability_bulk). RN :
  AvailabilityCalendar modes view/edit/pick + couleurs sport + initiales client ·
  Agenda lecture par défaut + fiche jour (clients, tél, fermer créneau, résa
  pré-datée) + mode édition (bannière + raccourcis week-ends/mois/semaine-type/
  tout-fermer) + confirmations refuse/annule · Espace pro dashboard (aujourd'hui
  actionnable, 1ʳᵉ demande inline, tuiles badgées) · badge demandes sur l'entrée
  Menu · flux client (liste créneaux + capacité + « Complet » grisé + calendrier
  repliable + récap prix indicatif) · puces prochaines dispos sur l'offre
  (pré-sélection) · Mes réservations (À venir/Passées + carte billet lieu+prix).
  NON inclus (question ignorée = non, réf. maquette) : fiabilité client sur la
  demande ; drag-paint des dispos (2ᵉ temps si besoin confirmé).
- 🧭 2026-09-28 : **observation du système pro + cadrage des chantiers** (artifacts
  systeme-pro-observation + chantiers-pro-cadrage, arbitrés par Scott) :
  RETENUS, dans l'ordre — **A** matériel nécessaire sur l'offre (fourni / à apporter,
  2 jsonb sur pro_offerings, rappel dans le billet client) · **B** fiche participant
  (champs par offre, remplie À L'ACCEPTATION, visible fiche jour) · **C** carnet
  clients simple (dérivé des bookings, notes privées pro-only, 3 stats) ·
  **E1+E3** pont web (page publique anon-safe curée + flux iCal token — revue
  adverse avant mise en ligne) · **D** la voix du pro (posts, audience = favoris
  00342 ± anciens clients, cap 2/sem) · **E2** booking web sans compte (APRÈS
  décision (a)/(b) de Scott). PARKÉ : report météo en un geste. PAS BESOIN
  (Scott) : au-delà — la barre qualité = « le guide de 55 ans gants aux mains ».
  Décisions ouvertes listées dans l'artifact cadrage (seed chat matériel,
  fiche bloquante ou souple, RGPD notes, audience voix, (a)/(b) web).
- ✅ 2026-09-29 : **chantiers A + B CONSTRUITS et shippés preview** (maquette v3
  validée « je pars dans le même sens que toi » — langage page réelle, zéro pilule
  d'affichage ; fiche APRÈS confirmation ; pas de répétition dans le chat seed).
  Mig 00422 : equipment_provided/required + participant_fields sur pro_offerings,
  participant_info sur bookings, RPC set_offering_details (ownership + validation
  listes ≤15×60c / std ⊆ catalogue / custom ≤3×80c) + set_booking_participant_info
  (client de LA résa ou pro si manuelle, accepted only, date future, validation
  stricte contre les champs demandés) ; vue coords + get_pro_agenda + get_my_bookings
  enrichies. AUCUN DROP des RPC d'offres (compat production). RN : formulaire offre
  (tags matériel ×2 + check-rows fiche + questions libres), fiche offre (section
  Matériel en lignes texte), billet client (ligne 🎒 + bouton « Compléter la fiche
  du groupe » → écran booking-form/[id]), fiche jour pro (lignes numérotées par
  participant + « n fiches manquantes » orange). i18n FR+EN. TODO v1.1 : rappel
  « fiche incomplète » la veille (cron) — non construit, badge + notif d'acceptation
  suffisent pour l'instant.
- ⏳ v1.5/P2 restants hors chantiers ci-dessus : question acompte sans paiement
  in-app (champ conditions — intégrable au chantier A/E1) · fiabilité client
  visible sur la demande (toujours en attente de décision) · report météo (parké).
