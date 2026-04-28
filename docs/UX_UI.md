# Junto — UX / UI

À jour au 28 avril 2026.

## Identité visuelle

### Ton général
Aventure et adrénaline, sans excès. "Outdoor sérieux" — puissant mais pas agressif. Référence vestimentaire : Arc'teryx, Patagonia.

### Mode
Dark mode + light mode disponibles. Préférence utilisateur via le segmented pill dans le settings drawer (`auto` / `clair` / `sombre`).

### Pattern visuel signature
**Topo SVG decorative background** — courbes de niveau dessinées en SVG, opacité ~6%, utilisées sur :
- Login screen (visiteur)
- Profile hero (carte du profil)
- Card hero patterns

Génère un sentiment outdoor sans surcharger.

---

## Palette de couleurs (`src/constants/colors.ts`)

### Dark theme (par défaut)
| Rôle | Hex |
|---|---|
| Fond principal | `#0D1B2A` |
| Surface (cards) | `#1B3A5C` |
| Surface alt (chips, segments) | varie selon contraste |
| CTA / Accents | `#F4642A` |
| Texte primaire | `#F5F5F0` |
| Texte secondaire | `#8A9BB0` |
| Texte muted | gris foncé |
| Line / borders | gris bleuté |
| Success | `#2ECC71` |
| Error | `#E74C3C` |
| Warning | `#F39C12` |

### Light theme
Background `#F5F5F0`, surfaces blanches, mêmes accents (CTA orange invariant).

### Pins de carte
- Orange (`#F4642A`) — meeting point (RDV)
- Vert (`#2ECC71`) — start
- Bleu — end
- Couleur sport — objectif

---

## Typographie (`src/constants/typography.ts`)

- **Titres :** Montserrat Bold
- **Corps :** Inter Regular
- **Tailles** (`fontSizes`) : `xs: 12, sm: 14, md: 16, lg: 18, xl: 24, xxl: 32`

---

## Tokens (`src/constants/spacing.ts`, `radius.ts`)

- **Spacing :** `xs: 4, sm: 8, md: 16, lg: 24, xl: 32`
- **Radius :** `sm: 8, md: 12, lg: 16, full: 999`

Le radius `full` (999) est utilisé partout pour les pills, badges, segmented controls, et CTA principaux — pas de "border-radius généreux" approximatif, c'est pill explicite.

---

## Composants visuels signatures

### Reliability ring (sur le profil)
- Cercle SVG autour de l'avatar (80px)
- Fill % proportionnel au reliability score
- Couleur band selon le tier (green ≥ 75, orange 40-74, red < 40)
- Pill % (chiffre) collé en bas du ring (visible pour soi-même uniquement)
- Tier label (Excellente / Bonne / Correcte / Faible) à côté pour les autres

### Stat row (profile hero)
- 3 cellules avec dividers : completed / created / joined
- Chaque cellule : nombre en grand, label coloré dessous
- Labels : `numberOfLines={1}` + `adjustsFontSizeToFit` pour éviter les wraps

### Badge display
- Chips circulaires icon-only (40px)
- Compteur en overlay (×N format)
- Pill du tier label en dessous
- Tap → modal "ladder" qui montre les 5 tiers avec le tier courant highlighted
- Pour la catégorie sport : icône = emoji du sport (`getSportIcon`)
- 4 badges par ligne dans la grille

### Metro pill (peer review)
- Une seule rangée pill par participant : 4 cellules badges positifs + divider + 4 cellules badges négatifs
- Chaque cellule à 2 lignes : emoji top, short label dessous
- Voted = cellule tintée (success/22 ou error/22) + label en gras
- `adjustsFontSizeToFit` pour gérer les longueurs de label variables

### Segmented pill (settings, auth tabs)
- Container rond, padding 3-4px, border 1px line
- Inner segments rounds, le segment actif a `bg = cta`
- Utilisé pour : theme picker (auto/clair/sombre), login tabs (sign-in/register)

### Topo SVG background
- Animated wave pattern en SVG, opacité 6-7%
- Stroke `colors.textPrimary`
- Sur login + profile hero
- ~7-26 lignes selon la hauteur du composant

### Background location prompt modal
- Fired à l'app open via `BackgroundLocationPrompt`
- MapPinCheck icon (lucide)
- Texte expliquant pourquoi "Allow all the time" est utile pour le geofencing
- Bouton primaire "Activer", lien secondaire "Pas maintenant"
- Persistance de la décision (`junto.presence.bgAsked`)

### Notif preferences (dans settings drawer)
- Section expansible
- Liste de toggles par type de notification (`profil.notifType.{key}`)
- Granulaire — l'utilisateur peut désactiver chaque type indépendamment

---

## UX Principles

### Valeur immédiate
L'utilisateur voit des activités sur la carte sans créer de compte. Pas d'écran intermédiaire.

### Friction progressive
- Voir → aucune friction
- Rejoindre → créer un compte (email + password, vérification email)
- Créer → reste accessible avec un compte standard (pas de vérification téléphone — disabled depuis mig 00050)
- Tier Pro → validation manuelle Junto

### 3 niveaux d'information
Pin → Pop-up → Page complète. Dévoilement progressif selon l'intérêt.

### Auto > Manuel quand possible
Pour la validation de présence, l'utilisateur n'a généralement aucune action à effectuer si le geofencing fonctionne. Le manuel est un fallback, pas le path principal.

