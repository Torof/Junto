# Junto — Production Readiness (audit consolidé 2026-06-11)

> Synthèse fact-checkée des 5 audits parallèles (A: Play Store policy, B: RGPD/légal, C: sécurité round 3, D: fiabilité/perf, E: release engineering). Chaque item vérifié contre le code réel — les claims des auditeurs contredits par les faits sont corrigés ici. Ce document est la checklist de travail jusqu'à la release production ; cocher au fur et à mesure.

## Verdict global

- **Sécurité (C)** : ✅ solide — aucun finding critique/high. Les 3 cycles d'audit ont porté. ACLs des anciennes RPCs vérifiées live (42501 pour anon).
- **Play policy (A)** : 🔴 1 blocker code (page web de suppression de compte) + paperasse Play Console.
- **RGPD (B)** : 🔴 3 blockers (purge storage à la suppression, mentions légales, SOP violation de données).
- **Perf (D)** : 🟠 3 findings réels qui feront mal dès les premiers utilisateurs (index, invalidation storm, polling).
- **Release eng (E)** : 🔴 1 blocker (clé service account Play) + séquence de pré-vol documentée.

---

## 🔴 BLOCKERS

### B1. ✅ FAIT (2026-06-11) — Page web de demande de suppression de compte — Play policy
La suppression in-app existe (Edge Function `delete-account` ✅) mais Play exige AUSSI une URL web de demande de suppression, liée depuis la fiche store. Aucune route sur getjunto.app.
**Fix livré :** route `/legal/account-deletion` (in-app path + demande par email, inventaire supprimé/anonymisé/conservé) + lien footer. Reste : la lier dans Play Console à la soumission. Route originale proposée : `web/app/account-deletion/page.tsx` — formulaire email sans login, délai de traitement annoncé, lien privacy policy. Lier dans Play Console à la soumission.

### B2. ✅ FAIT (2026-06-11) — La suppression de compte ne purge PAS le storage — RGPD Art. 17
Vérifié : ni `delete_own_account` (mig 00042) ni l'Edge Function ne touchent `storage.objects`. Les avatars (`avatars/{user_id}/…`) et les photos pro (`pro-photos/{user_id}/…`) survivent à la suppression du compte.
**Fix livré et déployé :** l'Edge Function purge les deux buckets (walk récursif des dossiers user) avant le delete auth, best-effort. Privacy policy mise à jour. Détail original : dans l'Edge Function delete-account (déjà service_role), lister + supprimer les objets des deux buckets préfixés par user_id AVANT le delete auth. + mention dans la privacy policy.

### B3. 🟡 SCAFFOLDÉ (2026-06-11) — Mentions légales manquantes — droit français
getjunto.app n'a que /legal/privacy et /legal/terms. Les mentions légales (éditeur, contact, hébergeurs, directeur de publication, SIRET le cas échéant) sont obligatoires pour un site exploité en France.
**Fix livré :** page `/legal/mentions` + footer, avec [PLACEHOLDERS]. ⚠️ Reste à Scott : remplir les infos entité : forme juridique/nom, adresse, SIRET éventuel, email de contact.

### B4. 🟡 CÔTÉ REPO FAIT (2026-06-11) — eas.json — serviceAccountKeyPath pointe sur le mauvais fichier
`submit.production.android.serviceAccountKeyPath: './google-services.json'` = config client FCM, pas une clé de compte de service Play Developer API. `eas submit` échouera.
**Fix repo livré :** eas.json pointe sur ./play-service-account.json (gitignoré). ⚠️ Reste à Scott : créer le service account (Google Cloud Console → IAM, lier dans Play Console → API access), télécharger la clé JSON → `./play-service-account.json` (gitignoré, pattern à ajouter), corriger eas.json. ⚠️ Action console Scott.

### B5. Auto-premium (mig 00051) — à inverser au launch
`handle_new_user` donne `tier='premium'` à tout signup (mode test). À inverser AVANT le premier utilisateur public, pas avant (les testeurs actuels en profitent).
**Fix :** mig `revert_auto_premium` prête à appliquer le jour J (tier → 'free').

