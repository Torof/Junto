# Sports / Levels / Gear expansion — proposal (redline me)

Status: **DRAFT for Scott's review.** Nothing built yet. Edit freely — strike sports you don't want, add ones I missed, fix grades/gear. Once you sign off I build: one DB migration (sports + gear_catalog), `sport-levels.ts` (granular scales), `sport-icons.ts` (emojis), i18n (FR+EN names).

Decisions taken: broad expansion · climbing → couenne/grande voie/bloc (outdoor only) · every grade individual.

---

## 1. Backward-compat — TWO open decisions for you

**A. Generic `climbing` and `mountain-biking` already have activities.** When we split them, what happens to existing ones?
- **Recommended:** the migration re-points existing `climbing` activities+offerings → `climbing-sport` (Couenne) and `mountain-biking` → `mtb-xc`, then removes the generic keys. Clean picker, no orphans.
- *Alt:* keep the generic key alongside the splits (cluttered picker). → **your call: REPOINT & REMOVE, or KEEP BOTH?**

**B. Indoor:** you said outdoor only — so no "escalade en salle". Confirm we also skip indoor bouldering.

---

## 2. Sports — additions & splits

`✚` = new · `↔` = split from existing · key in `code`, category, FR name.

### Climbing / vertical (mountain)
| key | FR | note |
|---|---|---|
| `climbing-sport` ↔ | Escalade couenne | sport, 1 longueur — French grades |
| `climbing-multipitch` ✚ | Grande voie | multi-longueurs — French grades |
| `bouldering` ✚ | Bloc | Font scale |
| `mountaineering` (exists) | Alpinisme | alpine grades |
| `ice-climbing` (exists) | Cascade de glace | WI scale |
| `dry-tooling` ✚ | Dry-tooling | M scale |
| `via-ferrata` (exists) | Via ferrata | F→ED |
| `caving` ✚ | Spéléo | (no public grade — descriptive) |

### Foot (mountain / outdoor)
| key | FR | note |
|---|---|---|
| `hiking` (exists) | Randonnée | distance/D+ |
| `trail-running` (exists) | Trail | distance/D+ |
| `running` (exists) | Course à pied | distance |
| `nordic-walking` ✚ | Marche nordique | distance/D+ |
| `snowshoeing` ✚ | Raquettes | distance/D+ |

### Snow (mountain)
| key | FR | note |
|---|---|---|
| `ski-touring` (exists) | Ski de randonnée | ski grade |
| `ski-freeride` ✚ | Ski freeride / hors-piste | ski grade |
| `skiing` (exists) | Ski alpin | piste colors |
| `snowboarding` (exists) | Snowboard | piste colors |
| `splitboard` ✚ | Splitboard | ski grade |
| `cross-country-ski` (exists) | Ski de fond | — |

### Bike
| key | FR | note |
|---|---|---|
| `mtb-xc` ↔ | VTT cross-country | trail colors |
| `mtb-enduro` ✚ | VTT enduro | trail colors |
| `mtb-downhill` ✚ | VTT descente (DH) | trail colors |
| `cycling` (exists) | Vélo de route | distance/D+ |
| `gravel` ✚ | Gravel | distance/D+ |

### Air
| key | FR | note |
|---|---|---|
| `paragliding` (exists) | Parapente | brevet levels |
| `speed-riding` ✚ | Speed-riding | brevet levels |
| `hang-gliding` ✚ | Deltaplane | brevet levels |
| `skydiving` (exists) | Parachutisme | — |

### Water
| key | FR | note |
|---|---|---|
| `canyoning` (exists) | Canyon | v-scale |
| `kayaking` (exists) | Kayak | whitewater class I–VI |
| `rafting` (exists) | Rafting | class I–VI |
| `stand-up-paddle` (exists) | Stand-up paddle | — |
| `freediving` ✚ | Apnée | depth bands |
| `diving` (exists) | Plongée | brevet (N1–N4 / PADI) |
| `swimming` (exists) | Natation | — |
| `surfing` (exists) | Surf | — |
| `sailing` (exists) | Voile | — |
| `rock-fishing` (exists) | Pêche en mer | — |

### Other outdoor
| key | FR | note |
|---|---|---|
| `slacklining` (exists) | Slackline | — |
| `highlining` ✚ | Highline | — |
| `horseback-riding` (exists) | Équitation | — |

**Left as-is (non-outdoor, exist):** badminton, football, tennis, volleyball, crossfit, skateboarding, triathlon.
**Coastal — include? (less Hautes-Alpes):** `kitesurf`, `windsurf`, `wakeboard`. → your call.

That's **~16 new** + 2 re-pointed splits.

