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