### B6. ✅ FAIT (2026-06-11) — Sentry production = totalement désactivé
`autoConsent = channel === 'preview'` → en production Sentry ne s'initialise jamais : zéro visibilité crash au launch, et la consent UI (RGPD) n'existe pas.
**Fix livré :** toggle « Partager les rapports de plantage » dans Settings (default OFF, init live au grant, Sentry.close() au retrait, persistance AsyncStorage) ; preview garde l'auto-consent. Détail original : toggle consentement dans Settings (default OFF, RGPD Art. 7), persisté (`sentry_consent` local + re-init au boot), texte dans la privacy policy. Item BACKLOG existant, maintenant bloquant.

### B7. 🟡 SOP RÉDIGÉE (2026-06-11) — SOP violation de données — RGPD Art. 33/34
Aucune procédure documentée (notification CNIL 72h, canal de contact, accès aux logs).
**Fix livré :** docs/INCIDENT_RESPONSE.md (détection → containment → CNIL 72h → users → post-mortem). ⚠️ Reste à Scott : vérifier rétention logs Supabase au dashboard. Détail original : `docs/INCIDENT_RESPONSE.md` (détection → notification CNIL 72h → notification users → forensics) + alias email dédié + vérifier la rétention des logs Supabase (dashboard).

---

## 🟠 REQUIRED — avant soumission

### Perf (audit D — les 3 qui feront mal au mois 1, vérifiés)
- [x] **Index participations** (mig 00261, appliquée) : AUCUN index côté activity (le UNIQUE est user-leading). Le `participant_count` de `activities_with_coords` est une sous-requête corrélée par ligne → scan complet par activité affichée. Mig : `(activity_id, status)` + `(activity_id, user_id)`. 15 min, gain majeur.
- [x] **Invalidation realtime trop large** (scopée nearby + throttle 2s) : `invalidateQueries({queryKey:['activities']})` sur chaque event postgres_changes → tempête de refetch multi-clients. Scoper aux clés `['activities','nearby']` et compagnie.
- [x] **Polling redondant avec le realtime** (DM/wall → fallback 60s) : DM 10s (`conversation/[id].tsx`), wall 15s, alors que les subscriptions realtime couvrent déjà. Supprimer les refetchInterval (garder un fallback long si on veut, 60s+).
- [x] Pagination (caps) : reviews 100, messages/wall latest-200 ; cursor pagination plus tard si besoin. Détail original : reviews (aucune limite), wall (aucune limite), conversations — `.limit()` + cursor là où les listes peuvent grossir.
- [x] Error boundary racine (reset + report Sentry). Détail original : zéro dans l'app — en ajouter autour des écrans à risque (detail, conversation, map).
- [ ] Requêtes géo : les filtres lng/lat sur la vue ne profitent pas du GIST. Acceptable au launch (échelle 05), à optimiser avec une RPC `ST_MakeEnvelope` quand le volume montera.

