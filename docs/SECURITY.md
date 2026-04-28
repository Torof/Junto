# Junto — Modèle de Sécurité

## Table des matières — navigation rapide

**Ne pas lire ce fichier en entier. Utiliser la table "When to Read Which Doc" dans CLAUDE.md pour savoir quelles sections lire.**

| Section | Contenu | Quand consulter |
|---------|---------|-----------------|
| Principes fondamentaux | 4 principes de sécurité | Première lecture uniquement |
| Clés et secrets | service_role, API keys, .gitignore, keystore | Setup projet |
| Row Level Security | Pattern migration, public_profiles view, trigger user creation | Création de table |
| Chaîne d'autorisation | Checks obligatoires par fonction | Création / modification de fonction |
| Exposition PostgREST | GRANT/REVOKE EXECUTE, fonctions internes vs client | Création de fonction |
| SECURITY DEFINER | Classification complète | Création de fonction |
| Tables sans INSERT client | Matrice opérations bloquées par table | Création de fonction qui écrit |
| Messages d'erreur | Règle des messages génériques | Création de fonction |
| PL/pgSQL injection | EXECUTE / paramètres bindés | Création de fonction avec SQL dynamique |
| Fonctions de création | Hardcoder les champs privilégiés | Création de fonction d'insertion |
| Colonnes privilégiées | Liste par table, triggers whitelist | Création de table, ajout de colonne |
| Matrice RLS complète | SELECT/INSERT/UPDATE/DELETE par table | Création de table, de policy |
| Système de présence | Géo / QR / peer-review / offline replay | Toute modification du flux présence |
| Système de badges | Progression tiers + badges réputation | Toute modification du système badges |
| Push notifications | Routing par type, collapse_id, trigger | Toute modification du système notifs |
| Storage | Buckets, policies, upload validation | Upload avatar, pro-docs |
| Auth & Sessions | Secure storage, session config, logout, email, âge | Auth flow |
| Profil visibilité | Matrice champs × rôles | Profils |
| Rate Limiting | Limites par opération avec SQL | Création de fonction avec rate limit |
| Protection des données | Stratégie de suppression par table | Ajout de FK, suppression compte |
| Modération | Suspension, blocked_users, reports | Block, modération |
| Intégrité des données | UNIQUE/CHECK, updated_at, concurrent join, triggers | Création de table, de fonction |
| Configuration Supabase | Checklist setup projet | Setup projet |
| Sanitisation texte | Strip HTML tags + control chars | Trigger de sanitisation |
| Anti-abus | Removal définitif, blocage, rate limiting, idempotency | Feature spécifique |
| Changement de tier | Downgrade Premium→Free, révocation Pro | Stripe / tier |
| Deep links | Custom scheme + universal links + reset password | Deep link config |
| Suppression de compte | Architecture Edge Function | Suppression compte |
| Bootstrap admin | Premier admin via SQL | Setup |

---

## Principes fondamentaux

### 1. Ne jamais faire confiance au client
La clé `anon` de Supabase est dans l'APK. N'importe qui peut l'extraire et appeler l'API directement. Toute règle métier, toute restriction d'accès, toute validation DOIT être appliquée côté serveur (RLS, contraintes DB, fonctions Postgres SECURITY DEFINER).

### 2. Valider et assainir tout input externe
Chaque donnée venant de l'utilisateur (texte, fichier, coordonnées) est potentiellement malveillante. Valider le format, la taille, le contenu avant traitement.

### 3. Exposer le minimum nécessaire
Chaque query sélectionne explicitement ses colonnes. Chaque API activée a une raison. Chaque donnée visible a été délibérément rendue publique.

### 4. Sécurité intégrée, pas ajoutée après
Les mesures de sécurité sont implémentées au moment de la création de chaque table, chaque service, chaque écran — jamais en retrofitting.

---

## Clés et secrets

### Règle absolue : pas de `service_role` dans le client
- **`anon` key** : dans l'app, protégée par RLS → OK
- **`service_role` key** : bypass TOUT le RLS → **JAMAIS dans le code client**
- Usage `service_role` : uniquement Edge Functions (`supabase/functions/`) + scripts admin côté serveur

### Push notification webhook
- Edge Function `send-push` reçoit un secret partagé via header `x-junto-push-secret`
- Le secret est stocké dans la table `app_config` (clé `push_webhook_secret`) côté DB et en variable d'env `PUSH_WEBHOOK_SECRET` côté Edge Function
- Sans ce header, l'Edge Function rejette `403 Forbidden`

### API Keys
- **Google Places** : restreinte par package Android + signature SHA-1
- **Mapbox** : scopée par nom de package
- **Sentry** : DSN public, OK dans le client (Sentry filtre côté serveur)

### .gitignore
Fichiers interdits de commit :
```
.env
.env.*
node_modules/
.expo/
dist/
*.jks
*.keystore
google-services.json
service-role-key*
```

### Keystore Android
- Le keystore signe l'app pour le Play Store
- **Si perdu = impossible de mettre à jour l'app**
- Sauvegardé dans un stockage sécurisé chiffré (pas dans git)
- Mot de passe stocké séparément du fichier
- Documenté dans DECISIONS.md

---

## Row Level Security (RLS)

### Règle
Chaque table a ses politiques RLS écrites au moment de sa création. Pas de table sans RLS.

### Pattern migration obligatoire
Chaque migration qui crée une table doit inclure immédiatement :
```sql
CREATE TABLE xxx (...);
ALTER TABLE xxx ENABLE ROW LEVEL SECURITY;
ALTER TABLE xxx FORCE ROW LEVEL SECURITY;
-- policies follow immediately
```
`FORCE` garantit que RLS s'applique même au table owner. Aucune donnée ne doit être insérée avant que RLS soit activé et les policies en place.

### Limitation RLS : colonnes
RLS opère sur les **lignes**, pas les colonnes. Pour la table `users` qui contient des champs privés (email, phone, date_of_birth), on ne peut pas empêcher un `SELECT email FROM users` via RLS seul.

