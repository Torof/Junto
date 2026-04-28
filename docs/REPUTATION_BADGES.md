# Junto — Réputation & Badges

Document de référence pour le système de réputation et de badges. À jour au 28 avril 2026 (migrations 00134, 00135 + suivantes pour les notifs et flips de présence).

## Vue d'ensemble

Trois piliers conçus pour encourager les bons comportements, créer de la confiance entre inconnus, et gamifier l'expérience sans tomber dans le jugement subjectif :

1. **Reliability score** — automatique, basé sur la présence confirmée
2. **Badges réputation** — attribués par les pairs après une activité
3. **Badges progression** — automatiques, par tier (5 niveaux × 3 catégories)

Aucun badge ne s'affiche tant qu'un seuil n'est pas atteint — protection contre les manipulations ponctuelles.

---

## Pilier 1 — Reliability score

### Calcul

Bayesian avec PRIOR = 3 (présume une fiabilité raisonnable au démarrage). Recalculé à chaque flip de `participations.confirmed_present` via `recalculate_reliability_score`.

Formule conceptuelle :
```
score = (PRIOR + nb_confirmed_present) / (PRIOR + nb_total_participations)
```

Stocké dans `users.reliability_score` (privilégiée — jamais write client).

### Tiers

| Tier (i18n key) | Seuil | Label affiché |
|---|---|---|
| `excellent` | ≥ 90 | Excellente |
| `good` | ≥ 75 | Bonne |
| `fair` | ≥ 50 | Correcte |
| `poor` | < 50 | Faible |
| `new` | NULL (pas assez de données) | Nouveau |

### Visibilité

| Champ | Soi-même | Autres connectés | Anon |
|---|---|---|---|
| `reliability_tier` (label) | Oui | Oui | Non |
| `reliability_score` (% brut) | Oui | Non | Non |

Le ring SVG sur le profil hero affiche le score en pourcentage pour soi-même, et le label tier pour les autres.

### Pénalités sur la fiabilité

