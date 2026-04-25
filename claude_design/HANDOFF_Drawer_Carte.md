# Handoff — Drawer replié (écran Carte)

Modification ciblée du **drawer replié** (barre persistante en bas de la carte, au-dessus de la bottom nav). Les autres éléments de l'écran carte (pins, compass, FAB, etc.) ne sont pas concernés par ce handoff.

Référence visuelle : `ProfilCarte/map-v3.jsx` — partie commentée `DRAWER REMANIÉ`.

---

## 1. Avant / Après

**Avant (état actuel)** — label `7 résultats` petit en bas à gauche, pas de CTA explicite, grip fin et peu visible.

**Après** — titre `7 résultats` en display 800/18px, grip large et visible, chip `Voir la liste →` à droite rendant l'action explicite.

---

## 2. Spécification complète

### 2.1 Conteneur du drawer

- `background: --bg` (même fond que l'écran, pas de panel)
- `border-radius: 20px 20px 0 0` (coins supérieurs arrondis uniquement)
- `border-top: 1px solid --line`
- `box-shadow: 0 -8px 24px -4px rgba(10,15,26,0.5)` (ombre portée **vers le haut**, pour décoller le drawer de la carte)
- `padding: 10px 18px 12px`
- `margin-top: -22px` (chevauche légèrement la carte pour que l'ombre s'imprime sur elle)
- `z-index: 16` (au-dessus de la carte, en dessous du FAB z-index 18)
- `flex-shrink: 0` (ne se compresse pas quand la carte réduit)

### 2.2 Grip (poignée de swipe)

Un seul élément, centré horizontalement :
- `width: 48px`
- `height: 4.5px`
- `border-radius: 3px`
- `background: --text-dim` (≈ `#8A95AB`)
- `opacity: 0.7`
- `margin: 0 auto 12px` (centré, espace de 12px sous lui)

> Cette épaisseur (4.5px) est volontairement plus marquée que la barre système typique — pour signaler clairement que le drawer est swipeable vers le haut.

### 2.3 Ligne titre + CTA

Container `display: flex`, `align-items: center`, `justify-content: space-between`.

**Titre (gauche)** :
- Famille : Archivo (classe `display`)
- `font-size: 18px`
- `font-weight: 800`
- `letter-spacing: -0.02em`
- `color: --text`
- Contenu : `${count} résultats` (au singulier si `count === 1` → `1 résultat`)

**CTA chip (droite)** :
- `display: flex`, `align-items: center`, `gap: 6`
- `background: --panel` (légèrement plus clair que le drawer, donne un relief)
- `padding: 7px 12px`
- `border-radius: 999` (pill)
- `border: 1px solid --line`
- `cursor: pointer` (ou ripple Android selon stack)

À l'intérieur du chip :
- Label : JetBrains Mono (classe `mono`), `font-size: 11px`, `color: --orange`, `font-weight: 700`, `text-transform: uppercase`, `letter-spacing: 0.1em`. Texte : `Voir la liste`
- Chevron : SVG 12×12, `stroke: #F26B2E`, `stroke-width: 2.5`, `stroke-linecap: round`, path = `polyline 18 15 12 9 6 15` (chevron pointant vers le haut — indique "expand vers le haut")

### 2.4 Interaction

- **Tap sur le chip** OU **tap sur le grip** OU **swipe up sur le drawer** → ouvre le drawer déplié (liste complète + onglets Filtres/Alertes). Comportement déjà présent dans l'app, on ne change que l'apparence du state replié.
- **Tap sur la zone titre** : même action (toute la barre est cliquable, pas seulement le chip).
- État drawer ouvert : inchangé par ce handoff — on ne touche qu'au **replié**.

### 2.5 Pluralisation française

```ts
const label = count === 0
  ? 'Aucun résultat'
  : count === 1
    ? '1 résultat'
    : `${count} résultats`;
```

Si `count === 0`, garder la même typo mais en couleur `--text-dim`, et masquer le chip `Voir la liste →` (rien à voir).

---

## 3. Design tokens utilisés

Déjà présents dans l'app, rien à ajouter :

```
--bg:       #0D1626
--panel:    #162238
--orange:   #F26B2E
--text:     #E8ECF3
--text-dim: #8A95AB
--line:     rgba(255,255,255,0.08)
```

---

## 4. Ce qu'on NE touche PAS

Pour éviter tout scope creep :
- Pins sur la carte → inchangés
- Boutons filtres/géoloc à droite → inchangés (séparés du drawer)
- FAB `+` → inchangé
- Compass top-right → inchangé
- Drawer **déplié** (contenu listing + tabs Filtres/Alertes) → inchangé
- Bottom nav → inchangée

Uniquement l'apparence de la **barre drawer en état replié**.

---

## 5. Référence pixel-perfect

Composant JSX complet : `ProfilCarte/map-v3.jsx`, bloc commenté `{/* DRAWER REMANIÉ — titre gros, grip visible, CTA explicite */}`.

En cas de divergence entre ce document et le JSX, le JSX fait foi pour les pixels, ce document fait foi pour la logique (pluralisation, états, interactions).