**Solution : vue `public_profiles`**
```sql
CREATE VIEW public_profiles AS
SELECT id, display_name, avatar_url, bio, sports, levels_per_sport, created_at
FROM users
WHERE suspended_at IS NULL;
```
- Toutes les queries publiques passent par la vue
- L'accès direct à la table `users` est réservé à `auth.uid() = id` et aux fonctions admin

### Création du profil utilisateur — trigger serveur uniquement
La ligne dans `public.users` est créée par un trigger Postgres sur `auth.users`, jamais par un INSERT client.

- **Pas de policy INSERT sur `public.users` pour les clients**
- Le client ne peut pas injecter `is_admin: true`, skip age verification, ou définir des defaults malveillants
- Les champs comme `date_of_birth`, `accepted_tos_at` sont set via des fonctions dédiées après la création initiale
- Self-heal `ensure_user_row` rétablit la ligne si le trigger a échoué

---

## Chaîne d'autorisation complète par fonction

Chaque fonction Postgres doit vérifier TOUTES les conditions documentées. Une vérification manquante = une faille.

**Règle universelle :** Chaque RPC client commence par :
```sql
v_user_id := auth.uid();
IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
  RAISE EXCEPTION 'Operation not permitted';
END IF;
```
Sans le check de suspension, un utilisateur suspendu peut toujours créer des activités, envoyer des messages, et rejoindre des activités.

### Activités

**`create_activity`** (mig 00102 + 00144) :
- Auth + non suspendu
- `char_length(title) >= 3`
- `starts_at > NOW()`
- `max_participants` est NULL OU dans [2, 50]
- Advisory lock par user pour sérialiser les créations concurrentes
- Rate limit : 20 activités / 24h (skipé pour `is_admin = TRUE`)
- Hardcode `creator_id = auth.uid()`, `status = 'published'`, `created_at = NOW()`
- Set `junto.bypass_lock = true` avant INSERT (pour la trigger whitelist)
- Auto-INSERT participation creator → `accepted`
- Si visibility public/approval → `check_alerts_for_activity`

**`join_activity`** (mig 00102) :
- Auth + non suspendu
- `FOR UPDATE` sur la ligne activité
- Activity status IN (`published`, `in_progress`)
- `auth.uid() != creator_id`
- Pas bloqué par le créateur (`blocked_users`)
- Capacité : `current_count < COALESCE(max_participants, 50)` — soft-cap 50 pour activités open
- Rate limit : 10 join / heure
- Cas existant : status `removed` → rejet ; `accepted`/`pending` → rejet (déjà dedans) ; sinon réactivation
- Crée notif `participant_joined` ou `join_request` selon visibilité

**`accept_participation` / `refuse_participation` / `remove_participant`** :
- Auth + non suspendu
- `auth.uid() = activities.creator_id`
- Status activité IN (`published`, `in_progress`)
- Status participation = `pending` (pour accept/refuse) ou `accepted` (pour remove)
- Le participant ciblé n'est pas le créateur

**`leave_activity`** :
- Auth + non suspendu
- `FOR UPDATE` sur la participation (sérialise avec `remove_participant`)
- Status participation IN (`accepted`, `pending`)
- Status activité IN (`published`, `in_progress`)
- Si départ tardif (<12h avant start) : pénalité reliability ; si départ normal : pas de pénalité

**`cancel_activity`** :
- Auth + non suspendu
- `auth.uid() = creator_id`
- Status IN (`published`, `in_progress`)
- Notif tous les participants acceptés

### Présence

**`confirm_presence_via_geo(p_activity_id, p_lng, p_lat, p_captured_at DEFAULT NULL)`** (mig 00149) :
- Auth + non suspendu
- Si `p_captured_at` fourni (replay offline) : `now() <= starts_at + duration + 3h`
- Window anchor (live = `now()`, replay = `p_captured_at`) dans [starts_at - 15min, starts_at + 15min]
- User est participant accepté avec `confirmed_present IS NULL`
- Distance ≤ 150m vers start OR meeting OR end OR `trace_geojson` (LineString)
- Flip `confirmed_present = TRUE` (single-shot)
- `recalculate_reliability_score`
- `notify_presence_confirmed`

**`confirm_presence_via_token(p_token)`** (mig 00147) :
- Auth + non suspendu
- Token existe et `expires_at > now()`
- `now()` dans [starts_at - 15min, starts_at + duration + 3h]
- User est participant accepté avec `confirmed_present IS NULL`
- Flip `confirmed_present = TRUE`
- Si scanner != créateur → flip aussi le créateur (auto-validation par scan participant)

**`create_presence_token(p_activity_id)`** (mig 00147) :
- Auth + non suspendu
- `auth.uid() = creator_id`
- `now()` dans [starts_at - 15min, starts_at + duration + 3h]
- Réutilise le token existant non-expiré OU en génère un nouveau (12 char)

**`peer_validate_presence(p_voted_id, p_activity_id)`** (mig 00140) :
- Auth + non suspendu
- `auth.uid() != p_voted_id`
- Activity completed + requires_presence = TRUE
- `now()` dans [end + 15min, end + 24h] — sinon erreur différenciée (`peer_review_window_not_open` / `peer_review_window_closed`)
- Target est participant accepté avec `confirmed_present IS NULL` (sinon `peer_already_validated`)
- **Si 2 participants acceptés ET voter = créateur** : direct flip (pas de seuil, pas de check self-presence)
- **Sinon (3+ participants)** : voter doit être `confirmed_present = TRUE` (sinon `peer_voter_not_present`) ; INSERT vote ; flip si `vote_count >= 2`

**`give_reputation_badge(p_voted_id, p_activity_id, p_badge_key)`** (mig 00134) :
- Auth + non suspendu
- `auth.uid() != p_voted_id`
- `p_badge_key` dans la liste autorisée (8 valeurs)
- Activity completed
- `now()` dans [end + 15min, end + 24h]
- Voter ET voted sont participants acceptés
- INSERT dans `reputation_votes` (UNIQUE constraint empêche le double-vote)

### Conversations & messagerie

