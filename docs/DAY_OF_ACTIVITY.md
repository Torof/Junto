# Junto — Le jour de l'activité

Document de référence pour le flux de présence le jour J. À jour au 28 avril 2026 (migrations 00135–00149).

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
- Distance au point de départ (`location_start`)
- Distance au point de RDV (`location_meeting`)
- Distance au point d'arrivée (`location_end`)
- Distance au polyline `trace_geojson` quand l'activité a une trace GPX (mig 00149)

Seuil 150m. Le check polyline ferme le faux-négatif des longues approches (alpinisme, ski de rando) où l'utilisateur peut être au km 5 d'une approche de 10 km, sur la trace mais loin des trois points.

## Notifications

| Moment | Type | Audience | Push ? |
|--------|------|----------|--------|
| T-2h | `presence_pre_warning` | Participants | Oui |
| T0 | `presence_validate_now` | Participants non confirmés | Oui |
| T0 | `qr_create_reminder` | Créateur | Oui |
| T+duration/2 | `presence_validate_warning` | Participants non confirmés | Oui |
| Validation succès | `presence_confirmed` | User validé | Oui |
| End | `rate_participants` | Participants | Non (in-app) |
| End+22h | `peer_review_closing` | Non-voteurs confirmés | Oui |

Tous les types `presence_*` partagent un `collapse_id = 'presence-{activity_id}'` — un seul slot OS par activité, mis à jour au lieu d'être empilé. Les variantes intermédiaires (`validate_now`, `validate_warning`) ajoutent un suffixe `(×N)` au titre selon le nombre de fois que le slot a été touché.

## Détection geofence — flow à deux états

L'app pose une notification locale en arrière-plan via TaskManager :

1. **Présence détectée** (Enter event) — fires immédiatement avec body "Tu es à portée de l'activité, valide ta présence"
2. **Présence confirmée** (RPC réussie) — remplace le slot avec body "Ta présence à cette activité est confirmée"

Si l'RPC échoue sur transport (réseau coupé), le slot reste à "détectée" et l'event est mis en queue offline. Le flusher (sur retour réseau / app foreground) draine la queue ; quand un replay réussit, il met à jour le slot vers "confirmée".

Si l'RPC est rejetée pour cause serveur (window pas ouverte, distance > 150m), le slot reste à "détectée" — on ne ment pas en affichant "confirmée" si la validation n'est pas passée.

## Les 5 paths de validation

### 1. Foreground watcher (`use-presence-geo-watcher`)
- Poll position toutes les 30s pendant que l'app est ouverte
- Filtre client : `now()` dans [T-15min, T+15min]
- Reject si accuracy GPS > 50m (canyon / forêt)
- Si distance ≤ 150m, appelle `confirm_presence_via_geo`
- Pas de notif locale (l'app est déjà ouverte, le toast/state suffit)

### 2. Background geofence task (`presence-geofence-task`)
- Permission "Always" requise
- OS wake l'app sur Enter event
- Fire la notif locale "Présence détectée"
- Tente `confirm_presence_via_geo` ; si succès flip à "Présence confirmée"
- Si pas de session restaurée ou échec transport → enqueue offline

### 3. App-open initial-state check (`use-presence-geofences`)
- Permission foreground suffit (background non requise pour ce path — décorrélé en cleanup mig client)
- Au foreground de l'app, lit la position courante et compare aux régions enregistrées
- Si déjà dans une zone, appelle `confirm_presence_via_geo` — gère le cas où l'utilisateur arrive avant le check Enter

### 4. Activity-detail page poll
- Quand l'utilisateur est sur la page de l'activité
- Poll similaire au foreground watcher mais focused sur cette activité
- Toast in-app sur succès, pas de notif OS

### 5. Manuel — bouton "I'm here"
- Visible quand l'utilisateur est dans la fenêtre de validation
- Appelle le même `confirm_presence_via_geo`
- Server gate filtre comme partout (distance, window, etc.)

### 5b. QR scan (fallback)
- Le créateur affiche son QR depuis l'écran d'activité
- Le participant scanne via la caméra
- `confirm_presence_via_token` valide le token + fenêtre ; pas de check distance (le token suffit)
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
- Auto-show QR du créateur sur l'écran d'activité quand T-15min arrive (réduire la dépendance au reminder)
