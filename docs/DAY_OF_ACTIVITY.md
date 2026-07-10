# Junto — Le jour de l'activité

Document de référence pour le flux de présence le jour J. À jour au 10 juillet 2026 (fenêtres 00292, RDV unique 00306, durcissement client juillet 2026).

## Vision

Le jour J, valider la présence doit être :
- **Automatique quand c'est possible** (geofence en arrière-plan, watcher en avant-plan)
- **Manuel quand l'auto échoue** (bouton "I'm here", scan QR du créateur)
- **Récupérable post-coup** (peer review pendant 24h après la fin)

Aucun utilisateur ne devrait être enregistré comme absent simplement parce qu'il était dans une zone sans réseau ou avait fermé l'app.

## Fenêtres de validation

| Phase | Fenêtre | Mécanisme |
|-------|---------|-----------|
| Enregistrement geofence (OS) | T-2h → T+15min | `Location.startGeofencingAsync` |
| Validation géo serveur | T-15min → T+15min | `confirm_presence_via_geo` |
| Validation QR | T-15min → end + 3h | `confirm_presence_via_token` |
| Émission token QR | T-15min → end + 3h | `create_presence_token` |
| Replay offline (deadline arrivée) | end + 3h | `confirm_presence_via_geo(.., p_captured_at)` |
| Peer review | end + 15min → end + 24h | `peer_validate_presence` |

L'asymétrie est intentionnelle : la fenêtre d'enregistrement OS commence à T-2h pour donner au système le temps de détecter une transition "outside → inside". Si on enregistrait à T-15min seulement et que l'utilisateur était déjà sur place, aucun event Enter ne se déclencherait jamais.

## Distance check

`confirm_presence_via_geo` calcule le minimum entre :
- Distance au point de RDV (`location_meeting` — NOT NULL depuis mig 00306, qui a fusionné l'ancien point de départ dedans)
- Distance au point d'arrivée (`location_end`)
- Distance au polyline `trace_geojson` quand l'activité a une trace GPX (mig 00149)

Seuil 150m. Le check polyline ferme le faux-négatif des longues approches (alpinisme, ski de rando) où l'utilisateur peut être au km 5 d'une approche de 10 km, sur la trace mais loin des trois points.

## Notifications

| Moment | Type | Audience | Push ? |
|--------|------|----------|--------|
| T-2h | `presence_pre_warning` | Participants non confirmés | Oui |
| T-10min | `presence_pre_warning_10min` | Participants non confirmés | Oui |
| T-10min | `qr_create_reminder` | Créateur (QR button live dès T-15min) | Oui |
| T+duration/2 | `presence_validate_warning` | Participants non confirmés | Oui |
| Validation succès | `presence_confirmed` | User validé | Conditionnel (skip_push=TRUE par défaut) |
| End | `rate_participants` | Participants | Non (in-app) |
| End + 1h | `presence_validate_overdue` | Participants non confirmés | Oui |
| End + 22h | `peer_review_closing` | Voters avec ≥1 peer non-confirmé restant à voter | Oui |

Tous les types `presence_*` partagent un `collapse_id = 'presence-{activity_id}'` — un seul slot OS par activité, mis à jour au lieu d'être empilé. Suffixe `(×N)` au titre selon le nombre de fois que le slot a été touché dans la fenêtre 24h.

## Détection geofence — flow à deux états

L'app pose une notification locale en arrière-plan via TaskManager :

1. **Présence détectée** (Enter event) — body "Tu es à portée de l'activité, valide ta présence". Trois cas selon le moment de l'Enter (l'identifier de région porte `starts_at`) :
   - **Avant T-15** : la notif est DIFFÉRÉE (trigger DATE) pour sonner à l'ouverture de fenêtre — pas de RPC ni de mise en queue (l'ancre serveur serait refusée de toute façon). Annulée si la présence est confirmée entre-temps ou si l'activité sort de la liste des candidats (leave/cancel).
   - **T-15..T+15** : notif immédiate + fix GPS frais + RPC.
   - **Après T+15** : notif immédiate UNE SEULE FOIS par activité (dédup AsyncStorage 30h) comme invite au scan QR — pas de RPC, pas de queue.