**`create_or_get_conversation(p_other_user_id, p_source TEXT, p_message TEXT DEFAULT NULL)`** :
- Auth + non suspendu
- Other user existe et non suspendu
- Blocage bidirectionnel (ni A→B ni B→A)
- Rate limit : 10 demandes pending par sender (rolling)
- Si conversation `active` existe : retourne l'existante ; sinon `pending_request` créée avec `request_expires_at = NOW() + 30 days`

**`accept_contact_request` / `decline_contact_request`** :
- Auth + non suspendu
- User est destinataire (pas le sender)
- Status = `pending_request`

**`send_wall_message`** (mig 00095) :
- Auth + non suspendu
- Activity status IN (`published`, `in_progress`)
- User est participant accepté
- Rate limit : 30 messages / minute / activité
- Advisory lock pour la sérialisation

**`send_private_message`** :
- Auth + non suspendu
- Conversation existe et user est user_1 ou user_2
- Status conversation = `active`
- Blocage bidirectionnel
- Rate limit similaire au wall

**`edit_wall_message` / `edit_private_message`** :
- Auth + non suspendu
- User est l'auteur (`user_id = auth.uid()`)
- Modifie uniquement `content` + `edited_at`
- Wall : status activité IN (`published`, `in_progress`)

### Présence — auto-expire

**`expire_stale_contact_requests()`** (mig 00142) — interne :
- Flip `pending_request` → `declined` quand `request_expires_at < NOW()`
- Hooké dans `check_activity_transitions` (foreground app)

**Trigger `on_activity_finished_expire_seat_requests`** (mig 00142) :
- AFTER UPDATE OF status sur activities
- Si NEW.status IN (`completed`, `cancelled`, `expired`) et OLD.status différent : flip pending seat_requests → `expired` + notif `seat_request_expired` au requester

### Transport & sièges

**`set_participation_transport`, `request_seat`, `accept_seat_request`, `decline_seat_request`, `cancel_accepted_seat`** (mig 00120) :
- Auth + non suspendu
- Activity status IN (`published`, `in_progress`)
- User est participant accepté
- Pour accept/decline : `auth.uid() = driver_id` ; status = `pending` ; siège disponible

### Alertes

**`create_alert`, `delete_alert`** :
- Auth + non suspendu
- User tier ∈ (`premium`, `pro`)
- Bornes lat/lng valides ; `radius_km` ∈ [1, 100]

**`check_alerts_for_activity(p_activity_id)`** — interne :
- Pour chaque alerte qui matche (sport, level, period, location dans le rayon) : crée notif `alert_match` (capée 3/jour/user UTC midnight reset)

### Auth users

**`set_date_of_birth(p_dob)`** :
- Auth + non suspendu
- `date_of_birth` est NULL (one-shot)
- Âge ≥ 18 ans

**`accept_tos()`** :
- Auth + non suspendu
- `accepted_tos_at` est NULL (one-shot)
- Set `accepted_tos_at` et `accepted_privacy_at` à NOW()

**`register_push_token(p_token, p_device_id)`** (mig 00121) :
- Auth + non suspendu
- UPSERT dans `push_tokens` keyed sur `(user_id, device_id)` — multi-device aware

**`ensure_user_row()`** :
- Crée la ligne `public.users` si elle manque (self-heal)

**`delete_own_account()`** — interne (appelé via Edge Function) :
- Voir section Suppression de compte

### Activity transitions (cron / lazy)

**`transition_statuses_only()`** (mig 00148) — cron :
- Flip published → in_progress (start atteint)
- Flip in_progress → completed (end atteint)
- Flip published → expired (start + 2h, aucun participant non-créateur)
- Émet `presence_pre_warning` (T-2h), `presence_validate_now` (T0), `presence_validate_warning` (T+duration/2), `qr_create_reminder` (T0 créateur), `peer_review_closing` (end+22h..end+24h)
- Appelle `close_due_presence_windows()`

**`check_activity_transitions()`** (mig 00142) — appelé par client en foreground :
- Wraps `transition_statuses_only()` + `expire_stale_contact_requests()` sous advisory lock

### Reliability score

**`recalculate_reliability_score(p_user_id)`** — appelée par tout flip de présence :
- Bayesian score avec PRIOR = 3
- Stocke dans `users.reliability_score` (privilégiée, jamais write client)

---

## Exposition des fonctions via PostgREST

Supabase/PostgREST expose automatiquement toutes les fonctions du schema `public`. **Toute fonction non destinée aux clients doit avoir EXECUTE révoqué.**

### Fonctions client-callable (GRANT EXECUTE TO authenticated)

**Activités :** `create_activity`, `join_activity`, `leave_activity`, `cancel_activity`, `accept_participation`, `refuse_participation`, `remove_participant`, `update_activity` (champs autorisés), `regenerate_invite_token`, `get_activity_by_invite_token`, `get_own_invite_token`

**Présence :** `confirm_presence_via_geo`, `confirm_presence_via_token`, `create_presence_token`, `peer_validate_presence`, `give_reputation_badge`, `revoke_reputation_badge`, `get_my_active_presence_activities`, `get_activity_peer_review_state`, `get_user_reputation`, `get_user_trophies`, `endorse_sport_level`

**Conversations :** `create_or_get_conversation`, `accept_contact_request`, `decline_contact_request`, `hide_conversation`, `send_wall_message`, `send_private_message`, `edit_wall_message`, `edit_private_message`, `delete_wall_message`, `delete_private_message`, `share_trace_message`

**Transport / sièges :** `set_participation_transport`, `request_seat`, `accept_seat_request`, `decline_seat_request`, `cancel_accepted_seat`

**Alertes / gear :** `create_alert`, `delete_alert`, `set_activity_gear`, `update_gear`, `add_gear_assignment`, `remove_gear_assignment`

**User :** `set_date_of_birth`, `accept_tos`, `register_push_token`, `ensure_user_row`, `block_user`, `unblock_user`, `report_content`, `get_user_public_stats`, `get_user_sport_breakdown`

**Cron-on-foreground :** `check_activity_transitions`

