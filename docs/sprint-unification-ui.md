# Sprint — Unification UI/UX

> Créé le 2026-09-19 après inventaire complet (3 audits parallèles, chiffres grep, pas
> d'impressions). Constat central : l'app contient QUATRE générations de design qui
> cohabitent, et la charte écrite (theme.ts, mai 2026) est contredite par les écrans
> les plus récents — que Scott préfère. Le chantier = choisir le canon, mettre les
> tokens à niveau, puis balayer écran par écran.

## Les 4 générations identifiées

- **Gen A « bordé utilitaire »** (la plus vieille) : create/step1-4, edit/[id],
  create-alert, couche actions de profile/[id]. `bold` partout, chips bordées→pleines,
  glyphes texte ✓/✕/+/−, zéro pressed.
- **Gen B « charte brutaliste »** (theme.ts mai 2026) : peer-review, favoris, contacts,
  gpx-traces. 1px borders, radius 4-8, micro-labels uppercase. Propre mais dépassée
  par la pratique.
- **Gen C « place-page / pilules teintées »** : pro-detail, offering-detail,
  activity-sheet, héros d'activity-detail, badge-display. Tint pills, shadows tokens,
  800/900 sur les titres.
- **Gen D « doux sans bordures »** (la plus récente, celle que Scott préfère) :
  channels-view, Espace pro, Agenda, availability-calendar, discovery (partiel).
  Cartes radius 14-18 sans bordure, boutons pilule, pressed scale — mais HORS tokens.

## Chiffres clés (recensement transversal)

309× fontWeight 800/bold vs 264× 700 (deux conventions rivales) · 82 styles de pilules
en 5 grammaires (3 codes « actif » différents) · 153 styles de boutons, 49 géométries,
5 rayons de CTA primaires · 195 rayons littéraux contournant une échelle de tokens 2×
trop petite · 22 recettes d'ombres ad hoc vs 3 tokens · 267 hex en dur (106 blancs de
texte → un token onCta) · emojis vibes définis à 3 endroits · **pressed feedback : ~4 %
des 606 Pressables**.

## Décision canon (À VALIDER PAR SCOTT)

**Proposition : le canon = Gen D pour la géométrie + discipline typographique C/B.**
1. Géométrie : cartes 14-16, sheets 24, pilules full, bordures remplacées par ombre
   douce OU espace (1px réservé aux inputs et séparateurs de listes).
2. Typo : **800 réservé aux titres et accents** (1 voix forte par surface) ; corps et
   méta en 500-600 ; plus jamais 'bold'/'900' en chaîne.
3. Pilules : UNE grammaire — teinte douce sans bordure (color+'1A'), actif = plein.
4. Boutons : 3 formes seulement — CTA pilule verte (texte onCta 700), lien discret
   (icône+texte 600 textSecondary), icône ronde 40. Fin des ghosts bordés+ombrés.
5. Pressed : wrapper Pressable maison avec opacité/scale par défaut, partout.
6. Ombres : tokens chauds only + un helper glow(cta) tokenisé pour les 2-3 CTA glorifiés.
7. Emojis UI : zéro (sauf décision contraire de Scott sur les vibes « Tinder-like »
   de discovery-compose — À TRANCHER explicitement).

Mise en œuvre du canon = **Phase 0** : mise à jour theme.ts/radius.ts/shadows.ts
(+ colors.onCta), création de <Chip>, <Button>, <PressableScale> partagés, réécriture
du header-charte de theme.ts.

## Bugs transverses (Phase 1 — à corriger quoi qu'il arrive)

- **Contraste** : texte `textPrimary` sur fonds cta/success/error → onCta blanc :
  profile/[id]:372/403/418/423 · pro/edit:849/861 · pro-detail:1484 · conversation:1465.
- **Thème sombre cassé** : fonds de chips `#FFFFFF` (discovery-view:541,598) ; poignée
  modale blanche-alpha invisible en clair (badge-display:1741).
- **Fossiles de l'orange banni `#F26B2E`** : profile-hero:40-41,173 (+ intro-carousel) —
  ignore l'accent-picker ; router via reliabilityColor + tokens.
- **Cimetières de styles morts** : activity-detail (~15 styles), badge-display (~10).
- **Glyphes texte → lucide** (~8 spots faciles) ; `'bold'/'900'` → numériques (9 spots).
- Doublons sémantiques : #7EC8A3/#E5524E/#E8A33D/#4B7CB8 re-codent success/error/warning.

## Tableau des verdicts (consolidé)

| Écran | Verdict | Résumé |
|---|---|---|
| carte + drawer + cards | ✅ canon | (1 ombre #000 à tokeniser) |
| channels-view | ✅ canon (Gen D) | référence géométrie |
| partenaires, mes-activites, menu-sheet, sport-picker | ✅ | nits mineurs |
| peer-review, favorites, contacts, gpx-traces, discovery-zone, offering-detail, activity-sheet | ✅/nits | Gen B/C propres |
| messagerie | 🟡 | palette type-pills en dur, 📍 emoji, radii 15/16, boutons carrés accept/decline hors famille |
| conversation/[id] | 🟡 | 8 radii, ✓/✕ texte, glow inline, 42 Pressables nus |
| filter-sheet | 🟡 | ✓ texte + '900', actif qui change la géométrie, sheet radius 8 |
| pro-detail | 🟡 | 800/900 partout, 3 grammaires de pilules, bouton contraste |
| espace/agenda/calendar | 🟡 | Gen D à re-baser sur les tokens Phase 0 |
| badge-display | 🟡→🔴 | système parallèle complet (17 radii, tokens ignorés) |
| discovery-view | 🔴 | 28×800, emojis, fonds blancs, 6 ombres inline |
| profile/[id] | 🔴 | héros moderne sur couche actions Gen A + bugs contraste |
| **create/step1-4 + edit/[id]** | 🔴 | Gen A pur — la 1re chose qu'un organisateur touche |
| create-alert | 🔴 | Gen A assumé (« brutalist outlined ») |
| settings-drawer | 🔴 | ✕/✓ texte, side-drawer unique, borderWidth 1.5, zéro ombre |

## Ordre de passe proposé (après Phase 0+1)

1. create/step1-4 + edit/[id] (le flux le plus vu des organisateurs, le plus daté)
2. profile/[id] (couche actions) — 3. activity-detail (3 générations + morts)
4. messagerie + conversation (retouches) — 5. filter-sheet + settings-drawer
6. discovery-view (aligner sur canon SANS refonte structurelle — la V2 reste au frigo)
7. pro-detail (les molettes : graisses, pilules) — 8. badge-display (re-basage tokens)
9. espace/agenda/calendar (re-basage tokens Phase 0)

Méthode : petits commits + OTA preview par écran, jamais de big-bang. Chaque écran :
tsc + lint + vérif visuelle Scott avant le suivant.
