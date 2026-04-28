# Junto — Définition Produit

À jour au 28 avril 2026.

## Les deux rôles utilisateur

Tout utilisateur connecté est à la fois potentiellement créateur et participant. Ce ne sont pas deux rôles fixes — c'est contextuel. Le même profil, avec des capacités qui se débloquent selon le tier.

---

## Les 3 tiers

### Free
- Rejoindre des activités : illimité
- Créer des activités : 4 par mois (business rule) + cap système 20/24h pour tous les non-admins
- Fonctionnalités de base

### Premium
- Rejoindre / créer : illimité (modulo le cap 20/24h anti-abus)
- Activités privées par lien
- Mise en avant sur la carte
- Création d'alertes (saved searches géolocalisées)
- Profil enrichi

### Pro (Professionnel vérifié)
- Tout le Premium
- Badge "Guide Professionnel Vérifié" — validation manuelle de Junto sur présentation de documents (SIRET, BPJEPS, etc.)
- Vitrine professionnelle complète (liens externes, certifications, spécialités)
- Historique des sorties organisées
- Avis des participants
- Paiement géré entièrement hors app — Junto est vitrine, pas intermédiaire financier
- Sur les pins : badge distinctif "Sortie Pro" visible par tous

### Admin
- Bypass du rate limit `create_activity` (mig 00144) — usage : modération, comptes de test
- Accès aux écrans de modération
- Pas un tier facturable

---

## Les 4 modes de visibilité d'une activité

| Mode | Visible carte | Accès |
|------|---|---|
| Public | ✅ | Direct — accès immédiat au mur |
| Sur acceptation (`approval`) | ✅ | Demande → validation créateur → accès au mur |
| Privé par lien (`private_link`) | ❌ | Lien partagé = accès direct |
| Privé par lien + validation (`private_link_approval`) | ❌ | Lien partagé + validation créateur |

**Règle universelle :** Le mur d'événement est accessible uniquement par les participants acceptés.

---

## Les 5 statuts d'une activité

`activities.status` :
- `published` — par défaut à la création, visible / joinable
- `in_progress` — flippé par le cron quand `starts_at <= NOW()`
- `completed` — flippé par le cron quand `starts_at + duration <= NOW()` ; déclenche `rate_participants` + badge progression
- `cancelled` — flippé par `cancel_activity` (créateur) ; notifie les participants
- `expired` — flippé par le cron quand `starts_at + 2h < NOW()` ET aucun participant non-créateur ; clean-up des pins fantômes

Le statut est privilégié — jamais write client, uniquement via SECURITY DEFINER functions avec `set_config('junto.bypass_lock', 'true', true)`.

---

## Activités open (sans capacité)

`max_participants` peut être NULL — activité "open" sans cap explicite. Le système applique un soft-cap caché de 50 dans `join_activity` pour éviter les abus.

L'UI affiche "Open" / "Sans limite" au lieu d'un compteur fixe.

---

## Présence requise

`activities.requires_presence` (BOOLEAN, default TRUE) — toggle créé en amont.
- Si TRUE : l'activité a un meetup point physique, le système de validation de présence s'active (geofence, QR, peer review)
- Si FALSE : pas de validation, la `confirmed_present` reste NULL pour tous les participants — utile pour des activités déjà-confirmées-d'avance ou des coordinations à distance

Voir `docs/DAY_OF_ACTIVITY.md` pour le flux de validation.

---

## Les 3 niveaux d'information d'une activité

### Niveau 1 — Pin sur la carte
Visible par tous (visiteurs inclus) : icône du sport, statut visuel (orange / vert / gris), titre court au cluster filter.

### Niveau 2 — Pop-up rapide (au tap)
Visible par tous : sport + titre, date / heure, lieu de départ, niveau, places, nom + photo créateur, bouton "Voir l'activité".

