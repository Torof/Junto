# Junto — Gestion des activités

À jour au 28 avril 2026.

## Cycle de vie

```
        create_activity
              ↓
        [published]    ── cancel_activity ──→ [cancelled]
              ↓
   cron flips à starts_at <= NOW()
              ↓
       [in_progress]
              ↓
   cron flips à starts_at + duration <= NOW()
              ↓
        [completed]    ──→ rate_participants notif
                       ──→ badge progression award
              ↓
   peer review window opens (end+15min..end+24h)

   Cas alternatif :
   [published] + starts_at + 2h < NOW() + aucun participant non-créateur
              ↓
        [expired]
```

Le statut est privilégié — jamais write client. Transitions uniquement via SECURITY DEFINER functions avec `set_config('junto.bypass_lock', 'true', true)`.

Voir `docs/SECURITY.md` section "Chaîne d'autorisation par fonction" pour les détails.

---

## Création — `create_activity`

### Prérequis
- Compte authentifié, non suspendu
- 20 activités max par 24h (admins bypass — mig 00144)
- Free tier : limite business additionnelle de 4/mois
- Le `phone_verified` n'est plus un prérequis (disabled depuis mig 00050)

### Champs (RPC `create_activity`)
- `p_sport_id` (référence `sports`)
- `p_title` (3-100 chars, sanitisé)
- `p_description` (max 2000 chars, sanitisé)
- `p_level` (échelle générique ou spécifique au sport — voir `getLevelScale`)
- `p_max_participants` (NULL pour open, sinon [2, 50])
- `p_distance_km` / `p_elevation_gain_m` (optionnels selon sport)
- `p_start_lng`, `p_start_lat` (point de départ)
- `p_meeting_lng`, `p_meeting_lat` (point de RDV — peut différer)
- `p_end_lng`, `p_end_lat` (optionnel)
- `p_objective_lng`, `p_objective_lat`, `p_objective_name` (optionnel — sommet, lac)
- `p_start_name` (libellé du départ)
- `p_trace_geojson` (LineString JSONB, parsée client-side depuis GPX)
- `p_starts_at` (futur)
- `p_duration` (interval — au moins 15min)
- `p_visibility` (`public` | `approval` | `private_link` | `private_link_approval`)
- `p_requires_presence` (boolean, default TRUE)

### Side effects
- `creator_id`, `status='published'`, `created_at` hardcodés
- INSERT auto-participation creator → `accepted`
- Si visibility public/approval → `check_alerts_for_activity` (envoi notifs `alert_match`)
- Si visibility private_link → token UUID générée

---

## Verrouillage des champs

Trigger `handle_activity_update` (whitelist) :

**Inconditionnelles (toujours OLD) :**
- `creator_id`, `status`, `invite_token`, `created_at`

**Conditionnelles (verrouillées si participants acceptés ≠ créateur) :**
- `location_*`, `starts_at`, `level`, `max_participants`, `visibility`

**Modifiables si créateur :**
- `title`, `description`, `sport_id`, `duration`, `requires_presence`, `objective_*`, `start_name`, `trace_geojson`, `distance_km`, `elevation_gain_m`

Modification d'un champ déclenche `activity_updated` notif aux participants acceptés (avec un payload `changes` JSONB) — push uniquement si le changement touche logistique (starts_at, duration, locations).

---

## Modes de visibilité

| Mode | Visible carte | Accès |
|------|---|---|
| `public` | ✅ | Direct |
| `approval` | ✅ | Demande → validation créateur |
| `private_link` | ❌ | Lien partagé |
| `private_link_approval` | ❌ | Lien partagé + validation |

`invite_token` UUID v4 généré à la création pour les modes privés. Régénération via `regenerate_invite_token` (créateur uniquement).

---

## Gestion des participants

### Demandes de participation

`join_activity(p_activity_id)` :
- Auth + non suspendu
- `FOR UPDATE` sur la ligne activité
- Status IN (`published`, `in_progress`)
- Pas créateur, pas bloqué
- Capacité OK (`current_count < COALESCE(max_participants, 50)`)
- Rate limit 10/heure
- Si visibility `public` ou `private_link` → status = `accepted` directement
- Sinon → status = `pending`, créateur reçoit notif `join_request`

### Acceptation / refus (créateur)

`accept_participation(p_id)` / `refuse_participation(p_id)` :
- `auth.uid() = creator_id`
- Status activité IN (`published`, `in_progress`)
- Status participation = `pending`
- Notif au demandeur (`request_accepted` / `request_refused`)

### Exclusion (créateur)

`remove_participant(p_id)` :
- `auth.uid() = creator_id`
- Le ciblé n'est pas le créateur
- Status participation = `accepted` → flip à `removed`
- Le `removed` est terminal — le participant ne peut plus rejoindre via `join_activity` (rejet sur status existant)

### Départ volontaire (participant)

`leave_activity(p_activity_id)` :
- Auth + non suspendu
- `FOR UPDATE` sur la participation (sérialise avec `remove_participant`)
- Status participation IN (`accepted`, `pending`)
- Status activité IN (`published`, `in_progress`)
- Si départ < 12h avant `starts_at` ET activité a `requires_presence = TRUE` → pénalité reliability (mig 00068)
- Le créateur peut lever la pénalité via `waive_late_cancel`
- Notif `participant_left` ou `participant_left_late` selon le timing