### Fonctions internes (REVOKE EXECUTE FROM anon AND authenticated)

- `create_notification`, `notify_presence_*`, `notify_creator_qr_reminder`, `notify_peer_review_closing`, `notify_presence_confirmed`
- `transition_statuses_only`, `transition_single_activity`, `close_due_presence_windows`, `close_presence_window_for`
- `expire_stale_contact_requests`
- `check_alerts_for_activity`
- `award_badge_progression`, `recalculate_reliability_score`
- `handle_new_user`, `handle_user_update`, `handle_activity_update`, `strip_html_*` (triggers)
- `push_notification_to_device` (trigger)
- `on_activity_completed_award_badges`, `on_activity_finished_expire_seat_requests` (triggers)
- `generate_random_name`, `sanitize_notif_text`, `badge_tier_for`

### Fonctions privilégiées admin

- `delete_own_account` — appelée par Edge Function avec `service_role`
- `admin_suspend_user`, `admin_unsuspend_user`, `admin_resolve_report` — `auth.uid()` doit être admin

---

## SECURITY DEFINER — toutes les fonctions

**Constat architectural :** Le design bloque tous les INSERT/UPDATE/DELETE clients sur 7+ tables. Les fonctions qui écrivent dans ces tables DOIVENT être SECURITY DEFINER pour bypasser RLS.

En pratique, **toutes les fonctions client-callable sont SECURITY DEFINER** — chacune écrit dans au moins une table restreinte. La catégorie SECURITY INVOKER est vide.

**Conséquence critique :** Il n'y a PAS de filet de sécurité RLS sur les fonctions. La chaîne d'autorisation documentée dans chaque fonction EST la seule ligne de défense. Chaque vérification manquante = une faille directe.

**Règle :** Toute fonction SECURITY DEFINER doit inclure `SET search_path = public` (ou `public, extensions` si elle utilise PostGIS / pg_net) :
```sql
CREATE FUNCTION xxx() RETURNS yyy
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$ ... $$;
```

---

## Tables sans INSERT client — inserts par fonctions uniquement

| Table | Opérations bloquées | Raison | Fonctions autorisées |
|-------|---------------------|--------|---------------------|
| `users` | INSERT | Empêche injection de is_admin, skip age check | Trigger `handle_new_user` + RPC `ensure_user_row` |
| `notifications` | INSERT, DELETE | Empêche création de fausses notifications | `create_notification` + helpers `notify_*` |
| `wall_messages` | INSERT, UPDATE, DELETE | Bypass rate limit, status, participant check | `send_wall_message`, `edit_wall_message`, `delete_wall_message` |
| `private_messages` | INSERT, UPDATE, DELETE | Bypass rate limit, blocked check | `send_private_message`, `edit_private_message`, `delete_private_message`, `share_trace_message` |
| `participations` | INSERT, UPDATE, DELETE | Bypass concurrent join, status, removal rules | `join_activity`, `accept_*`, `refuse_*`, `remove_participant`, `leave_activity`, `set_participation_transport`, `confirm_presence_via_*`, `peer_validate_presence` |
| `conversations` | INSERT, UPDATE, DELETE | Bypass rate limit, duplicate check | `create_or_get_conversation`, `accept_contact_request`, `decline_contact_request`, `send_private_message` (last_message_at), `hide_conversation` |
| `peer_validations` | INSERT, UPDATE, DELETE | Bypass voter-presence + threshold logic | `peer_validate_presence` |
| `reputation_votes` | INSERT, UPDATE, DELETE | Bypass UNIQUE + window check | `give_reputation_badge`, `revoke_reputation_badge` |
| `presence_tokens` | INSERT, UPDATE, DELETE | Tokens issus uniquement par le créateur | `create_presence_token` |
| `push_tokens` | INSERT, UPDATE, DELETE | Multi-device managed | `register_push_token` |
| `seat_requests` | INSERT, UPDATE | Bypass driver/requester checks | `request_seat`, `accept_seat_request`, `decline_seat_request`, `cancel_accepted_seat`, trigger d'expiration |
| `activity_alerts` | INSERT, UPDATE, DELETE | Bypass tier check, sanity bounds | `create_alert`, `delete_alert` |
| `activity_gear` | INSERT, UPDATE, DELETE | Bypass participant/creator check | `set_activity_gear`, `add_gear_assignment`, `remove_gear_assignment`, `update_gear` |
| `sport_level_endorsements` | INSERT, UPDATE, DELETE | Bypass UNIQUE + window check | `endorse_sport_level` |
| `user_badge_progression` | INSERT, UPDATE | Auto-managed par trigger | `award_badge_progression` |

Sans ces restrictions, un client peut contourner les fonctions et opérer directement via l'API REST.

---

## Messages d'erreur — pas de fuite d'information

Les messages d'erreur retournés au client ne doivent pas révéler de détails d'implémentation :
```sql
-- ❌ Révèle le mécanisme de protection :
RAISE EXCEPTION 'Status can only be changed via dedicated functions';
RAISE EXCEPTION 'Privileged columns can only be changed via dedicated functions';

-- ✅ Générique, pas de fuite :
RAISE EXCEPTION 'Operation not permitted';
```