### Niveau 3 — Page événement complète
- **Sans compte / non accepté :** infos complètes + description, bouton "Rejoindre" → création de compte
- **Avec compte, non accepté :** peut envoyer une demande de participation
- **Avec compte, accepté :** accès au mur, chat, infos privées de coordination, gestion transport / gear, validation présence

---

## Création d'une activité — Champs

Flow en 4 étapes :

### Étape 1 — Sport + infos
- Type de sport (liste avec icônes, scale niveau spécifique au sport, cf `getLevelScale`)
- Titre (3-100 chars)
- Description (max 2000 chars)
- Niveau requis (échelle générique ou spécifique au sport)
- Nombre de places (NULL = open, sinon 2-50)
- Distance (km) si sport en a (`sportHasDistance`)
- D+ / dénivelé positif si sport en a (`sportHasElevation`)

### Étape 2 — Localisation
- Point de départ (pin sur carte)
- Point de RDV (pin sur carte — peut différer)
- Point d'arrivée (optionnel)
- Point d'objectif (optionnel — sommet, lac, etc.)
- Trace GPX optionnelle (Strava, Komoot, Garmin) — parsée côté client, stockée en `trace_geojson` JSONB ; pas de fichier brut conservé

### Étape 3 — Date / temps / visibilité
- `starts_at` (futur, vérifié serveur)
- `duration_hours`, `duration_minutes`
- Mode de visibilité (4 options)
- `requires_presence` (default TRUE)

### Étape 4 — Récap & publication
- Validation finale + `create_activity` RPC

---

## Système de présence

Voir `docs/DAY_OF_ACTIVITY.md` en détail. Synthèse :

