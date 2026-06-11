# Junto — Backlog

> Réécrit le 2026-04-26, refresh 2026-04-28, refresh 2026-06-11 (260 migrations). Le plan Sprint 1-8 d'origine a guidé le démarrage mais l'app a depuis dépassé largement ce cadre. Ce document reflète l'état réel et ce qu'il reste à faire. L'historique sprint complet est récupérable via `git log`.

---

## Statut actuel

L'app est en **préparation Play Store**. La grande majorité des features V1 sont livrées : auth email/password (avec reset password via deep link, login redesigné), carte interactive + clustering + 5 styles de carte, création d'activité 4 étapes (avec GPX, objectif, pin priority, activités open sans cap), rejoindre/demander/accepter, mur d'événement + Realtime, messagerie privée + connection requests (avec auto-expiry 30j) + partage activité/trace, profil V4 avec reliability ring + per-sport endorsements, transport coordination (covoit + sièges + auto-expiry des demandes pending), gear declaration system, **présence V3** (geofencing background + foreground watcher + offline replay + QR + peer review threshold-based), **notif spine simplifié** (pre_warning T-2h / validate_now T0 / validate_warning T+duration/2 / peer_review_closing T+22h), reliability score Bayésien, reports & moderation, suspension, settings RGPD + suppression de compte, theme light/dark + segmented pill, tutorial, **badges progression V2** (joined/created/sport × t1-t5), reputation badges peer-voted, **Pro V1** (vitrine `pro_profiles` + catalogue `pro_offerings`, pin hexagone sur la carte, écrans détail + édition), web landing page (getjunto.app) avec auth callback + reset password bridges, pages légales, Sentry breadcrumbs sur le presence flow.

**Ajouts du sprint 2026-06-10/11** : audit complet (4 reviewers parallèles) + fixes — assetlinks package name corrigé (`app.getjunto`), i18n badges EN, **audit RLS** : découverte du no-op des sous-requêtes `users` dans les policies → prédicat `private.user_is_suspended` + sweep policies + filtres vues (migs 00255-00257, cf. SECURITY.md "sous-requêtes cross-table") ; **expo-image** adopté (cache disque, 8 composants) ; **saga clavier** résolue → hook `useKeyboardDockPadding` (reanimated IME inset), KAV banni des chat docks et bottom sheets ; **avis Pro complet** (Phase 4B, migs 00258-00260) — modèle Google Maps non gated, pro_reviews + offering_reviews, réponse du pro, stats héros PP + RA, notifications `review_received`/`review_reply`, reportable ; **pin system v2** — grammaire universelle outline → frame → plaque ivoire → glyphe (teardrop UA / carte RA / cercle photo PP, frame = statut sur UA, indigo sur la famille pro) ; Sentry 8 ; Mapbox token migré `RNMAPBOX_MAPS_DOWNLOAD_TOKEN` ; runtime 0.1.3.

**Ce qui reste avant launch public** : Stripe intégration (Premium/Pro), Discovery tab (Phase B-E), CGU finalisées, Play Store prep, custom SMTP pour le sender email.

---

## P0 — Bugs en cours

(aucun bloquant connu)

## P1 — Polish & easy wins

- [ ] **In-app distance feedback** sur l'écran activity-detail quand on est dans la fenêtre de validation (ex "tu es à 220m de la zone" avec dot vert à <150m). Ferme le mystère du fail silencieux à 160m du meetup point.
- [ ] **Auto-show QR du créateur** sur l'écran d'activité quand T-15min arrive — réduit la dépendance au reminder + manual tap.
- [ ] **Retirer `react-native-keyboard-controller`** de package.json au prochain build natif — installé pendant la saga clavier (2026-06-10), inerte sur device, gardé uniquement pour la compat OTA du runtime 0.1.3. Le retirer = bump version + build.

## P2 — UX clarifications & redesigns

- [ ] **Pins — teintes finales.** Le système v2 (grammaire frame) est validé ; restent deux teintes "proches mais pas parfaites" à fixer après feedback utilisateurs : l'indigo famille pro (`pinProBackground` #8B93F8 — "pas la bonne couleur mais good enough for now") et le beige frame UA (`pinFrame` #E0D2B4). Itération = 1 ligne + OTA.
- [ ] **expo-system-ui + sync thème OS** — `userInterfaceStyle` n'est pas appliqué sur Android (warning prebuild). Défer délibéré : le faire proprement = synchroniser l'apparence OS avec le store de thème in-app, sinon dialogs système dark sur app light. Cf. session 2026-06-10.

## P3 — Chantiers (plus de réflexion / d'impact)

### Doc debt
- [ ] **SECURITY.md — classification des fonctions Pro V1.** Les ~15 RPCs pro (mig 00240-00254 : pro_profiles, offerings, photos) n'ont jamais été ajoutées aux tables "Fonctions client-callable" / chaînes d'autorisation. Les entrées avis (00258-00260) sont à jour ; le rattrapage Pro V1 reste à faire.