**Exception :** quelques fonctions présence renvoient des codes spécifiques à des contraintes UX-actionnables (mig 00139). Ces codes ne révèlent pas d'implémentation, juste une catégorie d'état :
- `peer_review_window_not_open` (avant T+15min après end)
- `peer_review_window_closed` (après T+24h)
- `peer_voter_not_present` (le voter n'est pas confirmed_present)
- `peer_already_validated` (target déjà validé)

Sécurité inchangée : auth, suspension, self-vote, target-not-in-activity, activity-not-eligible → tous `Operation not permitted` générique.

---

## PL/pgSQL — prévention injection SQL

```sql
-- ❌ JAMAIS — vulnérable à l'injection SQL :
EXECUTE 'INSERT INTO activities (title) VALUES (''' || p_title || ''')';

-- ✅ TOUJOURS — paramètres bindés :
INSERT INTO activities (title) VALUES (p_title);

-- ✅ Si EXECUTE est nécessaire, utiliser USING :
EXECUTE 'INSERT INTO activities (title) VALUES ($1)' USING p_title;
```

---

## Fonctions de création — never trust client values

Les fonctions Postgres de création n'acceptent que les champs modifiables par l'utilisateur. Les champs privilégiés sont hardcodés :
```sql
INSERT INTO activities (
  creator_id, status, created_at, title, ...
) VALUES (
  auth.uid(),      -- hardcodé depuis l'auth
  'published',     -- hardcodé
  NOW(),           -- hardcodé
  p_title, ...     -- du client
);
```

---

## Colonnes privilégiées — jamais modifiables directement par le client

### Table `users`
- `is_admin`, `tier`, `is_pro_verified`, `pro_verified_at`, `suspended_at`
- `phone_verified`, `phone_verified_at` (Supabase Auth flow)
- `accepted_tos_at`, `accepted_privacy_at` (one-shot via `accept_tos`)
- `date_of_birth` (one-shot via `set_date_of_birth`)
- `reliability_score` (auto-calculé)
- `notification_preferences` (UPDATE direct OK — c'est l'utilisateur qui choisit ses propres préférences)
- `subscription_status`, `stripe_customer_id` (Stripe webhook seulement)
- `push_token` (legacy column, remplacé par `push_tokens` table — UPDATE quand même bloqué)

**Colonnes user modifiables par le client :**
`display_name`, `avatar_url`, `bio`, `sports`, `levels_per_sport`, `notification_preferences`

**Enforcement : trigger `handle_user_update`** — approche **whitelist** :
```sql
IF current_setting('junto.bypass_lock', true) = 'true' THEN
  NEW.updated_at := NOW();
  RETURN NEW;
END IF;

-- WHITELIST : forcer toutes les colonnes non autorisées à OLD
NEW.email := OLD.email;
NEW.created_at := OLD.created_at;
NEW.is_admin := OLD.is_admin;
NEW.tier := OLD.tier;
NEW.is_pro_verified := OLD.is_pro_verified;
NEW.suspended_at := OLD.suspended_at;
NEW.phone_verified := OLD.phone_verified;
NEW.accepted_tos_at := OLD.accepted_tos_at;
NEW.accepted_privacy_at := OLD.accepted_privacy_at;
NEW.date_of_birth := OLD.date_of_birth;
NEW.reliability_score := OLD.reliability_score;
NEW.subscription_status := OLD.subscription_status;
NEW.stripe_customer_id := OLD.stripe_customer_id;
NEW.push_token := OLD.push_token;

NEW.updated_at := NOW();
```

**Pourquoi whitelist** : chaque nouvelle colonne est automatiquement protégée (forcée à OLD). Le défaut sûr est "protégé".

### Table `activities`
- `creator_id`, `status`, `invite_token`, `created_at` — toujours OLD (whitelist inconditionnelle)
- `location_*`, `starts_at`, `level`, `max_participants`, `visibility` — verrouillées quand des participants existent
- `title`, `description`, `sport_id`, `duration`, `requires_presence` — modifiables si créateur

### Table `participations`
- `confirmed_present` — modifiable uniquement via les fonctions de présence (`confirm_presence_via_geo`, `confirm_presence_via_token`, `peer_validate_presence`)
- `status` — modifiable uniquement via les fonctions de participation
- `transport_*` — modifiable via `set_participation_transport`

### Table `notifications`
- INSERT interdit pour les clients (fonctions seulement)
- UPDATE limité à `read_at` sur ses propres notifs

### Table `sports`
- SELECT pour tous (anon inclus) — données de référence
- INSERT/UPDATE/DELETE admin uniquement

### Table `blocked_users`
- INSERT/DELETE uniquement avec `blocker_id = auth.uid()`

---

## Matrice RLS complète

**Légende :** ✅ = policy existe | ❌ = pas de policy (interdite) | 🔧 = via fonction SECURITY DEFINER

#### `users`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Own row: full. Others: via `public_profiles` view | ❌ Trigger only | ✅ Own row + whitelist trigger | ❌ Edge Function only |

#### `activities`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Discovery: published/in_progress, créateur non suspendu, non bloqué. Privé: via RPC + invite_token | 🔧 `create_activity` | ✅ `auth.uid() = creator_id` + whitelist trigger | ❌ Cancel only |

#### `sports`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| ✅ Everyone (incl. anon) | ❌ Admin only | ❌ Admin only | ❌ Admin only |

#### `participations`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Créateur voit toutes pour son activité ; participant voit la sienne ; accepted voient les autres accepted | 🔧 Functions only | 🔧 Functions only | 🔧 Functions only |

#### `wall_messages`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Accepted participants, blocked filtered on user_id | 🔧 `send_wall_message` | 🔧 `edit_wall_message` | 🔧 Soft delete |

#### `private_messages`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Sender/receiver, **bidirectional** block check | 🔧 `send_private_message` | 🔧 `edit_private_message` | 🔧 Soft delete |

#### `notifications`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `auth.uid() = user_id` | 🔧 Functions only | ✅ `read_at` on own row | ❌ |

#### `blocked_users`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `blocker_id = auth.uid()` + admins | ✅ `blocker_id = auth.uid()` | ❌ | ✅ `blocker_id = auth.uid()` |

#### `conversations`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `user_1 = auth.uid() OR user_2 = auth.uid()`, **bidirectional** block | 🔧 Functions only | 🔧 Functions only | ❌ Soft via `hide_conversation` |

#### `reports`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Reporter voit les siens + admins voient tout | ✅ Authenticated | ✅ Admins (status) | ❌ |

#### `peer_validations` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Voter ou voted | 🔧 `peer_validate_presence` | ❌ | ❌ |

#### `reputation_votes` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Voter ou voted | 🔧 `give_reputation_badge` | 🔧 `revoke_reputation_badge` | 🔧 |

#### `presence_tokens` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| ❌ (jamais lu directement par client) | 🔧 `create_presence_token` | ❌ | ❌ |

#### `push_tokens` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| ❌ (jamais lu) | 🔧 `register_push_token` | 🔧 | 🔧 |

#### `seat_requests` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Requester ou driver | 🔧 `request_seat` | 🔧 Functions | ❌ |

#### `activity_alerts` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `auth.uid() = user_id` | 🔧 `create_alert` | ❌ | 🔧 `delete_alert` |

#### `user_badge_progression` (nouveau)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `auth.uid() = user_id` | 🔧 trigger via `award_badge_progression` | 🔧 | ❌ |

#### `activity_gear`, `sport_level_endorsements` (nouveau)
Voir leurs fonctions dédiées. Lecture par participants/créateur.

---

## Système de présence

### Fenêtres de validation (mig 00147)

| Phase | Fenêtre | Path |
|-------|---------|------|
| Enregistrement geofence OS | T-2h → T+15min | `get_my_active_presence_activities` |
| Validation géo (live + replay) | T-15min → T+15min | `confirm_presence_via_geo` |
| Validation QR | T-15min → end + 3h | `confirm_presence_via_token` |
| Émission token QR | T-15min → end + 3h | `create_presence_token` |
| Replay offline (deadline arrivée) | end + 3h | `confirm_presence_via_geo(.., p_captured_at)` |
| Peer review | end + 15min → end + 24h | `peer_validate_presence`, `give_reputation_badge` |

### Distance check (mig 00149)

`confirm_presence_via_geo` calcule `min(d_start, d_meeting, d_end, d_trace)` où `d_trace` est la distance au polyline `trace_geojson` quand il existe (PostGIS `ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, user_point)`). Seuil 150m.

### Replay offline

Pour l'usage outdoor (alpinisme, ski de rando) où le réseau peut être absent au meetup :
- Le client (TaskManager geofence task + foreground watcher) cache `{activity_id, lng, lat, captured_at}` quand l'RPC échoue sur transport
- Le flusher draine sur retour réseau / app foreground
- `p_captured_at` doit être dans la fenêtre de validation ; arrivée du replay ≤ end + 3h
- Trust : envelope non-signée, accepté-participant + bornes (window/distance/single-shot) + check social (badges réputation `level_overestimated`, `unreliable_field`)

### Peer review

- Threshold : 1 vote pour 2-participant, 2 votes pour 3+
- Voter doit être `confirmed_present = TRUE` (sauf cas créateur en 2-participant qui a un direct flip)
- Notif `peer_review_closing` envoyée à T+22h aux non-voteurs

### Notifications

| Moment | Type | Audience |
|--------|------|----------|
| T-2h | `presence_pre_warning` | Participants |
| T0 | `presence_validate_now` | Participants non confirmés |
| T0 | `qr_create_reminder` | Créateur |
| T+duration/2 | `presence_validate_warning` | Participants non confirmés |
| Validation | `presence_confirmed` | User validé |
| End | `rate_participants` | Participants |
| End+22h | `peer_review_closing` | Non-voteurs confirmés |
| Détection geofence (BG) | "Présence détectée" → "Présence confirmée" (local notif) | Participant |

Les types `presence_pre_warning`, `presence_validate_now`, `presence_validate_warning`, `presence_confirmed` partagent un `collapse_id = 'presence-{activity_id}'` — un seul slot OS par activité, mis à jour au lieu d'être empilé.

---

## Système de badges

### Badges progression (mig 00135)

3 catégories × 5 tiers :

| Tier | Activités | Joined label | Created label | Sport label |
|------|-----------|-------------|--------------|-------------|
| t1 | 5 | Membre | Initiateur | Curieux |
| t2 | 10 | Actif | Organisateur | Adepte |
| t3 | 20 | Régulier | Animateur | Mordu |
| t4 | 50 | Habitué | Coordinateur | Passionné |
| t5 | 75+ | Pilier | Bâtisseur | Inconditionnel |

Auto-attribution via trigger `on_activity_completed_award_badges` qui appelle `award_badge_progression`. Notif `badge_unlocked` à chaque level-up.

### Badges réputation (peer-voted, mig 00134)

**Positifs (seuil 5)** : `trustworthy`, `great_leader`, `good_vibes`, `punctual`
**Négatifs (seuil 15)** : `level_overestimated`, `difficult_attitude`, `unreliable_field`, `aggressive`

Vote via `give_reputation_badge`, retrait via `revoke_reputation_badge`. Visibilité publique uniquement quand le seuil est atteint.

### Reliability score

Bayesian avec PRIOR = 3. Recalculé sur chaque flip de `confirmed_present`. Stocké dans `users.reliability_score` (privilégiée). Tier exposé via `reliability_tier` à 50 / 75 / 90.

---

## Push notifications

### Architecture (mig 00121, 00122, 00131, 00146, 00148)

- Table `push_tokens` (multi-device) keyed sur `(user_id, device_id)`. Le `device_id` est généré côté client et persisté dans SecureStore
- Trigger AFTER INSERT sur `notifications` : `push_notification_to_device`
- L'envoi passe par l'Edge Function `send-push` (header secret partagé) qui appelle Expo Push API

### Routing par type

```sql
CASE NEW.type
  WHEN 'rate_participants', 'request_refused', 'participant_left_late' THEN
    v_should_push := FALSE;          -- in-app only

  WHEN 'participant_joined' THEN
    v_collapse_id := 'joined-' || activity_id;  -- coalesce N joins → 1 visible

  WHEN 'presence_pre_warning', 'presence_validate_now', 'presence_validate_warning' THEN
    v_collapse_id := 'presence-' || activity_id;
    v_title := title || ' (×N)';     -- count progression dans la même slot

  WHEN 'presence_confirmed' THEN
    v_collapse_id := 'presence-' || activity_id;  -- remplace "validate_*"

  WHEN 'activity_cancelled' THEN
    v_should_push := starts_at - now() < INTERVAL '48 hours';  -- pas de push si activité lointaine

  WHEN 'activity_updated' THEN
    v_should_push := changes ? 'starts_at' OR 'duration' OR 'location_*';  -- logistique uniquement
END CASE;
```

### Sanitisation contenu

- `sanitize_notif_text` strip HTML + control chars + clip à 200 chars
- Appliqué automatiquement à title et body avant push
- Empêche l'exfiltration via lockscreen lock

### Auto-purge

Notifs > 7 jours supprimées par cron. Empêche l'accumulation infinie.

### Sur suspension

`push_token` cleared et `push_tokens` rows pour ce user supprimées. Pas de push à un user suspendu.

---

## Storage

### Buckets

| Bucket | Type | Usage |
|--------|------|-------|
| `avatars` | Public | Path fixe `/avatars/{user_id}/avatar`. Le nouveau écrase l'ancien — pas d'accumulation |
| `pro-documents` | Private | SIRET, BPJEPS, certifications. Lecture admin uniquement |

### Upload images
1. Validation magic bytes (pas que l'extension)
2. Taille max 5MB
3. Formats JPEG, PNG, WebP
4. EXIF stripping (GPS/device metadata)

### Upload GPX

Parsé côté client, coordonnées extraites en GeoJSON LineString stocké en `activities.trace_geojson` (JSONB). **Pas de bucket GPX** — élimine le risque de servir un XML malveillant.

Validation client :
- Parser sécurisé (XXE désactivé)
- Limit d'expansion (XML bombs)
- Taille max 10MB avant parsing
- LineString avec 2-10000 coordonnées (CHECK constraint)

---

## Authentification & Sessions

### Secure Storage
- Tokens d'auth via `expo-secure-store` (jamais AsyncStorage = plaintext)
- `device_id` pour push tokens dans SecureStore aussi

### Session
- Access token : 1h (auto-refresh)
- Refresh token : 30 jours
- Changement de mot de passe : invalide tous les refresh tokens

### Logout
- Avant `signOut()` : potentiellement effacer push_tokens row pour ce device
- Geofences déregistrés automatiquement via cleanup du hook `usePresenceGeofences` (mig client cleanup)

### Email
- Changement d'email : nécessite vérification de l'ancien ET du nouvel email
- Templates email customisés (Junto-branded) dans le dashboard Supabase

### Reset password
- `requestPasswordReset(email)` envoie un email avec lien vers `https://getjunto.app/auth/reset-password?token_hash=...`
- Web bridge redirige vers deep link `junto://reset-password?token_hash=...`
- App ouvre `(visitor)/reset-password` ; AuthGate pin l'utilisateur sur cet écran même si la session devient active (recovery)
- Soumission : `verifyOtp` puis `updateUser({ password })` puis sign out

### Âge
- `date_of_birth` obligatoire à l'inscription
- 18 ans minimum (`CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years')`)
- One-shot via `set_date_of_birth`

---

## Profil — Matrice de visibilité

| Champ | Non connecté | Connecté | Soi-même |
|-------|-------------|----------|----------|
| display_name, avatar, bio, sports, levels_per_sport, created_at | Oui | Oui | Oui |
| stats activités | Non | Agrégées | Détail complet |
| reliability_tier (label) | Non | Oui | Oui |
| reliability_score (raw %) | Non | Non | Oui |
| email, téléphone, date_of_birth | Non | Non | Oui |

---

## Rate Limiting

### Création d'activité
- Free / Premium / Pro : **20/24h** par défaut (mig 00144)
- **Admin** : illimité (skipé)
- Free tier additional cap : 4/mois (business rule)
- Advisory lock par user pour sérialiser concurrent creates

### Wall messages (mig 00095)
- 30 messages / minute / activité / user
- Advisory lock pour sérialisation

### Private messages
- Pattern similaire au wall (rate par minute par conversation)

### Création de conversation
- 10 demandes pending par sender (rolling, pas par heure — les pending occupent le quota)

### Join activity
- 10 / heure / user

### Recherche géo
- Rayon max 100km (PostGIS check)

### Alert match
- Cap 3/jour/user (UTC midnight reset)

### Supabase API rate
- Anonyme : 30 req/min
- Authentifié : 100 req/min

---

## Protection des données

### Stratégie de suppression par table

| Table | À la suppression utilisateur | FK |
|-------|------------------------------|-----|
| participations | Supprimer | CASCADE |
| activities (créées) | Annuler via Edge Function puis CASCADE | CASCADE |
| wall_messages | Anonymiser | SET NULL (user_id) |
| private_messages | Supprimer | CASCADE |
| conversations | Supprimer | CASCADE |
| notifications | Supprimer | CASCADE |
| reputation_votes (voter) | Supprimer | CASCADE |
| reputation_votes (voted) | Supprimer | CASCADE |
| peer_validations | Supprimer | CASCADE |
| reports (reporter) | Anonymiser | SET NULL |
| reports (reported) | Conserver | RESTRICT |
| blocked_users | Supprimer | CASCADE |
| seat_requests | Supprimer | CASCADE |
| activity_alerts | Supprimer | CASCADE |
| push_tokens | Supprimer | CASCADE |
| user_badge_progression | Supprimer | CASCADE |

### Consentement
- `accepted_tos_at`, `accepted_privacy_at` — horodatages
- One-shot via `accept_tos`, jamais re-settable

---

## Modération

### Champs utilisateur
- `is_admin BOOLEAN DEFAULT FALSE`
- `suspended_at TIMESTAMPTZ NULL` — suspension réversible

### Suspension
- Activités, messages, profil filtrés par RLS
- Push tokens cleared
- `confirmed_present`, `reliability_score` préservés (utiles si réinstauration)

### Tables
- `blocked_users` — affecte RLS sur toutes tables
- `reports` — INSERT par tous, SELECT par reporter+admin, UPDATE admin only

---

## Intégrité des données

### UNIQUE / CHECK critiques

```sql
-- Participations
UNIQUE (user_id, activity_id)
CHECK (status IN ('accepted', 'pending', 'declined', 'removed', 'left'))

-- Reputation votes
UNIQUE (voter_id, voted_id, activity_id, badge_key)
CHECK (voter_id != voted_id)

-- Peer validations
UNIQUE (voter_id, voted_id, activity_id)
CHECK (voter_id != voted_id)

-- Conversations
UNIQUE (user_1, user_2)  -- IDs ordonnés à la création
CHECK (user_1 != user_2)

-- Activities
CHECK (max_participants IS NULL OR max_participants BETWEEN 2 AND 50)
CHECK (starts_at > NOW())  -- création
CHECK (duration >= INTERVAL '15 minutes')
CHECK (char_length(title) BETWEEN 3 AND 100)
CHECK (char_length(description) <= 2000)
CHECK (status IN ('published', 'in_progress', 'completed', 'cancelled', 'expired'))
CHECK (visibility IN ('public', 'approval', 'private_link', 'private_link_approval'))
CHECK (trace_geojson IS NULL OR (
  trace_geojson->>'type' = 'LineString'
  AND jsonb_array_length(trace_geojson->'coordinates') BETWEEN 2 AND 10000
))

-- Seat requests (mig 00142)
CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled', 'expired'))

-- Users
CHECK (char_length(display_name) BETWEEN 2 AND 30)
CHECK (char_length(bio) <= 500)
```

### Concurrent join protection

Fonction Postgres avec `FOR UPDATE` sur la ligne activity. Capacité comparée à `COALESCE(max_participants, 50)` pour gérer les activités open.

### Verrouillage des champs d'activité

Trigger `handle_activity_update` (whitelist) :
- Inconditionnelles : `creator_id`, `status`, `invite_token`, `created_at` toujours OLD
- Conditionnelles : `location_*`, `starts_at`, `level`, `max_participants`, `visibility` verrouillées si participants existent
- Bypass via `set_config('junto.bypass_lock', 'true', true)` — uniquement appelé par fonctions internes

**Règle absolue :** aucune fonction client-callable ne doit set ce flag dans une branche atteignable par input client.

### Transitions automatiques de statut

Cron / lazy via `transition_statuses_only` :
- `published → in_progress` quand `starts_at <= NOW()`
- `in_progress → completed` quand `starts_at + duration <= NOW()`
- `published → expired` quand `starts_at + 2h < NOW()` et aucun participant non-créateur

### Deep links
- Custom scheme `junto://` (configuré dans app.config.ts)
- Universal links sur `getjunto.app` pour `/activity/*`, `/invite/*` (associatedDomains iOS + autoVerify Android)
- Reset password via web bridge → deep link

---

## Configuration Supabase

### Setup checklist
- [ ] Désactiver GraphQL
- [ ] Configurer le rate limiting API (30/min anon, 100/min auth)
- [ ] Configurer la durée de session (1h access, 30j refresh)
- [ ] Activer la confirmation email
- [ ] Configurer le minimum mot de passe à 8 caractères
- [ ] Verrouiller les redirect URIs (Supabase Site URL + Redirect URLs)
- [ ] Customiser les templates email (welcome, reset password) — Junto-branded
- [ ] Custom SMTP pour le sender (sinon "Supabase Auth" sender visible)
- [ ] Statement timeout configuré
- [ ] FCM V1 credentials chargés pour push Android
- [ ] APNs credentials chargés pour push iOS
- [ ] PostGIS extension enabled

### Edge Functions secrets
- `PUSH_WEBHOOK_SECRET` (matché par `app_config.push_webhook_secret`)
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (auto-injected)

---

## Sanitisation des inputs texte

`sanitize_notif_text` strip HTML + control chars + clip à 200 chars. Appliqué dans `create_notification`.

Trigger `strip_html_*` sur tables avec texte user-generated (users.bio, activities.title/description, messages.content). Empêche l'injection HTML dans un futur dashboard admin / partage web.

---

## Anti-abus

### Removal définitif
Status `removed` est final. `join_activity` rejette si participation existante = `removed`.

### Blocage — directionnalité

| Contexte | Comportement |
|----------|-------------|
| Mur d'événement | Unidirectionnel (A bloque B → A ne voit plus B ; B voit toujours A) |
| Messages privés | Bidirectionnel |
| Rejoindre activité | Unidirectionnel (B ne peut pas rejoindre les activités de A) |
| Découverte | Unidirectionnel |
| Liste participants | Unidirectionnel (compteur reste exact) |
| Reviews / reputation_votes | Unidirectionnel à l'affichage, comptent dans la moyenne globale |

### Account enumeration
Supabase Auth configuré pour retourner des messages uniformes (login + inscription).

### Stripe webhook idempotency
- Stocker `event_id` traités
- Traiter D'ABORD, stocker ENSUITE
- Ignorer les doublons

### Peer review collusion (résiduel)
Connue : 2 confirmed friends peuvent valider un no-show en activité 3-personnes. Atténuation : badges réputation peer-voted (`unreliable_field`, `level_overestimated`). Pas de signature server-side du replay offline (envelope non-signée — bornes window/distance comme garde-fou).

---

## Changement de tier — règles métier

### Premium → Free
- Activités existantes restent actives
- Création nouvelles activités bloquée si > 4/mois actives
- Création private_link bloquée
- Badge "Vérifié" retiré

### Pro → non-Pro
- Display-time check sur `is_pro_verified`
- Pas de migration de données

---

## Suppression de compte — Edge Function

Architecture :
1. Le client appelle l'Edge Function `delete-user`
2. L'Edge Function vérifie `auth.uid()` du JWT
3. **Avant deleteUser :** annule toutes les activités `published`/`in_progress` (status → cancelled) + notifie les participants
4. `supabase.auth.admin.deleteUser(userId)` avec `service_role`
5. CASCADE / SET NULL applique la stratégie

Pourquoi l'étape 3 : sans annulation préalable, CASCADE supprimerait silencieusement les activités en cours.

---

## Bootstrap admin

Premier admin via SQL Editor du dashboard :
```sql
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET is_admin = TRUE WHERE display_name = 'admin_pseudo';
END $$;
```
Le bypass est nécessaire car `is_admin` est dans la whitelist du trigger user.

---

## Ce document est la référence sécurité

Toute question de sécurité se réfère à ce document. Mis à jour au fil du développement (la dernière refonte est postérieure à la mig 00149).
