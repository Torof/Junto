# Junto — Décisions Techniques

Log des décisions techniques non évidentes. Ce fichier capture le "pourquoi" derrière les choix architecturaux — ce qu'on ne peut pas déduire du code seul.

---

## 2026-04-09 — Expo Router plutôt que React Navigation

**Décision :** Utiliser Expo Router (file-based routing) au lieu de React Navigation directement.
**Pourquoi :** Élimine la configuration manuelle du deep linking et du typage des routes — deux tâches que React Navigation impose. Le routing file-based rend la structure de navigation visible dans l'arborescence des fichiers.
**Alternative considérée :** React Navigation avec configuration manuelle des types et du deep linking.

## 2026-04-09 — TanStack Query + Zustand plutôt que Zustand seul

**Décision :** TanStack Query pour le state serveur, Zustand uniquement pour l'UI state.
**Pourquoi :** L'app est majoritairement du state serveur (activités, messages, profils). Zustand seul impose de réinventer loading/error/cache/refetch pour chaque entité — boilerplate massif et source de bugs (données stales, race conditions). TanStack Query gère tout ça nativement.
**Alternative considérée :** Zustand pour tout le state.

## 2026-04-09 — Deux tables de messages (wall + private)

**Décision :** `wall_messages` et `private_messages` en tables séparées.
**Pourquoi :** Les règles RLS sont fondamentalement différentes (participant d'activité vs expéditeur/destinataire). Les canaux Realtime sont différents. La stratégie de suppression est différente (anonymiser vs CASCADE). Une seule table imposerait du RLS conditionnel complexe et fragile.
**Alternative considérée :** Table unique `messages` avec colonne `type`.

## 2026-04-09 — React Hook Form + Zod pour les formulaires

**Décision :** Utiliser RHF + Zod dès le départ.
**Pourquoi :** Le flow de création d'activité en 4 étapes avec validation à chaque step serait chaotique avec useState. Zod permet de définir des schémas de validation cohérents avec les contraintes DB.
**Alternative considérée :** Gestion manuelle avec useState.

## 2026-04-09 — i18n dès Sprint 1

**Décision :** Configurer react-native-i18next avec FR + EN dès le premier écran.
**Pourquoi :** Retrofitter l'i18n sur 30+ écrans coûte des semaines de travail mécanique. Le coût marginal par écran est de ~5 minutes.
**Alternative considérée :** Ajouter l'i18n au Sprint 8 (polish).

## 2026-04-09 — Sports comme table de référence

**Décision :** Table `sports` avec id, key, icon, category, display_order — pas de strings hardcodés.
**Pourquoi :** Les sports sont référencés dans les activités, les profils utilisateur, et les filtres. Des strings hardcodés imposeraient des listes dupliquées côté client et une mise à jour app pour chaque nouveau sport ajouté.
**Alternative considérée :** Enum ou string directement sur les activités.

## 2026-04-09 — day.js plutôt que Date natif

**Décision :** Utiliser day.js (2KB) pour toute manipulation de dates.
**Pourquoi :** App internationale avec événements cross-timezone. `Date` natif est peu fiable pour les conversions de fuseau horaire. day.js est immutable et propose un plugin timezone. Commencer avec Date natif et migrer plus tard = refactorer chaque opération de date dans l'app.
**Alternative considérée :** Date natif + Intl.DateTimeFormat.

## 2026-04-09 — Modèle user complet dès Sprint 1

**Décision :** Inclure tous les champs user connus dans la migration initiale (bio, sports, levels, tier, pro status, consent, admin, suspension, date_of_birth), même si l'UI vient plus tard.
**Pourquoi :** Évite 4+ ALTER TABLE migrations à travers les sprints pour des colonnes dont la forme est déjà connue. Exceptions : `stripe_customer_id` (Sprint 6) et `notification_preferences` (Sprint 4) dont la forme dépend de l'implémentation.
**Alternative considérée :** Ajouter les colonnes sprint par sprint.

## 2026-04-10 — Vue `public_profiles` pour protéger les colonnes privées

**Décision :** Créer une vue Postgres `public_profiles` qui expose uniquement les colonnes publiques de la table users. Toutes les queries publiques (anon, profil d'un autre utilisateur) passent par cette vue.
**Pourquoi :** RLS opère sur les lignes, pas les colonnes. Sans vue, un appel direct `SELECT email, phone FROM users` via l'anon key expose les données privées.
**Alternative considérée :** Compter sur le service layer pour sélectionner les bonnes colonnes — rejeté car le service layer est côté client, bypassable.

## 2026-04-10 — Trigger serveur pour la création du profil utilisateur

**Décision :** La ligne dans `public.users` est créée par un trigger Postgres sur `auth.users`, pas par un INSERT client.
**Pourquoi :** Si le client INSERT directement, il peut injecter `is_admin: true`, skip l'age check, ou définir n'importe quel default. Le trigger garantit que seul le serveur crée les lignes avec des valeurs sûres.
**Alternative considérée :** INSERT client avec contraintes DB — rejeté car le client contrôle les valeurs de tous les champs nullable.

## 2026-04-10 — Premier admin via SQL direct

**Décision :** Le premier utilisateur admin est créé manuellement via le SQL Editor du dashboard Supabase.
**Pourquoi :** Aucun mécanisme in-app ne peut promouvoir un utilisateur admin sans qu'un admin existe déjà. Évite un endpoint d'auto-promotion qui serait un vecteur d'attaque.
**Alternative considérée :** Endpoint de bootstrap avec secret — rejeté, trop risqué.

## 2026-04-10 — GPX parsé côté client, pas de bucket GPX

**Décision :** Les fichiers GPX sont parsés côté client. Seules les coordonnées extraites sont envoyées au serveur et stockées en géométrie PostGIS dans la table activities. Le fichier GPX brut n'est pas conservé.
**Pourquoi :** Stocker les fichiers GPX dans un bucket nécessiterait des storage policies cross-table complexes (GPX → activity → participations pour déterminer qui peut lire). En parsant côté client et en stockant les coordonnées, l'accès est contrôlé par le RLS standard de la table activities. Élimine aussi le risque de servir un fichier XML malveillant stocké.
**Alternative considérée :** Bucket GPX privé avec policies — rejeté pour la complexité et le risque de sécurité.

---

## 2026-04-11 — Pas d'historique d'activités visible sur le profil public

**Décision :** Le profil public affiche uniquement des stats agrégées (nombre d'activités complétées, sports pratiqués, membre depuis). L'historique détaillé des activités (lieux, dates, co-participants) reste privé dans l'onglet "Mes activités" de l'utilisateur.
**Pourquoi :** Exposer l'historique d'activités permet de tracer les habitudes de déplacement d'un utilisateur (lieux fréquentés, jours, horaires). Pour une app qui met en contact des inconnus en plein air, c'est un risque de sécurité personnelle. Les stats agrégées donnent les signaux de confiance (expérience, régularité) sans exposer les patterns de localisation. Le système de réputation/badges (Sprint 8) complètera ces signaux.
**Alternative considérée :** Historique avec précision réduite (sans lieux exacts) — rejeté car même les titres d'activités et dates peuvent révéler des patterns.
