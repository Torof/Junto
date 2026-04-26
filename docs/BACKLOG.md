# Junto — Backlog

> Réécrit le 2026-04-26. Le plan Sprint 1-8 d'origine a guidé le démarrage mais l'app a depuis dépassé largement ce cadre (~300 commits, 97 migrations, ~45 composants). Ce document reflète l'état réel et ce qu'il reste à faire. L'historique sprint complet est récupérable via `git log` si besoin.

---

## Statut actuel

L'app est en **préparation Play Store**. La grande majorité des features V1 sont livrées : auth Google + email, carte interactive + clustering + 5 styles de carte, création d'activité 4 étapes (avec GPX, objectif, pin priority), rejoindre/demander/accepter, mur d'événement + Realtime, messagerie privée + connection requests, profil V4 avec reliability ring + per-sport endorsements, transport coordination (covoit + sièges), gear declaration system, presence validation V2 (QR + GPS), notifications push, reliability score Bayésien, reports & moderation, suspension, settings RGPD + suppression de compte, theme light/dark, tutorial, badges reputation/trophées, web landing page, pages légales.

**Ce qui reste avant launch public** : items polish/bugs ci-dessous (P0/P1), Stripe intégration (Premium/Pro), Discovery tab (Phase B-E), vérification que le calcul reliability tourne bien post-activité (item 21).

---

## P0 — Bugs en cours

### Bloqués par le prochain `eas build`
- [ ] **Input messagerie caché par clavier sur Android** — bug edge-to-edge. Diff partiel pushé : `behavior="padding"` iOS / `"height"` Android. À compléter : `android.softwareKeyboardLayoutMode: 'resize'` dans `app.config.ts`.
- [ ] **Download direct GPX trace sur Android** — actuel : share sheet (Drive/Files/etc). Pour un vrai download "vers Téléchargements" sans intermédiaire : installer `expo-sharing` et utiliser `Sharing.shareAsync` qui sauvegarde directement. iOS reste sur Save to Files (limitation OS, pas l'app).

## P1 — Polish & easy wins

- [ ] **Ouvrir profil depuis l'INTÉRIEUR d'une conversation** — pour l'instant l'écran conversation a un header vide (`title: ''`), donc rien à taper. À faire : custom header avec avatar + nom du correspondant, tappable → profil. Côté liste des conversations, la nav avatar→profil est déjà en place.

## P2 — UX clarifications & redesigns


## P3 — Chantiers (plus de réflexion / d'impact)


## Reliability score — questions ouvertes

- [ ] **Vérifier le calcul du taux de fiabilité en fin d'activité** — vérifier que le score est recalculé et mis à jour dans le profil après une activité terminée (vérifier les fonctions Bayésiennes dans migrations 00064 et 00070). Redéfinir les pénalités si nécessaire :
  - **No-show** (inscrit, pas venu, pas annulé) : barème proposé **-15 pts** (sévère, casse la planif)
  - **Annulation tardive** (<12h avant) : **-5 pts** (gênant mais pardonnable)
  - **Non-validation présence** (venu mais pas validé) : **-2 pts** (admin oversight)
  - **Quand** : trigger à la transition `status` → `completed`, via SECURITY DEFINER function

- [ ] **Pénalité no-show + garde-fou créateur** — si validation présence obligatoire et personne non validée à la fin, pénalité auto. **Reco : 2 couches** :
  1. Créateur valide manuellement (premier recours, autorité légitime IRL)
  2. Cross-validation par 2+ autres participants confirmés (fallback si créateur passif)
  - **Risque** : favoritisme créateur. **Mitigation** : log de qui a validé qui, flag pour modération si pattern suspect (créateur valide systématiquement les mêmes 3 personnes).
  - **Écarté** : grace period 24h via proximité GPS post-activité — marche mal en pratique (les gens rentrent chez eux).

---

## Avant launch public — non-polish

- [ ] **Stripe / paiements** — intégration via Edge Function + webhook idempotency (cf. SECURITY.md). Tier Premium (création illimitée, activités privées par lien, badge Vérifié). Tier Pro (vitrine + mise en avant + badge Pro). Actuellement tous les nouveaux users sont auto-Premium pour faciliter le test (migration 00051) — à inverser avant launch.
- [ ] **Discovery tab — Phase B-E** (cf. `docs/sprint-discovery.md`). Phase A figée, connection request system livré (migration 00072). Reste : RPCs `get_discovery_partners`, `update_discovery_settings`, écrans opt-in / settings / liste partenaires / inbox demandes, swap `BellPlus` → `Radar`. À vérifier : où en est-on précisément.
- [ ] **API key restrictions** — Google Places + Mapbox (package signature), à faire avant tout test externe.
- [ ] **Keystore backup sécurisé**.
- [ ] **Android App Links** (deep links vérifiés par domaine, prévention phishing).
- [ ] **CGU + Politique de confidentialité finalisées** — textes hébergés sur l'URL publique du Play Store (web landing déjà en place).
- [ ] **Tests end-to-end** sur les flows critiques (création, join, presence validation, cancellation, suppression compte).
- [ ] **Préparation Play Store** : screenshots refresh, description, content rating questionnaire, déclaration âge 18+.

---

## V2+ — Backlog futur

### V2 — post-launch
- [ ] iOS (App Store)
- [ ] Filtres avancés sur la carte (multi-sport, niveau, distance, prix futur)
- [ ] Suggestions d'activités basées sur le profil
- [ ] Mode hors ligne (carte Mapbox offline)
- [ ] Sentry / error tracking
- [ ] Analytics (Mixpanel ou équivalent)
- [ ] Liste d'attente automatique quand activité complète
- [ ] Vote d'annulation de groupe (2/3 pour annuler sans malus — voir ACTIVITY_MANAGEMENT.md)
- [ ] Élargissement aux activités non sportives (théâtre, cinéma, jeux)
- [ ] Tier Pro avancé — paiement intégré in-app avec commission Junto
- [ ] Vérification d'identité avancée
- [ ] API pour clubs et associations sportives
- [ ] Tableau de bord analytics pour les Pros
- [ ] Certificate pinning (protection MITM avancée)
- [ ] GPS spoofing detection
- [ ] CAPTCHA à l'inscription (anti-bot à grande échelle)

### Discovery V2 (parked)
- [ ] Annonces / mur de petites annonces — à construire UNIQUEMENT si Ship 1 prouve que les users créent des activités à partir de leurs matches Discovery. Sinon abandonné.

---

## Décidé contre

- **Liste de contacts / système d'amis explicite** — Junto = logistique, pas relationnel (cohérent avec mémoires `no_social_scoring` + anti-dating-drift). Une "liste d'amis" formelle = glissement vers réseau social. Les gens avec qui on a déjà fait une activité apparaissent naturellement dans l'historique de messagerie — suffisant.