2. **Présence confirmée** (RPC réussie) — la "détectée" est dismissée + la programmée annulée, et "confirmée" part sous un identifiant DISTINCT (re-poster sur le même id est silencieux sur Android).

Si l'RPC échoue sur transport (réseau coupé), l'event (coordonnées RÉELLEMENT mesurées — jamais le centre de région, qui donnerait distance 0 au serveur) est mis en queue offline : dédup par épisode de 10 min, max 3 events/activité, TTL 30h. Le flusher (retour réseau / app foreground) draine ; un replay réussi flippe la notif vers "confirmée".

Si l'RPC est rejetée pour cause serveur (`junto.presence_*` ou auth) c'est TERMINAL : l'event est droppé de la queue et la notif "détectée" est retirée — on ne laisse pas traîner "valide ta présence" pour une validation impossible.

## Les paths de validation (post mig 00166)

Tous les paths automatiques GPS appellent `confirm_presence_via_geo` (server-gated : auth, suspension, status ∈ published/in_progress/completed, deleted_at IS NULL, T-15..T+15, participation accepted, distance ≤ 150m, idempotent). Le path QR appelle `confirm_presence_via_token`.

### 1. Foreground watcher (`use-presence-geofences` — `runForegroundWatcher`)
- Démarre quand au moins une activité est dans T-15..T+15 et l'app est foreground
- `Location.watchPositionAsync(Accuracy.High, 5s)` jusqu'à 60s
- Reject si accuracy > 100m
- Sur fix in-zone (rayon 300m), appelle `confirm_presence_via_geo` avec `p_skip_push: true`

### 2. Initial-state check (`use-presence-geofences` — `initialStateCheck`)
- Au foreground de l'app, prend une fix `Accuracy.High` immédiate
- Si déjà dans la zone (≤300m), appelle `confirm_presence_via_geo`
- Couvre le cas "user déjà sur place avant que l'OS fire Enter"

### 3. Background geofence task (`presence-geofence-task`)
- Permission "Always" requise — `Location.startGeofencingAsync` enregistre les régions
- OS wake l'app sur Enter event → schedule notif locale "Présence détectée"
- Demande une fix fraîche (`getCurrentPositionAsync(Accuracy.High)`, budget 8s) plutôt que d'utiliser le centre de la région (évite les false positives de fused-location stale)
- Sur succès RPC → dismiss "détectée", schedule "Présence confirmée" sous identifier `${slotId}-confirmed` (sound)
- Sur échec transport / fix coarse → enqueue offline

### 4. Foreground service location task (`presence-foreground-service` + `presence-location-task`)
- Démarre quand l'app est foregroundée pendant T-15..T+15 (kické par `usePresenceGeofences`)
- `Location.startLocationUpdatesAsync` avec `foregroundService` config (notif Android persistante "Junto valide ta présence")
- Stream GPS Accuracy.High en continu — survit au backgrounding initial mais ne démarre pas si l'app n'a jamais été ouverte pendant la fenêtre (limite OEM, hors v1)
- Sur succès RPC → schedule "Présence confirmée" + auto-stop le service

### 5. Offline replay (`presence-offline-cache`)
- Queue AsyncStorage : enqueue chaque échec transport / no-session des paths #3, #4
- Drain au foreground / NetInfo reconnect (`use-presence-offline-flusher`)
- Replay envoie le `captured_at` original ; serveur accepte jusqu'à T+duration+3h

### 6. QR scan (`confirm_presence_via_token`)
- Le créateur affiche son QR depuis activity-detail (bouton + auto-show, visibles T-15min..T+duration+3h — alignés serveur)
- Le participant scan via caméra → token validé + fenêtre serveur (T-15..T+duration+3h)
- Pas de check distance (la possession physique du QR suffit)
- Auto-flip du créateur à `confirmed_present = TRUE` si pas encore validé (couvre le cas 2-participants)

