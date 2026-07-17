# Junto — Kit de marque (pour Claude Design / visuels Play Store)

Ce dossier réunit tout le nécessaire pour composer des **images de fiche Play Store**
fidèles à l'identité Junto — sans reproduire un écran, mais en réutilisant les
**éléments** de l'app (pins, cartes d'activité, couleurs, ton).

## Ce qu'est Junto (en une phrase)
Une app pour **voir les sorties outdoor en cours autour de soi, où que l'on aille, et
les rejoindre** — entre passionnés ou encadré par un pro. Positionnement : *destination
d'abord* (« là où tu vas, là où tu veux »), **jamais** « près de chez toi ». Ton positif,
naturel, montagne, jamais négatif.

## Palette (thème clair = référence)
| Rôle | Hex |
|---|---|
| Fond (cream) | `#F5EEDF` |
| Surface / carte | `#EDE4D2` |
| Surface alt | `#E3D9C4` |
| Encre (texte principal) | `#1F1A15` |
| Texte secondaire | `#6F665A` |
| **Accent (CTA) — vert vif** | `#2FA46A` |
| Vert montagne (logo) | `#3F7A56` |
| Bordure brutaliste | `#1F1A15` |
| Étoile / note | `#FBBF24` |

### Couleurs par catégorie de sport (pour les pins & pastilles)
| Univers | Hex |
|---|---|
| Montagne | `#4A7C59` |
| Eau | `#2563EB` |
| Air | `#8B5CF6` |
| Vélo | `#64748B` |
| À pied | `#E11D48` |

## Typographie
Polices **système** (pas de font custom) : SF Pro (iOS) / Roboto (Android), sans-serif.
Titres en **800 / bold**, letter-spacing légèrement négatif (-0.5 à -1px). Corps régulier.
Petites étiquettes en capitales espacées.

## Style visuel
- **Brutaliste doux** : bordures 1–2px encre franches, coins arrondis modérés (14–24px),
  pas d'ombres lourdes (préférer un bord net). Thème clair par défaut, calme, naturel.
- **Cartes d'activité** : fond cream `#EDE4D2`/`#F5EEDF`, pastille sport (contour de la
  couleur de catégorie), titre encre gras, lignes d'info avec **icônes en trait vert**
  (calendrier, horloge, niveau, participants, lieu), CTA texte vert.
- **Fond de carte** : Mapbox Outdoors — terrain vert, courbes de niveau, villages.

## Les pins (élément signature)
- **Activité entre passionnés** : marqueur en **goutte** (teardrop), **teinté par la
  couleur de catégorie**, avec l'**emoji du sport** au centre, et une étiquette texte de
  la même couleur à côté (nom + date).
- **Page/offre pro** : **épingle à tête ronde blanche** sur aiguille fine (grammaire
  « place-pin » de Google), avec le glyphe du sport ou le logo du pro, liseré de catégorie.

### Emojis de sport (au centre des pins passionnés)
🥾 rando · 🧗 escalade · ⛷ ski de rando/ski · 🏃 trail/course · 🏔 alpinisme · 🚴 vélo ·
🛶 kayak · 🏄 surf/paddle · ⛵ voile · 🪂 parapente · 🏂 snowboard · 🏊 natation ·
🌊 canyoning · 🤿 plongée · 🚣 rafting/canoë

## Fichiers fournis dans ce dossier
- `junto_icon_square.png` — icône de l'app (marque).
- `junto_icon_fg.png` — marque seule (foreground, sur transparent).
- `ui-map.jpeg` — écran carte réel (pins + labels + terrain).
- `ui-activity.jpeg` — tiroir d'activité entre passionnés (carte + infos).
- `ui-pro-page.jpeg` — page pro (nom, note, actions, photos).
- `ui-profile.jpeg` — profil (fiabilité, sports, avis des pairs).

Ces captures servent de **référence d'éléments** (pins, cartes, couleurs, map) — pas de
modèles à copier tels quels.

## Ce qu'on veut produire
3 images composées « maison » (pas des screenshots) pour la fiche :
1. **Activité entre passionnés** — carte d'activité mise en valeur + pin, sur fond de marque.
2. **Activité pro** — offre pro (photo, prix, durée, note) + pin pro.
3. **Page pro** — page pro (nom, note ★, actions) + pin pro.
Format Play : portrait, ratio ≤ 2:1 (ex. 1080×1920). Accroche courte en haut, ton positif.