---

## 3. Level scales (granular — `sport-levels.ts`)

Each starts with **Tous niveaux**. Range picker spans two grades.

- **Couenne / Grande voie (French):** 4, 5a, 5b, 5c, 6a, 6a+, 6b, 6b+, 6c, 6c+, 7a, 7a+, 7b, 7b+, 7c, 7c+, 8a, 8a+, 8b, 8b+, 8c, 9a *(trim the top if you want)*
- **Bloc (Font):** 3, 4, 5, 5+, 6a, 6a+, 6b, 6b+, 6c, 6c+, 7a, 7a+, 7b, 7b+, 7c, 8a
- **Alpinisme:** F, PD-, PD, PD+, AD-, AD, AD+, D-, D, D+, TD-, TD, TD+, ED1, ED2, ED3, ED4
- **Cascade de glace (WI):** WI2, WI3, WI4, WI5, WI6, WI7
- **Dry-tooling (M):** M4, M5, M6, M7, M8, M9, M10
- **Via ferrata:** F, PD, AD, D, TD, ED
- **Canyon (v):** v1, v2, v3, v4, v5, v6, v7
- **Kayak / Rafting (whitewater):** Classe I, II, III, IV, V, VI
- **Ski rando / freeride / splitboard (ski grade):** S1, S2, S3, S4, S5  *(or toponeige 1.1–5.x — your pref)*
- **VTT (XC/enduro/DH), Ski alpin, Snowboard:** Vert, Bleu, Rouge, Noir
- **Parapente / speed-riding / deltaplane:** Découverte, Brevet en cours, Pilote autonome, Confirmé
- **Plongée:** N1, N2, N3, N4 / Guide
- **Apnée:** Découverte, <10 m, 10–20 m, 20–30 m, 30 m+
- **Distance/D+ sports** (rando, trail, course, marche nordique, raquettes, vélo, gravel): no grade chips — they already show km · D+.

---

## 4. Gear plan (`gear_catalog`)

### Fix existing gaps
- **Plongée** (only "Combinaison néoprène" today): + Bloc/bouteille, Détendeur, Gilet stabilisateur, Masque, Palmes, Ordinateur de plongée, Lampe.
- **VTT (all 3 disciplines):** Casque, Gants, Chambre à air, Kit de réparation, Pompe, Eau/Gourde; +enduro/DH: Protections (genoux/coudes), Casque intégral, Lunettes.
- **Vélo route / gravel:** Casque, Chambre à air, Kit réparation, Pompe, Eau, (gravel) sacoches.
- **Ski alpin / snowboard:** (mostly BYO) — Casque, DVA/Pelle/Sonde only if freeride.
- **Cross-country-ski:** Skis de fond, Bâtons, Fartage, Eau.

### Gear for new sports (reuse existing items where possible — they're tagged by `sport_keys` array)
- **Couenne:** = current climbing set (corde 60/70, dégaines, baudrier, casque, assureur, mousquetons, sangles, chaussons, magnésie).
- **Grande voie:** couenne set + Coinceurs/Friends, Anneaux de corde, Topo, Vivres/eau, Frontale.
- **Bloc:** Crashpad, Chaussons, Magnésie, Brosse.
- **Dry-tooling:** Piolets dry, Crampons, Corde, Dégaines, Baudrier, Casque, Gants.
- **Spéléo:** Casque + éclairage, Combinaison, Baudrier spéléo, Descendeur/croll, Corde, Kit, Couverture survie.
- **Raquettes:** Raquettes, Bâtons, Guêtres, DVA/Pelle/Sonde (si hors-piste), Frontale, Eau.
- **Ski freeride / splitboard:** DVA, Pelle, Sonde, Airbag, Casque, Peaux (splitboard), Couteaux.
- **Speed-riding / deltaplane:** Voile/aile, Sellette/harnais, Casque, Secours, Radio, Vario.
- **Apnée:** Combinaison, Masque, Palmes, Plomb, Bouée, Ordinateur.
- **Highline:** Sangle highline, Backup, Ancrages/sangles d'ancrage, Baudrier, Longe, Connecteurs.
- **Gravel:** = vélo route + sacoches.

---

## 5. Build order once approved
1. Migration: insert new sports (display_order, category, icon key) + re-point/remove generic climbing & MTB (pending decision A) + insert gear_catalog rows (+ fix gaps) + grants unchanged.
2. `sport-icons.ts`: emoji per new key.
3. `sport-levels.ts`: granular scales above.
4. i18n: `sports.<key>` + any new `gear.<name_key>` (FR + EN).
5. Regenerate types if needed, typecheck, smoke-test catalog via PostgREST, OTA.