## Reliability score — questions ouvertes

(Vide pour l'instant — peer review livré, no-show capturé, formule Bayésienne validée.)

---

## Avant launch public — non-polish

- [ ] **Stripe / paiements** — intégration via Edge Function + webhook idempotency (cf. SECURITY.md). Tier Premium (création illimitée, activités privées par lien, badge Vérifié). Tier Pro (vitrine + mise en avant + badge Pro). Actuellement tous les nouveaux users sont auto-Premium pour faciliter le test (migration 00051) — à inverser avant launch.
- [ ] **Discovery tab — Phase B-E** (cf. `docs/sprint-discovery.md`). Phase A figée, connection request system livré (migration 00072). Reste : RPCs `get_discovery_partners`, `update_discovery_settings`, écrans opt-in / settings / liste partenaires / inbox demandes, swap `BellPlus` → `Radar`.
- [ ] **API key restrictions** — Google Places + Mapbox (package signature), à faire avant tout test externe.
- [ ] **Keystore backup sécurisé**.
- [ ] **Android App Links** — le package name d'assetlinks.json est corrigé dans le repo (`com.junto.app` → `app.getjunto`, 2026-06-10) mais PAS encore déployé sur getjunto.app. Reste : (1) redéployer le site web, (2) vérifier que le fingerprint SHA256 correspond au keystore EAS (`eas credentials`), (3) ajouter le fingerprint du cert Play App Signing avant la release store. Tant que ce n'est pas fait, les liens `/activity/*` et `/invite/*` ouvrent le navigateur, pas l'app.
- [ ] **CGU + Politique de confidentialité finalisées** — textes hébergés sur `getjunto.app/legal/*` (web landing en place, FR + EN à compléter).
- [ ] **Custom SMTP pour le sender email** — actuellement "Supabase Auth" via shared SMTP. Setup Resend / Mailgun / etc. avec DNS records sur OVH pour avoir `Junto <noreply@getjunto.app>`. Décision attendue.
- [ ] **Sentry consent UI** — toggle dans settings + ToS update. Preview channel auto-consent OK pour dogfooding ; production attend cette UI.
- [ ] **Tests end-to-end** sur les flows critiques (création, join, presence validation, cancellation, suppression compte).
- [ ] **Préparation Play Store** : screenshots refresh, description, content rating questionnaire, déclaration âge 18+.

---

## V2+ — Backlog futur

### V2 — post-launch
- [ ] iOS (App Store) — codebase prête, déclencheur = user base meaningful
- [ ] Sign in with Apple (déclencheur = présence sur App Store)
- [ ] Filtres avancés sur la carte (multi-sport, niveau, distance, prix futur)
- [ ] Suggestions d'activités basées sur le profil
- [ ] Mode hors ligne (carte Mapbox offline)
- [ ] Analytics (Mixpanel ou équivalent)
- [ ] Liste d'attente automatique quand activité complète
- [ ] Vote d'annulation de groupe (2/3 pour annuler sans malus — voir ACTIVITY_MANAGEMENT.md)
- [ ] Élargissement aux activités non sportives (théâtre, cinéma, jeux)
- [ ] Tier Pro avancé — paiement intégré in-app avec commission Junto
- [ ] Vérification d'identité avancée
- [ ] API pour clubs et associations sportives
- [ ] Tableau de bord analytics pour les Pros
- [ ] Map clustering + "search this zone" button (différé à une session UI dédiée)
- [ ] Live position partagée pendant l'activité

### Présence — durcissements
- [ ] **Signed geo-proof token** pour offline replay (envelope HMAC, secret server-issued au join). Déclencheur = abuse observé empiriquement.
- [ ] **Mock-location detection** (Android `ALLOW_MOCK_LOCATION` flag).
- [ ] **GPS spoofing detection** générique.
- [ ] **Anti-collusion server-side** sur peer votes — pattern detection sur les votes croisés répétés.

### Sécurité durcissement
- [ ] Certificate pinning (protection MITM avancée)
- [ ] CAPTCHA à l'inscription (anti-bot à grande échelle)

### Discovery V2 (parked)
- [ ] Annonces / mur de petites annonces — à construire UNIQUEMENT si Ship 1 prouve que les users créent des activités à partir de leurs matches Discovery. Sinon abandonné.

---

## Décidé contre

- **Liste de contacts / système d'amis explicite** — Junto = logistique, pas relationnel (cohérent avec mémoires `no_social_scoring` + anti-dating-drift). Une "liste d'amis" formelle = glissement vers réseau social. Les gens avec qui on a déjà fait une activité apparaissent naturellement dans l'historique de messagerie — suffisant.
