# Junto — Backlog

> Réécrit le 2026-04-26, refresh 2026-04-28, refresh 2026-06-11 (260 migrations). Le plan Sprint 1-8 d'origine a guidé le démarrage mais l'app a depuis dépassé largement ce cadre. Ce document reflète l'état réel et ce qu'il reste à faire. L'historique sprint complet est récupérable via `git log`.

---

## Statut actuel

L'app est en **préparation Play Store**. La grande majorité des features V1 sont livrées : auth email/password (avec reset password via deep link, login redesigné), carte interactive + clustering + 5 styles de carte, création d'activité 4 étapes (avec GPX, objectif, pin priority, activités open sans cap), rejoindre/demander/accepter, mur d'événement + Realtime, messagerie privée + connection requests (avec auto-expiry 30j) + partage activité/trace, profil V4 avec reliability ring + per-sport endorsements, transport coordination (covoit + sièges + auto-expiry des demandes pending), gear declaration system, **présence V3** (geofencing background + foreground watcher + offline replay + QR + peer review threshold-based), **notif spine simplifié** (pre_warning T-2h / validate_now T0 / validate_warning T+duration/2 / peer_review_closing T+22h), reliability score Bayésien, reports & moderation, suspension, settings RGPD + suppression de compte, theme light/dark + segmented pill, tutorial, **badges progression V2** (joined/created/sport × t1-t5), reputation badges peer-voted, **Pro V1** (vitrine `pro_profiles` + catalogue `pro_offerings`, pin hexagone sur la carte, écrans détail + édition), web landing page (getjunto.app) avec auth callback + reset password bridges, pages légales, Sentry breadcrumbs sur le presence flow.

**Ajouts du sprint 2026-06-10/11** : audit complet (4 reviewers parallèles) + fixes — assetlinks package name corrigé (`app.getjunto`), i18n badges EN, **audit RLS** : découverte du no-op des sous-requêtes `users` dans les policies → prédicat `private.user_is_suspended` + sweep policies + filtres vues (migs 00255-00257, cf. SECURITY.md "sous-requêtes cross-table") ; **expo-image** adopté (cache disque, 8 composants) ; **saga clavier** résolue → hook `useKeyboardDockPadding` (reanimated IME inset), KAV banni des chat docks et bottom sheets ; **avis Pro complet** (Phase 4B, migs 00258-00260) — modèle Google Maps non gated, pro_reviews + offering_reviews, réponse du pro, stats héros PP + RA, notifications `review_received`/`review_reply`, reportable ; **pin system v2** — grammaire universelle outline → frame → plaque ivoire → glyphe (teardrop UA / carte RA / cercle photo PP, frame = statut sur UA, indigo sur la famille pro) ; Sentry 8 ; Mapbox token migré `RNMAPBOX_MAPS_DOWNLOAD_TOKEN` ; runtime 0.1.3.