### Play Console (paperasse — Scott, avec les inventaires fournis par l'audit A)
- [ ] Data Safety form (inventaire complet des données dans le rapport A : location précise, photos, messages, email, DOB, user id — fournisseurs : Supabase EU, Mapbox, Google, Expo/FCM, Sentry DE)
- [ ] Déclaration ACCESS_BACKGROUND_LOCATION + **vidéo démo** (30-60s : disclosure in-app → prompt → géofence auto-validation)
- [ ] Content rating questionnaire + déclaration 18+
- [ ] Compte de test pour l'équipe review (pré-onboardé) + instructions presence flow
- [ ] Vérifier la déclaration FGS `location` dans le manifest du premier build prod (expo-location la pose normalement — contrôler l'APK/AAB)

### Privacy policy — compléments ✅ FAITS sur le web (2026-06-11) — ⚠️ découverte : les pages légales IN-APP sont des copies indépendantes déjà en dérive (contact support@junto.app vs contact@getjunto.app) → décision à prendre : synchroniser les copies ou faire pointer l'app vers getjunto.app/legal (textes existent et sont substantiels, contrairement au claim de l'audit E)
- [ ] Rétention Sentry + mention suppression
- [ ] Fenêtre géofencing background explicite (T-15min → fin+3h, arrêt auto, app fermée)
- [ ] Messages wall anonymisés survivent à la suppression ; reports conservés (modération)
- [ ] Sous-traitants US (Mapbox, Google, Expo, Vercel) + SCCs/DPF — vérifier les DPAs signés
- [ ] Note "pas de cookies de suivi" (vérifié : aucun analytics)

### Release engineering
- [ ] `EXPO_PUBLIC_GOOGLE_PLACES_API_KEY` est **vide** (.env) et absent des env EAS — générer + restreindre (package + SHA1) + env EAS production. ⚠️ Vérifier si la recherche de lieux marche actuellement !
- [ ] Keystore backup : `eas credentials` → download → chiffrer → stockage hors repo (procédure à documenter)
- [x] `versionCode` supprimé d'app.config. Détail original : `versionCode: 4` dans app.config : ignoré avec appVersionSource remote — supprimer la ligne (warning de build)
- [x] `.env` renommé. Détail original : renommer `.env` `AUTH_TOKEN_SENTRY` → `SENTRY_AUTH_TOKEN` (cosmétique local ; l'EAS secret est déjà bien nommé)
- [ ] Feature graphic 1024×500 (manquant ; screenshots ✅, listing draft ✅ docs/play-store-listing.md)
- [ ] App Links : APRÈS le premier build Play, ajouter le fingerprint **Play App Signing** (Play Console → App integrity) à assetlinks.json (garder celui d'EAS pour les builds preview)
- [ ] `NEXT_PUBLIC_APK_DOWNLOAD_URL` (Vercel) → URL Play Store après publication
- [ ] SMTP custom (Resend/Mailgun + DNS OVH) — décision en attente ; bloquant pour la délivrabilité des emails auth à l'échelle
- [ ] Plan Supabase : vérifier backups/PITR + rétention logs au dashboard (Pro recommandé avant production)

---

## 🟢 RECOMMENDED (non bloquant)

- Retry/backoff sur les RPCs idempotentes (join, confirm presence) — réseau rural
- staleTime global 5min → 60s ; gcTime 5min
- File d'actions offline générique (join/message) — la presence-offline-cache existe déjà comme modèle
- `push_send_audit` table pour la visibilité de délivrance push
- Bump MAX_EVENTS_PER_SESSION Sentry (50 → ~150) quand la consent UI sera là
- Stress test advisory locks (création en masse)
- DOB complète vs année de naissance — décision data-minimization à logger dans DECISIONS.md
- DPO : non requis à cette échelle (à réévaluer si "suivi systématique à grande échelle")

## Claims d'auditeurs corrigés (fact-check)

- ❌ E : "legal pages text not finalized" → les textes FR existent et sont réels (168 + 116 lignes, datés avril 2026). Le travail restant = compléments ci-dessus, pas une création.
- ❌ D : "expo-image default = memory cache unbounded" → le défaut d'expo-image est memory-disk. Non-actionnable.
- ❌ E : "reset versionCode to 1" → avec appVersionSource remote, le versionCode local est ignoré ; il faut le SUPPRIMER, pas le réinitialiser.
- ⚠️ C : "REVOKE from public fait partout" → vrai pour la surface ancienne (vérifié live), mais 00258 a prouvé que les NOUVELLES fonctions repartent avec le grant PUBLIC par défaut — réflexe à garder (checklist CLAUDE.md #10 à étendre : REVOKE from public ET anon).

## Séquence de pré-vol (résumé ordonné, détail dans le rapport E)

1. Fixes code (B1, B2, B3*, B6, B7 + perf pack) — *B3 attend les infos entité de Scott
2. Console Scott : service account Play (B4), Places API key, keystore backup, plan Supabase, SMTP
3. Play Console : listing + data safety + déclaration background location + content rating + compte test + feature graphic
4. Mig revert auto-premium (B5) — jour J
5. Premier build production (`--profile production`) → vérifier manifest FGS → `eas submit`
6. Fingerprint Play App Signing → assetlinks.json → APK download URL → vidéo démo si demandée
7. Internal testing → staged rollout 5% → 100%