- Présence non confirmée à la fin d'une activité (post peer review window) → comptée comme un no-show
- Annulation tardive (`leave_activity` < 12h avant start) → pénalise selon `late_cancel_only_when_presence_required` (mig 00068)
- Le créateur peut lever la pénalité (`waive` action depuis l'organisation tab)

---

## Pilier 2 — Badges réputation (peer-voted)

### Principe

Attribués par les participants après une activité partagée. Positifs ou négatifs. Visible sur le profil uniquement quand le seuil cumulé est atteint.

### Fenêtre d'attribution

Pendant la peer-review window : **end + 15min → end + 24h**. Au-delà, `give_reputation_badge` rejette.

### Règles

- Voter et voted doivent être tous deux participants acceptés de la même activité
- Voter ≠ voted
- Attribution optionnelle (pas obligatoire après chaque sortie)
- UNIQUE constraint sur `(voter_id, voted_id, activity_id, badge_key)` — pas de double vote pour le même badge sur la même activité
- Le voter peut retirer son vote via `revoke_reputation_badge`

### Badges positifs (seuil 5)

| Key | Icône | i18n FR | Short FR |
|---|---|---|---|
| `trustworthy` | 🤝 | De confiance | Fiable |
| `great_leader` | ⭐ | Super leader | Leader |
| `good_vibes` | 😊 | Bonne ambiance | Ambiance |
| `punctual` | ⏱️ | Ponctuel | Ponctuel |

### Badges négatifs (seuil 15)

| Key | Icône | i18n FR | Short FR |
|---|---|---|---|
| `level_overestimated` | ⚠️ | Niveau surestimé | Niveau |
| `difficult_attitude` | 😤 | Attitude difficile | Attitude |
| `unreliable_field` | 🎭 | Peu fiable | Inconstant |
| `aggressive` | 😠 | Agressif | Agressif |

Les short labels sont utilisés sur l'écran peer-review (cellules métro à deux lignes : emoji + short label).

### Visibilité

- Avant seuil : invisible pour tout le monde, y compris le voted
- Après seuil : visible publiquement sur le profil
- Le filtre `blocked_users` cache les votes des utilisateurs bloqués au niveau de l'affichage individuel, mais les comptes restent dans la moyenne globale (intégrité préservée)

---

## Pilier 3 — Badges progression (automatiques)

Système tiered en 3 catégories × 5 tiers (mig 00135). 100% objectif, aucune subjectivité, aucune manipulation possible.

Auto-attribution via le trigger `on_activity_completed_award_badges` qui appelle `award_badge_progression` à chaque flip d'activité vers `completed`. Notif `badge_unlocked` envoyée à chaque level-up.

### Tiers

| Tier | Seuil (count) | Joined | Created | Sport |
|---|---|---|---|---|
| t1 | 5 | Membre | Initiateur | Curieux |
| t2 | 10 | Actif | Organisateur | Adepte |
| t3 | 20 | Régulier | Animateur | Mordu |
| t4 | 50 | Habitué | Coordinateur | Passionné |
| t5 | 75 | Pilier | Bâtisseur | Inconditionnel |

Constantes en TypeScript (mig client) :
```ts
TIERS = [
  { key: 't1', min: 5,  max: 9 },
  { key: 't2', min: 10, max: 19 },
  { key: 't3', min: 20, max: 49 },
  { key: 't4', min: 50, max: 74 },
  { key: 't5', min: 75, max: Infinity },
]
```

### Catégories

- **joined** — comptage global d'activités complétées en tant que participant
- **created** — comptage global d'activités complétées en tant que créateur
- **sport** — comptage par sport (clé du sport, ex `hiking`, `climbing`)

Le compteur de la catégorie `sport` augmente uniquement quand l'utilisateur a participé à une activité de ce sport (créateur ou participant).

### Stockage

Table `user_badge_progression` :
- `user_id`
- `category` (`joined` | `created` | `sport`)
- `sport_key` (NULL pour joined / created)
- `count`
- `tier` (NULL avant t1)
- `tier_unlocked_at`

Géré exclusivement par `award_badge_progression`. Aucune écriture directe par client.

### Affichage profil

Le composant `badge-display` rend des chips circulaires (icon-only) avec :
- Compteur en overlay (×N)
- Pill du tier en dessous
- Tap → modal "ladder" qui montre les 5 tiers avec le tier courant highlighted

Pour la catégorie sport, l'icône est l'emoji du sport (`getSportIcon`) et non un trophée générique.

---

## Notifications

| Trigger | Type | Body (FR) |
|---|---|---|
| Tier unlocked | `badge_unlocked` | "Tu as débloqué {{label}} !" avec dynamic label selon catégorie / tier |
| Activity completed | `rate_participants` | "Évalue tes co-participants" — ouvre la peer-review window |
| End + 22h | `peer_review_closing` | "Fenêtre de validation qui se ferme" — relance les non-voteurs |

Le `rate_participants` notif route vers l'écran `/peer-review/{id}` qui combine reputation badges + peer presence validation.

---

## Anti-abus

### Restrictions sur les peer votes

- Voter doit être participant accepté de l'activité (peer ou créateur)
- Voter ≠ voted
- UNIQUE sur `(voter, voted, activity, badge_key)` empêche le double-vote

### Collusion résiduelle

Connue : 2 confirmed friends peuvent biaiser les votes en activité 3-personnes. Atténuation : badges réputation négatifs comme `level_overestimated` / `unreliable_field` peuvent contre-balancer le pattern. Pas de détection automatique de collusion implémentée.

### Blocked users — directionnalité

`blocked_users` filtre l'affichage individuel mais pas la moyenne globale :
- A bloque B → A ne voit pas les votes de B sur son profil
- Les votes de B comptent toujours dans la moyenne agrégée
- L'évaluation globale reste honnête, l'affichage filtre

### Gating fenêtre

Toutes les fonctions reputation sont gated par la peer-review window (end + 15min → end + 24h). Empêche les votes "à froid" longtemps après l'activité.

---

## Visibilité agrégée sur le profil

L'ordre d'affichage suit le composant `badge-display` :
1. **Reliability ring + tier** (en haut, en cercle autour de l'avatar)
2. **Badges progression** (joined / created / sport — chips avec count + tier)
3. **Reputation badges** (positifs visibles si seuil 5 atteint, négatifs visibles si seuil 15)
4. **Sport-level endorsements** (mig 00097 — confirmer/contester le niveau annoncé du voted user)

---

## Utilisation côté créateur

Lors de la gestion des demandes de participation, le créateur voit :
- Le `reliability_tier` (label, pas le %)
- Les badges progression actuels
- Les badges réputation visibles (au-dessus du seuil)

Cela permet une décision éclairée avant d'accepter ou refuser, sans révéler le score brut (qui reste privé au demandeur).

---

## Backlog post-launch

- Seuils différenciés pour les badges négatifs selon la gravité
- Modération des badges contestés (le voted user peut signaler un vote abusif)
- Statistiques détaillées sur le profil (ratio par tier, courbe d'évolution)
- Sport-specific badges (au-delà du tier généraliste, ex "Grimpeur acharné" sur 50+ sorties escalade)
- Anti-collusion server-side (pattern detection sur les votes croisés répétés)