**Ce qui reste avant launch public** : CGU finalisées (+ mentions légales entité), Play Store prep (cf. docs/PROD_READINESS.md), custom SMTP. Stripe et Discovery sont DESCOPÉS du launch (walk #1 + DECISIONS 2026-06-11) : lancement 100% gratuit via auto-premium, paiement plus tard.

---

## P0 — Bugs en cours

(aucun bloquant connu)

## P1 — Polish & easy wins

- [ ] **In-app distance feedback** sur l'écran activity-detail quand on est dans la fenêtre de validation (ex "tu es à 220m de la zone" avec dot vert à <150m). Ferme le mystère du fail silencieux à 160m du meetup point.
- [ ] **Auto-show QR du créateur** sur l'écran d'activité quand T-15min arrive — réduit la dépendance au reminder + manual tap.
- [ ] **Remplacer les copies légales in-app par des liens vers getjunto.app/legal** (walk #1, 2026-06-11) — 3 copies dérivent déjà (contact support@junto.app vs contact@getjunto.app) ; les écrans (visitor)/legal/* et (auth)/legal/privacy+terms deviennent des ouvertures navigateur ; faq/licenses restent natifs. Source unique = web.
- [ ] **Retirer `react-native-keyboard-controller`** de package.json au prochain build natif — installé pendant la saga clavier (2026-06-10), inerte sur device, gardé uniquement pour la compat OTA du runtime 0.1.3. Le retirer = bump version + build.

## P2 — UX clarifications & redesigns

- [ ] **Pin beige UA — teinte finale.** Le système v3 est CLOS (2026-06-11) : RA = teardrop identique à UA avec frame toujours bleu pro-badge #3b82f6 (= couleur du badge pro profil, idée Scott), PP = cercle bleu. Le canal sémantique unique = couleur du frame (beige à venir / vert en cours / ambre bientôt / bleu pro permanent). Reste UNIQUEMENT le beige `pinFrame` #E0D2B4 ("proche mais pas parfait") — à fixer après feedback testeurs. 1 ligne + OTA.
- [ ] **Session UX messagerie + demandes de covoit** (parqué 2026-05-05, migré du fichier memory au walk #1) — interface messagerie "pas engageante, pas claire" ; flow seat-request "raw, ugly and difficult" : affichage des demandes (deux côtés), affordances accept/decline/cancel, construction du seed message. Déclencheur : après le retour des testeurs (c'est LA surface qu'ils vont critiquer). Note : le bug "popup bloque l'écriture" du même jour est résolu (cause = rate limit 1/min, perdu au rework reply, réinstauré sain à 15/min — mig 00264).
- [ ] **expo-system-ui + sync thème OS** — `userInterfaceStyle` n'est pas appliqué sur Android (warning prebuild). Défer délibéré : le faire proprement = synchroniser l'apparence OS avec le store de thème in-app, sinon dialogs système dark sur app light. Cf. session 2026-06-10.

## P3 — Chantiers (plus de réflexion / d'impact)

### Doc debt
- [ ] **SECURITY.md — classification des fonctions Pro V1.** Les ~15 RPCs pro (mig 00240-00254 : pro_profiles, offerings, photos) n'ont jamais été ajoutées aux tables "Fonctions client-callable" / chaînes d'autorisation. Les entrées avis (00258-00260) sont à jour ; le rattrapage Pro V1 reste à faire.


## Reliability score — questions ouvertes

(Vide pour l'instant — peer review livré, no-show capturé, formule Bayésienne validée.)

---

## Avant launch public — non-polish

- [ ] **Paiements (POST-launch, déclencheur = décision d'activer Premium/Pro payants)** — probablement Play Billing, pas Stripe (politique Google biens numériques, cf. DECISIONS 2026-06-11). Achat unique user / abonnement mensuel+annuel pro. La mig revert auto-premium (tier→'free' pour les nouveaux) part AVEC ce chantier, pas avant. Webhook idempotency cf. SECURITY.md.
- [ ] **API key restrictions** — Google Places + Mapbox (package signature), à faire avant tout test externe.
- [ ] **Keystore backup sécurisé**.
- [ ] **Android App Links — cert Play App Signing.** Le gros est fait (2026-06-11) : package name corrigé, fingerprint EAS réel extrait de l'APK signé et vérifié en ligne sur getjunto.app (Vercel auto-déploie sur push, le README web est obsolète sur ce point). Reste UNIQUEMENT : ajouter le fingerprint du cert **Play App Signing** à assetlinks.json avant la release store (Play Console → App integrity), sinon les builds store ne vérifieront pas.
- [ ] **CGU + Politique de confidentialité finalisées** — textes hébergés sur `getjunto.app/legal/*` (web landing en place, FR + EN à compléter).
- [ ] **Custom SMTP pour le sender email** — actuellement "Supabase Auth" via shared SMTP. Setup Resend / Mailgun / etc. avec DNS records sur OVH pour avoir `Junto <noreply@getjunto.app>`. Décision attendue.
- [ ] **Checklist de test de release manuelle** (`docs/RELEASE_TESTING.md`) à dérouler avant chaque release — rescopé au walk #1 : la suite automatisée (Detox/Maestro) passe en post-launch.
- [ ] **Préparation Play Store** : screenshots refresh, description, content rating questionnaire, déclaration âge 18+.

---

## V2+ — Backlog futur

### V2 — post-launch
- [ ] **Itinéraire — création de trace pour l'organisation** (décidé 2026-06-11, cf. DECISIONS). Outil "Dessiner l'itinéraire" : tap des waypoints sur la carte → LineString → même stockage `trace_geojson` que l'import (réutilise Mapbox + utils geojson↔gpx existants). Tracé INDICATIF (style pointillé / label "indicatif", multi-waypoints pour approximer), pour ORGANISER une sortie — jamais un enregistrement de performance. **Ligne à ne pas franchir : PAS d'enregistrement GPS (Strava), PAS de routing snap-to-trail (Komoot).** Couple import + dessin dans une étape "Itinéraire → [Importer un GPX] · [Dessiner]" → règle aussi la découvrabilité de l'import (peu instinctif aujourd'hui). Forte demande utilisateurs. Pas un bloquant launch ; fast-follow.
- [ ] **Fixed spots (POIs permanents)** — migré du memory ; note walk #1 : candidat sérieux au slot "premier outil de croissance" (contenu carte indépendant du volume d'activités) maintenant que Discovery est conditionnel.
- [ ] **Gear presets / inventaire perso** + **gear requests (revival from scratch)** — migrés du memory.
- [ ] iOS (App Store) — codebase prête, déclencheur = user base meaningful
- [ ] Sign in with Apple (déclencheur = présence sur App Store)
- [ ] Filtres avancés sur la carte (multi-sport, niveau, distance, prix futur)
- [ ] Suggestions d'activités basées sur le profil
- [ ] Mode hors ligne (carte Mapbox offline)
- [ ] Métriques d'usage respectueuses de la vie privée (agrégées/self-hosted) — décision post-launch. Mixpanel & co TUÉS au walk #1 : contradiction frontale avec la privacy policy livrée (« pas de trackers »).
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
- [ ] CAPTCHA à l'inscription — déclencheur : abus de bots observé
- ~~Certificate pinning~~ — TUÉ au walk #1 : maintenance élevée (rotation de certs), menace négligeable pour ce profil, TLS + RLS est la vraie défense

### Discovery V2 (parked)
- [ ] Annonces / mur de petites annonces — à construire UNIQUEMENT si Ship 1 prouve que les users créent des activités à partir de leurs matches Discovery. Sinon abandonné.

---

## Décidé contre

- **Liste de contacts / système d'amis explicite** — Junto = logistique, pas relationnel (cohérent avec mémoires `no_social_scoring` + anti-dating-drift). Une "liste d'amis" formelle = glissement vers réseau social. Les gens avec qui on a déjà fait une activité apparaissent naturellement dans l'historique de messagerie — suffisant.