---

## Annulation

### Annulation par le créateur

`cancel_activity(p_activity_id)` :
- `auth.uid() = creator_id`
- Status IN (`published`, `in_progress`)
- Flip status → `cancelled`
- Notif `activity_cancelled` à tous les participants acceptés (push gated : seulement si starts_at - now() < 48h, sinon in-app uniquement)
- Pénalité reliability sur le créateur (à confirmer dans la version Bayesian — pas une annulation tardive automatique)

### Annulation par expiration

Cron `transition_statuses_only` flip `published` → `expired` quand :
- `starts_at + 2h < NOW()`
- Aucun participant accepté ≠ créateur

Empêche l'accumulation de pins fantômes. Pas de notif (l'activité n'avait personne).

---

## Validation présence — résumé

Voir `docs/DAY_OF_ACTIVITY.md` pour le détail. Les paths :
1. Background geofence (T-15min..T+15min)
2. Foreground watcher (T-15min..T+15min)
3. App-open initial-state check
4. Activity-detail page poll
5. Manuel "I'm here"
6. QR scan (T-15min..end+3h)
7. Offline replay (cache + drain)
8. Peer review (end+15min..end+24h, threshold 1 ou 2)

---

## Coordination logistique

### Transport

`set_participation_transport(p_activity_id, p_transport_type, p_transport_seats, p_transport_from_name, p_transport_departs_at)` :
- User est participant accepté
- `transport_type` ∈ (`car`, `carpool`, `public_transport`, `bike`, `on_foot`, `other`)
- `transport_departs_at` borné [start - 12h, start + 6h]
- Si type ≠ `car`/`carpool` → seats et departs_at forcés à NULL

`request_seat`, `accept_seat_request`, `decline_seat_request`, `cancel_accepted_seat` — voir `docs/SECURITY.md`.

Auto-expiration des seat_requests pending quand l'activité flippe à completed/cancelled/expired (mig 00142). Notif `seat_request_expired` au requester (le driver reste silencieux — c'est lui qui n'a pas répondu).

### Gear (matériel)

`set_activity_gear(p_activity_id, p_items)` (créateur) — définit la liste de matériel
`add_gear_assignment` / `remove_gear_assignment` (participants) — qui apporte quoi

Catalogue de référence dans `gear_catalog`.

---

## Mur d'événement

`send_wall_message(p_activity_id, p_content)` :
- Auth + non suspendu
- Status IN (`published`, `in_progress`)
- User est participant accepté
- Content sanitisé, max 2000 chars
- Rate limit 30/min/activité (advisory lock)

Soft delete via `delete_wall_message` (auteur ou créateur). Edit via `edit_wall_message` (auteur uniquement, ajoute `edited_at`).

---

## Clôture & post-activité

### Transition completed
- Cron flip `in_progress` → `completed` quand `starts_at + duration <= NOW()`
- Trigger `on_activity_completed_award_badges` :
  - Pour chaque participant accepté : `award_badge_progression` (incrémente joined / sport counters, débloque tier si seuil)
  - Crée notif `rate_participants` → ouvre la peer-review window

### Peer review (end+15min..end+24h)
- Reputation badges (`give_reputation_badge` / `revoke_reputation_badge`)
- Peer presence votes (`peer_validate_presence`)
- Sport-level endorsements (`endorse_sport_level` — confirmer/contester le niveau annoncé)

### Notif relance (end+22h..end+24h)
- `notify_peer_review_closing` envoie un push aux non-voteurs (qui sont confirmed_present mais n'ont voté pour personne)

### Archive
- `completed` activité reste accessible en lecture seule dans :
  - L'historique du créateur (vue `my_activities`)
  - L'historique du participant (vue `my_joined_activities`)

---

## Modification (`update_activity`)

Modification autorisée tant que l'activité est `published`. Modifie uniquement les champs whitelistés.

Tout changement :
- Met à jour `updated_at` automatiquement (via le trigger)
- Insère une notif `activity_updated` à tous les participants acceptés avec un `changes` JSONB
- Push uniquement si le changement touche `starts_at`, `duration`, `location_meeting`, `location_start` (logistique critique)

---

## Suppression d'activité

Pas de DELETE policy — les activités ne sont jamais supprimées directement.
- Annulation = status flip à `cancelled`
- CASCADE via suppression de compte créateur (Edge Function)

---

## Concurrent join — protection

Fonction `join_activity` utilise :
- `FOR UPDATE` sur la ligne activité (lock)
- Comparaison `current_count < COALESCE(max_participants, 50)` après le lock

Sans ces protections, deux requêtes simultanées passeraient toutes deux le check pré-lock et inséreraient deux participations, dépassant la capacité.

---

## V2 / backlog

- Annulation par vote du groupe (2/3 threshold) — design only, pas implémenté
- Liste d'attente automatique si activité complète
- Reporter une activité sans annuler
- Modération admin des activités signalées
- Pénalités progressives selon timing d'annulation