---

## Flows UX détaillés

### Onboarding visiteur
```
Ouverture app
    → Carte centrée
    → Bandeau "Activer localisation"
    → Activités visibles immédiatement
```

### Inscription
```
Login screen (topo SVG bg + tab pills sign-in/register)
    → Tab "Créer un compte"
    → Email + password + ToS checkbox + Créer
    → Email vérification envoyé (template Junto-branded)
    → Vérification → onboarding (date_of_birth + accept_tos)
    → Display name aléatoire
    → Background location prompt
    → Carte
```

### Reset password
```
Login screen
    → Tab "Mot de passe oublié"
    → Email + Envoyer
    → Email avec lien getjunto.app/auth/reset-password
    → Web bridge auto-redirige vers junto://reset-password
    → App ouvre l'écran reset-password (pinned, ne bouge pas même si recovery session active)
    → Nouveau password + confirme + Mettre à jour
    → Sign out + redirect login
```

### Rejoindre une activité
```
Carte
    → Tap pin (niveau 1)
    → Pop-up rapide (niveau 2)
    → "Voir l'activité"
    → Page événement (niveau 3)
        → Public → "Rejoindre" → access mur
        → Approval → "Demander à rejoindre"
            → Notif créateur (push)
            → Accepté → notif demandeur (push) → access mur
            → Refusé → notif demandeur (push)
```

### Créer une activité (4 étapes)
```
+ flottant carte
    → Étape 1 : Sport + titre + description + niveau + places (NULL = open)
        + distance/D+ si sport en a
    → Étape 2 : Pin start + pin meeting + (optionnel: end, objective)
        + (optionnel: import GPX → trace_geojson)
    → Étape 3 : Date + durée + visibility
    → Étape 4 : Récap → Publier
```

### Validation présence (jour J)
Voir `docs/DAY_OF_ACTIVITY.md`.

---

## Notifications visuelles

### OS notifications
- `presence_*` : un seul slot OS par activité (collapse_id `presence-{aid}`)
- `participant_joined` : collapse `joined-{aid}` — N joins → 1 visible avec buzz par join

### In-app feedback
- `Burnt.toast({ title, preset })` — preset `done`, `error`
- Haptic feedback sur actions importantes (`haptic.success()`, `haptic.medium()`)
- Toast non-bloquant — auto-dismiss

---

## Navigation

### Tabs (auth)
4 onglets en bas :
1. Carte (`carte`)
2. Mes activités (`mes-activites`)
3. Messagerie (`messagerie`)
4. Profil (`profil`)

Icône active en orange, inactive en text-secondary. Notif badge sur l'onglet messagerie + notifications.

### Stack screens (auth)
- `activity/[id]` — page événement
- `create/step1..4` — modal flow
- `edit/[id]` — édition (créateur)
- `peer-review/[id]` — peer review post-activité
- `conversation/[id]` — DM
- `profile/[id]` — profil public d'un autre user
- `invite/[token]` — entry point pour activités privées
- `admin/moderation` — admin only
- `legal/{terms, privacy, faq, licenses}`

### Stack screens (visitor)
- `index` — carte publique
- `login` — auth
- `reset-password` — recovery flow
- `onboarding` — date_of_birth + ToS
- `suspended` — landing pour comptes suspendus
- `activity/[id]` — page publique d'une activité
- `legal/{terms, privacy}`

---

## Settings drawer (depuis profil)

Ordre :
1. **Compte** — display name (avec icône crayon Pencil pour signaler edit), email (read-only), tier badge
2. **Préférences**
   - Toggle "Ma position" (background location)
   - Notifications dropdown (granulaire par type)
   - Theme segmented pill (auto / clair / sombre)
   - Map style — **retiré** du drawer (déjà accessible depuis l'écran carte)
3. **Alertes** (si tier ≥ premium)
4. **Modération** (si admin)
5. **Légal** (FAQ, CGU, privacy, licences)
6. Logout
7. Suppression de compte (link discret en bas)

---

## Patterns code-derived (à respecter)

- Toujours utiliser `radius.full` pour pills/CTA — pas de border-radius custom
- `KeyboardAvoidingView behavior` : `'padding'` sur iOS, `undefined` sur Android (le `softwareKeyboardLayoutMode: 'resize'` natif gère)
- ScrollView centering : utiliser un wrapper `<View flex:1 justifyContent:center>` plutôt que `justifyContent:'center'` sur le contentContainer (sinon le focused input se retrouve sous le clavier)
- Topo SVG bg : 7-26 paths Q-curve, stroke `colors.textPrimary`, opacity `0.06`
- Badges chips : 40px circulaires, count overlay en haut à droite, tier pill en dessous
- Metro cells : 2 lignes (emoji top + short label), `adjustsFontSizeToFit minimumFontScale={0.7}`

---

## V2 / backlog UI

- Vue liste (toggle map/list) — design only, pas implémenté (le code de toggle a été retiré en cleanup pass — c'était write-only state)
- Map clustering + "search this zone" button (différé à une session UI dédiée)
- Live position partagée pendant l'activité (V2)
- iOS-specific polish (Sign in with Apple, etc.) — différé jusqu'à user base
- In-app distance feedback ("tu es à 220m de la zone") sur l'écran d'activité