### 7. Peer testimony (`peer_validate_presence`)
- Pas un path GPS, mais une 3ème voie : 2 votes de participants `confirmed_present = TRUE` flip un peer non-confirmé à TRUE
- Émission post-event : tous les confirmed reçoivent `rate_participants` ; à T+22h les voters avec ≥1 peer non-confirmé restant à voter reçoivent `peer_review_closing`
- Side effect : si scanner ≠ créateur, le créateur est lui-même auto-validé (preuve qu'il était là)

## Replay offline

Cas d'usage outdoor : alpinisme, ski de rando, kayak. Le réseau peut être absent du meetup jusqu'à 1-2h après la fin.

Le client cache localement (AsyncStorage) :
```ts
{ activity_id, lng, lat, captured_at }
```

Conditions de stockage :
- L'RPC `confirm_presence_via_geo` échoue sur transport (network error)
- OU la session n'est pas encore restaurée (background task qui réveille avant supabase-js)

Le flusher (`use-presence-offline-flusher`) draine sur :
- App foreground
- NetInfo reconnect

Sur replay réussi, le slot OS bascule à "Présence confirmée".

Bornes serveur :
- `p_captured_at` doit être dans la fenêtre live (T-15min, T+15min)
- L'arrivée du replay doit être ≤ end + 3h
- Distance toujours ≤ 150m
- Single-shot (`confirmed_present IS NULL`)

Trade-off connu : envelope non signée, un participant accepté pourrait fabriquer `captured_at` + coordonnées. Atténuation : bornes window/distance + check social (badges réputation `level_overestimated`, `unreliable_field`). Signature server-side reportée jusqu'à ce qu'un abus soit observé.

## Peer review (post-activité)

Si la validation auto a échoué (utilisateur sans téléphone, batterie morte, GPS bloqué indoor) :

- Fenêtre : T+15min → T+24h après end
- Threshold :
  - **2 participants au total** : 1 vote suffit (le créateur peut directement valider l'autre — aucun pool de pairs alternatif n'existe)
  - **3+ participants** : 2 votes requis (le créateur n'a aucun privilège, il est juste un voter parmi d'autres)
- Voter must be `confirmed_present = TRUE` lui-même (sauf cas créateur en 2-participant)

Erreurs différenciées (mig 00139) :
- `peer_review_window_not_open` (avant T+15min)
- `peer_review_window_closed` (après T+24h)
- `peer_voter_not_present`
- `peer_already_validated`

Notif `peer_review_closing` envoyée à T+22h aux non-voteurs (relance pour les retardataires).

## Auto-validation cascade — résumé

L'utilisateur n'a généralement aucune action à effectuer :
1. Si réseau OK + GPS OK → auto via geofence ou foreground watcher
2. Si pas de réseau au meetup → cache offline puis replay au retour
3. Si GPS HS / indoor → fallback QR (créateur affiche)
4. Si tout a échoué → peer review post-activité

L'unique cas où la présence ne peut pas être validée du tout : utilisateur sans téléphone ET seul participant confirmé OU activité 2-participants où le créateur ne valide pas non plus. Edge case absolu — peer review ne peut rien sans au moins un peer confirmé.

## Reliability score

À chaque flip de `confirmed_present`, `recalculate_reliability_score` met à jour le score de l'utilisateur. Bayesian avec PRIOR = 3, exposé via `reliability_tier` (>= 90 excellent, >= 75 good, >= 50 fair, < 50 poor).

Vu publiquement comme un tier (label) ; vu en clair (%) uniquement par l'utilisateur lui-même.

## Diagnostic

Sentry breadcrumbs sur chaque leg (`lib/sentry.trace`) :
- `presence.geofence` — Enter event, RPC outcome, enqueue
- `presence.watcher` — in-zone detection, RPC outcome, accuracy rejects
- `presence.offline` — enqueue, flush start, replay outcomes

Les coordonnées exactes ne sont jamais incluses (lat/lng dans la liste sensible de `lib/sentry`). Seules les distances arrondies, les codes de raison, et les timestamps.

## Backlog post-launch

- In-app distance feedback ("tu es à 220m de la zone") sur l'écran d'activité quand on est dans la fenêtre — ferme le mystère du fail silencieux à 160m
- Mock-location detection (Android `ALLOW_MOCK_LOCATION`)
- Signed geo-proof token pour l'offline replay (clore la fabrication possible des envelopes non signées)