- Geofencing en arrière-plan (T-2h enregistrement, T-15min..T+15min validation)
- QR code fallback (créateur affiche, participant scanne)
- Replay offline pour zones sans réseau (jusqu'à end + 3h)
- Peer review post-activité (end+15min..end+24h)

Conséquence : le `confirmed_present` flip alimente le reliability score et débloque les badges progression.

---

## Système de transport

Mig 00076+. Permet aux participants de coordonner le covoiturage :
- `participations.transport_type` (`car`, `carpool`, `public_transport`, `bike`, `on_foot`, `other`)
- `transport_seats` (places disponibles si conducteur)
- `transport_from_name` (départ de la voiture)
- `transport_departs_at` (heure de départ — bornée [start - 12h, start + 6h])

Demandes via `request_seat`, acceptation via `accept_seat_request`. Auto-expiration des demandes pending à la fin de l'activité (mig 00142).

---

## Système d'équipement (gear)

Mig 00084+. Le créateur définit l'équipement nécessaire ; les participants s'attribuent du matos :
- `activity_gear` — items requis (mig 00084)
- `gear_assignments` — qui apporte quoi
- Catalogue de référence dans `gear_catalog`

---

## Système d'alertes

Mig 00086+. Les utilisateurs Premium / Pro créent des saved searches :
- Localisation + rayon (`activity_alerts.location`, `radius_km`)
- Sport optionnel
- Niveau optionnel
- Période optionnelle (`starts_on`, `ends_on`)

Quand une activité matchant l'alerte est créée, `check_alerts_for_activity` envoie une notif `alert_match` (capée 3/jour/user UTC midnight reset).

---

## Profil utilisateur

- Photo (optionnelle, bucket `avatars` public, path fixe)
- Display name (modifiable, généré aléatoirement à l'inscription)
- Bio (max 500 chars)
- Sports pratiqués + niveau par sport (`levels_per_sport`)
- Historique des activités complétées
- Reliability tier (label public)
- Reliability score (% privé pour soi-même)
- Badges progression (joined / created / sport, tiers t1-t5)
- Badges réputation (visibles si seuil atteint)
- Sport-level endorsements (peer-confirmé / contesté)

---

## Onboarding

### Visiteur (sans compte)
1. Ouverture app → carte centrée sur la position approximative
2. Activités visibles immédiatement — valeur directe
3. Bandeau discret pour s'inscrire / se connecter

### Inscription
1. Email + password (8 chars min)
2. Vérification email obligatoire (template Junto-branded)
3. Onboarding : date_of_birth (>=18), accept_tos
4. Display name aléatoire généré (modifiable)
5. Background location prompt à l'app open (pour la validation présence en arrière-plan)

### Reset password
1. Bouton "Mot de passe oublié" sur le login
2. `requestPasswordReset(email)` envoie un email avec lien `getjunto.app/auth/reset-password`
3. Web bridge → deep link `junto://reset-password`
4. App ouvre l'écran reset, vérifie le token, demande nouveau password
5. Sign out + redirect login avec nouveau password

---

## Notifications

Voir `docs/SECURITY.md` section "Push notifications" pour le routing complet.

Types principaux côté participant :
- `presence_pre_warning` (T-2h)
- `presence_validate_now` (T0 si non confirmé)
- `presence_validate_warning` (T+duration/2 si non confirmé)
- `presence_confirmed` (validation succès)
- `rate_participants` (end)
- `peer_review_closing` (end+22h)
- `participant_joined`, `request_accepted`, `request_refused`
- `activity_cancelled`, `activity_updated`
- `seat_request`, `seat_request_accepted`, `seat_request_declined`, `seat_request_expired`
- `contact_request`, `contact_request_accepted`
- `alert_match`
- `badge_unlocked`

---

## Messagerie

### Conversations privées (DM)
- 1-on-1 entre utilisateurs
- Status `pending_request` (30 jours d'expiration) → `active` ou `declined`
- Bidirectional block check (ni A→B ni B→A)
- Hide-conversation (soft-archive) côté receveur

### Mur d'événement
- Réservé aux participants acceptés
- Filtre `blocked_users` unidirectionnel sur user_id
- Rate limit 30/min/activité/user

### Partage de trace GPX
- `share_trace_message` envoie une trace dans une conversation privée comme attachment ; l'autre participant peut la prévisualiser et l'importer dans son activité

---

## Architecture App Map

### Zone publique (sans compte)
- Carte principale
- Pop-up rapide (niveau 2)
- Page événement (niveau 3) — lecture seule
- Profil utilisateur public — lecture seule
- Écran inscription / connexion

### Connecté — 4 onglets
1. **Carte** — découverte, filtres, création
2. **Mes activités** — créées + rejointes + invitations
3. **Messagerie** — DM + demandes en attente
4. **Profil** — mes infos, badges, settings drawer

### Settings drawer (depuis profil)
- Identité (display name, email — read-only, pseudo edit avec icône crayon)
- Localisation (toggle background location)
- Préférences notifications (granulaire par type)
- Thème (segmented pill : auto / clair / sombre)
- Tier / abonnement
- Légal (FAQ, CGU, privacy, licenses)
- Logout
- Suppression de compte (Edge Function)

### Modération (admin)
- Liste des reports
- Actions : dismiss / suspend user

---

## Règles métier clés

- Le créateur est automatiquement participant accepté à sa propre activité
- Une activité Pro affiche clairement son caractère professionnel sur le pin et le pop-up
- Les paiements pour activités Pro se font entièrement hors app
- Le `confirmed_present` est privilégié — flippé uniquement par les fonctions de présence (geo, QR, peer)
- Le `reliability_score` est auto-calculé Bayesian, jamais write client
- Tout texte user-generated est sanitisé (HTML strip + control chars + 200 char clip pour les notifs)

---

## V2 / backlog

- Discovery feature (people lookup, anti-dating-drift — voir docs/sprint-discovery.md)
- iOS-specific polish (Sign in with Apple) — différé jusqu'à user base
- Map clustering + "search this zone" button — différé à une session UI dédiée
- Live position partagée pendant l'activité
- Stripe pour Premium / Pro
- Statistiques détaillées sur le profil (courbes, ratios)
