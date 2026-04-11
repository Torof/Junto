# Junto — Modèle de Sécurité

## Table des matières — navigation rapide

**Ne pas lire ce fichier en entier. Utiliser la table "When to Read Which Doc" dans CLAUDE.md pour savoir quelles sections lire.**

| Section | Contenu | Quand consulter |
|---------|---------|-----------------|
| Principes fondamentaux | 4 principes de sécurité | Première lecture uniquement |
| Clés et secrets | service_role, API keys, .gitignore, keystore | Setup projet (Sprint 1 Phase C) |
| Row Level Security | Règle, pattern migration, public_profiles view, trigger user creation | Création de table |
| Chaîne d'autorisation | Checks obligatoires par fonction | Création de fonction |
| Exposition PostgREST | GRANT/REVOKE EXECUTE, fonctions internes vs client | Création de fonction |
| SECURITY DEFINER | Classification complète des fonctions | Création de fonction |
| Tables sans INSERT client | Matrice opérations bloquées par table | Création de fonction qui écrit |
| Messages d'erreur | Règle des messages génériques | Création de fonction |
| PL/pgSQL injection | Règle EXECUTE / paramètres bindés | Création de fonction avec SQL dynamique |
| Fonctions de création | Pattern : hardcoder les champs privilégiés | Création de fonction d'insertion |
| Politiques standard | Templates SQL RLS réutilisables | Création de table |
| Colonnes privilégiées | Liste par table, triggers whitelist, code complet | Création de table, ajout de colonne |
| Matrice RLS complète | SELECT/INSERT/UPDATE/DELETE par table avec SQL | Création de table, de policy |
| Realtime | Vérifications pour les subscriptions | Sprint 4 (wall), Sprint 7 (DM) |
| Storage | Buckets, policies, upload validation, GPX | Upload avatar (Sprint 5), pro-docs (Sprint 6) |
| Auth & Sessions | Secure storage, session config, logout, email, âge | Sprint 1 Phase C/E |
| Profil visibilité | Matrice champs × rôles | Sprint 5 (profils) |
| Rate Limiting | Limites par opération avec SQL | Création de fonction avec rate limit |
| Protection des données | Stratégie de suppression par table, wall anonymisation, consentement | Ajout de FK, Sprint 8 (suppression compte) |
| Modération | Suspension, blocked_users, reports RLS | Sprint 5 (block), Sprint 8 (modération) |
| Intégrité des données | UNIQUE/CHECK, updated_at, concurrent join, verrouillage champs, leave, transitions, deep links | Création de table, de fonction |
| Configuration Supabase | Checklist setup projet | Sprint 1 Phase C uniquement |
| Notifications push | Règle contenu vie privée | Sprint 4 (notifications) |
| Sanitisation texte | Strip HTML tags | Sprint 1 (trigger) |
| Anti-abus | Removal définitif, blocage directionnalité, rate limiting conversations, reviews, Stripe idempotency, account enumeration | Feature spécifique |
| Changement de tier | Downgrade Premium→Free, révocation Pro | Sprint 6 |
| Deep links App Links | Android App Links vérifiés | Sprint 8 |
| Suppression de compte | Architecture Edge Function complète | Sprint 8 |
| Bootstrap admin | Premier admin via SQL | Sprint 1 / Sprint 6 |

---

## Principes fondamentaux

### 1. Ne jamais faire confiance au client
La clé `anon` de Supabase est dans l'APK. N'importe qui peut l'extraire et appeler l'API directement. Toute règle métier, toute restriction d'accès, toute validation DOIT être appliquée côté serveur (RLS, contraintes DB, fonctions Postgres).

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
- **`service_role` key** : bypass TOUT le RLS → **JAMAIS dans le code client, JAMAIS dans `.env` côté app**
- Usage `service_role` : uniquement CI/CD, Edge Functions, scripts admin côté serveur

### API Keys
- **Google Places** : restreinte par package Android + signature SHA-1
- **Mapbox** : scopée par nom de package
- **Configuration** : faite dans les dashboards de chaque provider avant tout lancement public

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
`FORCE` garantit que RLS s'applique même au table owner (prévient les bypasses pendant le développement). Aucune donnée ne doit être insérée avant que RLS soit activé et les policies en place.

### Limitation RLS : colonnes
RLS opère sur les **lignes**, pas les colonnes. Pour la table `users` qui contient des champs privés (email, phone, date_of_birth), on ne peut pas empêcher un `SELECT email FROM users` via RLS seul.

**Solution : vue `public_profiles`**
```sql
CREATE VIEW public_profiles AS
SELECT id, display_name, avatar_url, bio, sports, levels_per_sport, created_at
FROM users
WHERE suspended_at IS NULL;
```
- Toutes les queries publiques (anon, authenticated consultant un autre profil) passent par la vue
- L'accès direct à la table `users` est réservé à `auth.uid() = id` (propre profil) et aux fonctions admin
- Empêche l'exposition accidentelle de email, phone, date_of_birth via l'anon key

**Grants obligatoires :**
```sql
GRANT SELECT ON public_profiles TO anon, authenticated;
-- PAS de GRANT SELECT sur la table users pour anon
-- SELECT sur users pour authenticated uniquement via RLS (auth.uid() = id)
```

### Création du profil utilisateur — trigger serveur uniquement
La ligne dans `public.users` est créée par un **trigger Postgres sur `auth.users`**, jamais par un INSERT client :
```sql
CREATE FUNCTION handle_new_user() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, display_name, created_at)
  VALUES (NEW.id, NEW.email, generate_random_name(), NOW());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();
```
- **Pas de policy INSERT sur `public.users` pour les clients** — seul le trigger peut créer des lignes
- Le client ne peut pas injecter `is_admin: true`, skip age verification, ou définir des defaults malveillants
- Les champs comme `date_of_birth`, `accepted_tos_at` sont set via des fonctions dédiées après la création initiale

### Chaîne d'autorisation complète par fonction

Chaque fonction Postgres doit vérifier TOUTES les conditions suivantes. Une vérification manquante = une faille.

**Règle universelle :** Chaque RPC function commence par :
```sql
IF auth.uid() IS NULL THEN
  RAISE EXCEPTION 'Not authenticated';
END IF;

IF EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL) THEN
  RAISE EXCEPTION 'Operation not permitted';
END IF;
```
Sans le check de suspension, un utilisateur suspendu peut toujours créer des activités, envoyer des messages, et rejoindre des activités. Le RLS cache son contenu aux autres, mais il continue à générer des données et des notifications — un fantôme invisible qui agit toujours.

**`create_activity` :**
- `auth.uid()` est authentifié
- `phone_verified = true` (vérifier dans la table users)
- Rate limit : 4/mois free, 2/jour tous tiers
- Tier check si visibility = private_link

**`join_activity` :**
- `auth.uid()` est authentifié
- Activity status IN ('published', 'in_progress')
- User n'est PAS le créateur (erreur claire, pas juste UNIQUE violation)
- User n'est PAS bloqué par le créateur (`blocked_users` check)
- Seat count < max_participants (avec FOR UPDATE)
- UNIQUE constraint empêche double join

**`accept_participation` / `refuse_participation` :**
- `auth.uid()` est le créateur de l'activité
- Activity status IN ('published', 'in_progress') — pas cancelled/completed/expired
- Participation status = 'pending'

**`cancel_activity` :**
- `auth.uid()` est le créateur
- Activity status IN ('published', 'in_progress') — pas cancelled/completed/expired

**`leave_activity` :**
- `auth.uid()` est le participant
- Participation status IN ('accepted', 'pending') — pas 'removed'
- Activity status IN ('published', 'in_progress') — pas cancelled/completed/expired

**`remove_participant` :**
- `auth.uid()` est le créateur de l'activité
- Le participant ciblé n'est PAS le créateur (ne peut pas se retirer soi-même)
- Participation status = 'accepted'

**`send_wall_message` :**
- `auth.uid()` est authentifié + non suspendu
- Activity status IN ('published', 'in_progress') — pas de messages sur activité terminée/annulée
- User est participant accepté de l'activité
- Rate limit : 1 message / minute / activité (mur = coordination, pas chat)
- Advisory lock si nécessaire

**`send_private_message` :**
- `auth.uid()` est authentifié + non suspendu
- Conversation existe et user est user_1 ou user_2
- Blocage bidirectionnel : ni l'expéditeur ni le destinataire ne bloque l'autre
- Rate limit : même pattern que wall messages

**`edit_wall_message` / `edit_private_message` :**
- `auth.uid()` est authentifié + non suspendu
- User est l'auteur du message (`user_id = auth.uid()`)
- Modifie uniquement `content` + `edited_at` (edit) ou `deleted_at` (soft delete)
- Activity status IN ('published', 'in_progress') pour wall messages

**`create_or_get_conversation` :**
- `auth.uid()` est authentifié + non suspendu
- L'autre utilisateur existe et n'est pas suspendu
- Blocage bidirectionnel : ni l'un ni l'autre ne bloque
- Rate limit : 10 nouvelles conversations / heure
- Si conversation existe déjà : retourner l'existante (pas d'insert)

**`create_review` :**
- `auth.uid()` est authentifié + non suspendu
- Activity status = 'completed'
- Reviewer ET reviewed sont participants acceptés de la même activité
- Reviewer != reviewed
- UNIQUE constraint empêche double review

**`update_push_token` :**
- `auth.uid()` est authentifié + non suspendu
- Met à jour uniquement `push_token` sur le propre row de l'utilisateur

**`set_date_of_birth` :**
- `auth.uid()` est authentifié
- `date_of_birth` est actuellement NULL (one-time only)
- Valeur fournie correspond à un âge >= 18 ans

**`accept_tos` :**
- `auth.uid()` est authentifié
- `accepted_tos_at` est actuellement NULL (one-time only)
- Set `accepted_tos_at` et `accepted_privacy_at` à NOW()

**`get_activity_by_invite_token` :**
- `auth.uid()` est authentifié + non suspendu
- Token UUID valide et correspond à une activité existante
- Retourne les infos de l'activité (même si privée)

### Exposition des fonctions via PostgREST

Supabase/PostgREST expose automatiquement **toutes les fonctions du schema `public`** en endpoints REST. Les fonctions internes (triggers, cron, utilitaires) sont donc appelables par n'importe quel client avec la clé `anon` — **même les fonctions SECURITY DEFINER**.

**Règle critique :** Toute fonction non destinée aux clients doit avoir `EXECUTE` révoqué :
```sql
REVOKE EXECUTE ON FUNCTION xxx FROM anon, authenticated;
```

**Fonctions client-callable (GRANT EXECUTE to authenticated ONLY, pas anon) :**
- `create_activity`, `join_activity`, `leave_activity`
- `accept_participation`, `refuse_participation`, `remove_participant`, `cancel_activity`
- `send_wall_message`, `send_private_message`, `edit_wall_message`, `edit_private_message`
- `create_or_get_conversation`, `create_review`
- `update_push_token`, `get_activity_by_invite_token`
- `set_date_of_birth`, `accept_tos`

```sql
-- Pour chaque fonction client-callable :
REVOKE EXECUTE ON FUNCTION xxx FROM anon;
GRANT EXECUTE ON FUNCTION xxx TO authenticated;
```

**Fonctions internes (REVOKE EXECUTE from anon AND authenticated) :**
- `create_notification` — si appelable par un client, permet de créer de fausses notifications pour n'importe quel user
- `transition_activity_status` — exécutée par pg_cron uniquement
- `check_activity_lock` — trigger, pas un RPC
- `check_user_update` — trigger, pas un RPC
- `update_updated_at` — trigger, pas un RPC
- `handle_new_user` — trigger sur auth.users
- `generate_random_name` — utilitaire interne

```sql
-- Pour chaque fonction interne :
REVOKE EXECUTE ON FUNCTION xxx FROM anon, authenticated;
```

### SECURITY DEFINER — toutes les fonctions

**Constat architectural :** Notre design bloque tous les INSERT/UPDATE/DELETE clients sur 7 tables (users, notifications, wall_messages, private_messages, participations, conversations, reviews). Les fonctions qui écrivent dans ces tables DOIVENT être SECURITY DEFINER pour bypasser ces restrictions.

En pratique, **toutes nos fonctions client-callable sont SECURITY DEFINER** — car chacune écrit dans au moins une table restreinte. La catégorie SECURITY INVOKER est vide.

**Conséquence critique :** Il n'y a PAS de filet de sécurité RLS sur les fonctions. La chaîne d'autorisation documentée dans chaque fonction EST la seule ligne de défense. Chaque vérification manquante = une faille directe. C'est le trade-off de notre choix de bloquer tous les writes directs.

**Règle : toute fonction SECURITY DEFINER doit inclure `SET search_path = public`** :
```sql
CREATE FUNCTION xxx() RETURNS yyy
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ ... $$;
```

**Fonctions SECURITY DEFINER — classification complète :**

| Fonction | Raison DEFINER | Callable par |
|----------|---------------|-------------|
| `create_activity` | INSERT dans activities + participations (pas de policy INSERT client) | authenticated |
| `join_activity` | INSERT dans participations (pas de policy INSERT client) | authenticated |
| `leave_activity` | UPDATE/DELETE participations (pas de policy UPDATE/DELETE client) | authenticated |
| `accept_participation` | UPDATE participations status (pas de policy UPDATE client) | authenticated |
| `refuse_participation` | UPDATE participations status (pas de policy UPDATE client) | authenticated |
| `remove_participant` | UPDATE participations status (pas de policy UPDATE client) | authenticated |
| `cancel_activity` | UPDATE activities status via bypass variable (trigger bloque) | authenticated |
| `send_wall_message` | INSERT wall_messages (pas de policy INSERT client) | authenticated |
| `send_private_message` | INSERT private_messages + UPDATE conversations (pas de policy client) | authenticated |
| `edit_wall_message` | UPDATE wall_messages (pas de policy UPDATE client) | authenticated |
| `edit_private_message` | UPDATE private_messages (pas de policy UPDATE client) | authenticated |
| `create_or_get_conversation` | INSERT conversations (pas de policy INSERT client) | authenticated |
| `create_review` | INSERT reviews (pas de policy INSERT client) | authenticated |
| `update_push_token` | UPDATE colonne privilégiée users | authenticated |
| `set_date_of_birth` | UPDATE colonne privilégiée users | authenticated |
| `accept_tos` | UPDATE colonne privilégiée users | authenticated |
| `get_activity_by_invite_token` | Lecture d'invite_token non exposé publiquement | authenticated |
| `create_notification` | INSERT notifications (pas de policy INSERT client) | **interne uniquement** |
| `transition_activity_status` | UPDATE activities status, pas de contexte utilisateur | **interne uniquement** |
| `handle_new_user` | INSERT users (pas de policy INSERT client) | **trigger uniquement** |
| `handle_user_update` | Trigger UPDATE users | **trigger uniquement** |
| `handle_activity_update` | Trigger UPDATE activities | **trigger uniquement** |
| `generate_random_name` | Utilitaire interne | **interne uniquement** |

### Tables sans INSERT client — inserts par fonctions uniquement

Les tables suivantes n'ont **aucune policy INSERT pour les clients**. Tous les inserts passent par des fonctions Postgres `SECURITY DEFINER` avec validation intégrée :

| Table | Opérations bloquées | Raison | Fonctions autorisées |
|-------|---------------------|--------|---------------------|
| `users` | INSERT | Empêche injection de is_admin, skip age check | Trigger `on_auth_user_created` |
| `notifications` | INSERT, DELETE | Empêche création de fausses notifications | `create_notification` |
| `wall_messages` | INSERT, UPDATE, DELETE | Empêche bypass rate limiting, status check, participant check. Empêche tampering user_id/activity_id sur edit. | `send_wall_message`, `edit_wall_message` |
| `private_messages` | INSERT, UPDATE, DELETE | Empêche bypass rate limiting et blocked check. Empêche tampering. | `send_private_message`, `edit_private_message` |
| `participations` | INSERT, UPDATE, DELETE | Empêche bypass concurrent join, status checks, removal rules | `join_activity`, `accept_participation`, `refuse_participation`, `remove_participant`, `leave_activity` |
| `conversations` | INSERT, UPDATE, DELETE | Empêche bypass rate limiting et duplicate check | `create_or_get_conversation`, `send_private_message` (updates last_message_at) |
| `reviews` | INSERT, UPDATE, DELETE | Empêche bypass co-participation check. Immutable après création. | `create_review` |

Sans ces restrictions, un client peut contourner les fonctions et opérer directement via l'API REST, en bypassant toutes les validations.

### Messages d'erreur — pas de fuite d'information

Les messages d'erreur retournés au client ne doivent pas révéler de détails d'implémentation :
```sql
-- ❌ Révèle le mécanisme de protection :
RAISE EXCEPTION 'Status can only be changed via dedicated functions';
RAISE EXCEPTION 'Privileged columns can only be changed via dedicated functions';

-- ✅ Générique, pas de fuite :
RAISE EXCEPTION 'Operation not permitted';
```

Toutes les opérations non autorisées retournent le même message générique. Les détails sont dans les logs Postgres (côté serveur), pas dans la réponse client. Empêche un attaquant de comprendre les mécanismes de protection.

### PL/pgSQL — prévention injection SQL
Les paramètres de fonctions PL/pgSQL sont traités comme des valeurs bindées, pas comme du SQL — donc pas vulnérables à l'injection. **MAIS** l'utilisation de `EXECUTE` avec concaténation de string EST vulnérable :
```sql
-- ❌ JAMAIS — vulnérable à l'injection SQL :
EXECUTE 'INSERT INTO activities (title) VALUES (''' || p_title || ''')';

-- ✅ TOUJOURS — paramètres bindés, safe :
INSERT INTO activities (title) VALUES (p_title);

-- ✅ Si EXECUTE est nécessaire, utiliser les paramètres :
EXECUTE 'INSERT INTO activities (title) VALUES ($1)' USING p_title;
```
**Règle : ne jamais concaténer de paramètres client dans un EXECUTE.**

### Fonctions de création — never trust client values
Les fonctions Postgres de création (activités, messages, participations, etc.) n'acceptent que les champs modifiables par l'utilisateur dans leur signature. Les champs privilégiés sont hardcodés :
```sql
-- Exemple : création d'activité
CREATE FUNCTION create_activity(
  p_title TEXT, p_description TEXT, p_sport_id UUID, ...  -- champs utilisateur uniquement
) RETURNS UUID AS $$
  ...
  INSERT INTO activities (
    creator_id, status, created_at, title, ...
  ) VALUES (
    auth.uid(),      -- hardcodé depuis l'auth, pas du client
    'published',     -- hardcodé, pas du client
    NOW(),           -- hardcodé
    p_title, ...     -- du client
  );
```

### Politiques standard
```sql
-- Lecture : utilisateurs non suspendus, contenu non bloqué
AND creator.suspended_at IS NULL
AND creator_id NOT IN (
  SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
)

-- IMPORTANT pour wall_messages et private_messages :
-- Le filtre blocked_users doit porter sur user_id (auteur du message), pas creator_id
AND user_id NOT IN (
  SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
)

-- Écriture : uniquement le propriétaire
AND auth.uid() = user_id

-- Suppression : uniquement le propriétaire ou admin
AND (auth.uid() = user_id OR EXISTS (
  SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = TRUE
))
```

### Colonnes privilégiées — jamais modifiables directement par le client
Les colonnes suivantes ne sont JAMAIS modifiables via un UPDATE direct du client. Toute modification passe par des fonctions Postgres avec vérification d'autorisation intégrée.

**Table users :**
- `is_admin` — modifiable uniquement par un autre admin via fonction
- `tier` — modifiable uniquement via Stripe webhook / fonction admin
- `is_pro_verified`, `pro_verified_at` — modifiable uniquement via fonction admin
- `suspended_at` — modifiable uniquement via fonction admin
- `phone_verified`, `phone_verified_at` — modifiable uniquement via le flow de vérification Supabase Auth
- `accepted_tos_at`, `accepted_privacy_at` — modifiable uniquement via fonction `accept_tos` (set une fois). La fonction vérifie que la valeur est NULL avant de la setter — si déjà set, rejet. Le premier consentement est le seul juridiquement valable.
- `date_of_birth` — **immutable après création**. La fonction `set_date_of_birth` vérifie que la valeur est NULL avant de la setter — si déjà set, rejet. Empêche un utilisateur de modifier son âge pour contourner la vérification 18+.

**Colonnes user modifiables par le client :**
`display_name`, `avatar_url`, `bio`, `sports`, `levels_per_sport` — uniquement ces champs via UPDATE direct avec `auth.uid() = id`.

**Enforcement : trigger UNIQUE sur la table users** — approche **whitelist** (plus sûr que blacklist) :
```sql
CREATE FUNCTION handle_user_update() RETURNS TRIGGER AS $$
BEGIN
  -- Bypass pour fonctions autorisées
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := NOW();
    RETURN NEW;
  END IF;

  -- WHITELIST : forcer TOUTES les colonnes non-autorisées à leur ancienne valeur
  -- Toute nouvelle colonne ajoutée à la table est automatiquement protégée
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.date_of_birth := OLD.date_of_birth;
  NEW.is_admin := OLD.is_admin;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.suspended_at := OLD.suspended_at;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.push_token := OLD.push_token;
  NEW.subscription_status := OLD.subscription_status;
  NEW.stripe_customer_id := OLD.stripe_customer_id;

  -- Colonnes autorisées en UPDATE direct : display_name, avatar_url, bio, sports, levels_per_sport
  -- (pas listées ci-dessus = le client peut les modifier)

  -- Auto-update updated_at
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Pourquoi whitelist plutôt que blacklist :**
- Blacklist : chaque nouvelle colonne est modifiable par le client SAUF si on pense à l'ajouter au trigger. Oubli = faille.
- Whitelist : chaque nouvelle colonne est automatiquement protégée (forcée à OLD). Seules les colonnes explicitement NON listées sont modifiables.
- Le défaut sûr est "protégé". Pour rendre une colonne modifiable, il faut l'exclure explicitement de la whitelist.

**Trigger unique :** Ce trigger remplace `check_user_update` ET `update_updated_at` — un seul trigger par table élimine les dépendances d'ordre d'exécution entre triggers multiples.

Contraintes sur `display_name` :
- `CHECK (char_length(display_name) BETWEEN 2 AND 30)`
- Noms réservés interdits via fonction de mise à jour : "admin", "junto", "support", "moderator", "système", etc.

**`push_token`** — modifiable uniquement via une fonction dédiée (enregistrement push notification côté client). Jamais exposé dans les queries publiques (profil, activités, etc.).
**`subscription_status`** — modifiable uniquement via Stripe webhook Edge Function. Jamais modifiable par le client.
**`stripe_customer_id`** — modifiable uniquement via Stripe webhook Edge Function. Jamais modifiable par le client.

**Table activities :**
- `creator_id` — **immutable après création** (protégé par le trigger `handle_activity_update`)
- `status` — **jamais modifiable par UPDATE direct** (protégé par le trigger inconditionnellement). Transitions uniquement via fonctions Postgres SECURITY DEFINER :
  - Création → `published` (fonction de création)
  - `published` → `cancelled` (fonction d'annulation, créateur uniquement)
  - `published` → `expired` (cron automatique)
  - `published` → `in_progress` (cron automatique ou fonction)
  - `in_progress` → `completed` (cron automatique ou fonction)
- `invite_token` — **jamais modifiable par UPDATE direct** (protégé par le trigger). Régénération via fonction dédiée uniquement.

Voir le trigger `handle_activity_update` (section Verrouillage des champs d'activité) pour l'implémentation complète.

**Table participations :**
- `status` — INSERT par un utilisateur ne peut être que `pending`. Seul le créateur de l'activité (via fonction) peut mettre `accepted` ou `refused`.

**Table notifications :**
- INSERT interdit pour les utilisateurs. Seules les fonctions Postgres créent des notifications. L'utilisateur peut uniquement UPDATE `read_at` sur ses propres notifications.

**Table sports :**
- SELECT pour tous (y compris anon) — données de référence publiques
- INSERT / UPDATE / DELETE réservés aux admins uniquement
- Empêche l'injection de sports offensants ou la suppression de sports référencés

**Table activities :**
- Pas de DELETE policy — les activités sont annulées (status → cancelled), jamais supprimées directement. Seul CASCADE à la suppression utilisateur les retire.
- `invite_token UUID` — jamais exposé dans les queries de listing public. Accessible uniquement via fonction RPC dédiée pour les activités privées par lien.
- RLS `suspended_at` filter : appliqué sur la découverte (carte, liste) mais PAS sur l'historique (mes activités, profil) — les activités completed restent visibles dans l'historique des participants même si le créateur est suspendu.

**Table blocked_users :**
- INSERT uniquement avec `blocker_id = auth.uid()`. Un utilisateur ne peut bloquer qu'en son propre nom.
- DELETE uniquement avec `blocker_id = auth.uid()`. Seul le bloqueur peut retirer son propre blocage.

### Matrice RLS complète — toutes les tables, toutes les opérations

**Légende :** ✅ = policy existe | ❌ = pas de policy (opération interdite) | 🔧 = via fonction SECURITY DEFINER uniquement

#### `users`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Own row: full. Others: via `public_profiles` view | ❌ Trigger only | Own row, colonnes autorisées uniquement | ❌ Edge Function only |

#### `activities`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Discovery: published/in_progress, creator not suspended, not blocked. History: own participations. Private: via RPC + invite_token | 🔧 `create_activity` | `auth.uid() = creator_id` + lock trigger | ❌ Cancel only |

#### `sports`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| ✅ Everyone (incl. anon) | ❌ Admin only | ❌ Admin only | ❌ Admin only |

#### `participations`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Creator voit toutes pour son activité. Participant voit la sienne. Accepted voient les autres accepted. Anon: rien. | 🔧 `join_activity` | ❌ Via fonctions uniquement (accept, refuse, remove, leave) | ❌ Via `leave_activity` function |

```sql
-- SELECT policy participations
(
  auth.uid() = user_id  -- propre participation
  OR auth.uid() = (SELECT creator_id FROM activities WHERE id = activity_id)  -- créateur
  OR (status = 'accepted' AND EXISTS (
    SELECT 1 FROM participations p2
    WHERE p2.activity_id = participations.activity_id
    AND p2.user_id = auth.uid() AND p2.status = 'accepted'
  ))  -- co-participants acceptés
)
-- Filtre blocked_users : masque les participants bloqués de la liste
AND user_id NOT IN (
  SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
)
```

#### `wall_messages`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Accepted participants, blocked filtered on user_id | ❌ 🔧 `send_wall_message` | ❌ 🔧 Via fonction edit (auteur only, content + edited_at/deleted_at only) | ❌ Soft delete only |

#### `private_messages`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Sender or receiver, **bidirectional** block check (ni A→B ni B→A) | ❌ 🔧 `send_private_message` | ❌ 🔧 Via fonction edit (auteur only) | ❌ Soft delete only |

```sql
-- Bidirectional block check pour private_messages :
AND NOT EXISTS (
  SELECT 1 FROM blocked_users
  WHERE (blocker_id = auth.uid() AND blocked_id = other_user_id)
     OR (blocker_id = other_user_id AND blocked_id = auth.uid())
)
```

#### `notifications`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `auth.uid() = user_id` | ❌ 🔧 Functions only | ✅ `auth.uid() = user_id` (read_at — accepté pour MVP, user ne peut corrompre que ses propres données) | ❌ Pas de suppression |

#### `blocked_users`
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `blocker_id = auth.uid()` + admins | `blocker_id = auth.uid()` | ❌ Pas de champ modifiable | `blocker_id = auth.uid()` |

#### `conversations` (Sprint 7)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| `user_1 = auth.uid() OR user_2 = auth.uid()`, **bidirectional** block check | 🔧 Via fonction (rate limited, bidirectional block check) | ❌ `last_message_at` via `send_private_message` function | ❌ Pas de suppression |

#### `reviews` (Sprint 8)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| ✅ Public (sur profils), filtered par blocked_users | 🔧 Via fonction (check co-participation) | ❌ Immutable après soumission | ❌ Immutable |

#### `reports` (Sprint 8)
| SELECT | INSERT | UPDATE | DELETE |
|--------|--------|--------|--------|
| Reporter voit les siens + admins voient tout | ✅ Authenticated users | ❌ Admins only (status) | ❌ Personne |

### Realtime
Les souscriptions Supabase Realtime respectent le RLS. Vérifier que les politiques couvrent :
- Messages du mur : seuls les participants acceptés reçoivent les updates
- Messages privés : seuls l'expéditeur et le destinataire
- Changements de participation : seuls le créateur et le participant concerné

---

## Storage (fichiers)

### Bucket policies
Chaque bucket a ses politiques d'accès, équivalent RLS pour les fichiers :
```sql
-- Seul le propriétaire peut uploader dans son dossier
CREATE POLICY "Users upload own avatar"
ON storage.objects FOR INSERT
WITH CHECK (auth.uid()::text = (storage.foldername(name))[1]);
```

### Buckets — public vs private

| Bucket | Type | Raison |
|--------|------|--------|
| `avatars` | **Public** | Les avatars sont visibles par tous (y compris anon) sur les pins, popups, profils. **Path fixe** : `/avatars/{user_id}/avatar` — le nouveau fichier écrase l'ancien, empêche l'accumulation. |
| `pro-documents` | **Private** | Documents sensibles (SIRET, BPJEPS), lecture admin uniquement |

**Note :** Pas de bucket GPX — les fichiers GPX sont parsés côté client et les coordonnées stockées en PostGIS dans la table activities.

**Critique :** Un bucket **public** sert les fichiers sans vérification d'auth. Si `pro-documents` est créé en public par erreur, n'importe qui avec l'URL peut lire les documents personnels. Toujours vérifier le type à la création.

### Upload d'images
1. **Validation du type** : vérifier les magic bytes, pas juste l'extension
2. **Taille max** : 5MB pour les avatars
3. **Formats acceptés** : JPEG, PNG, WebP uniquement
4. **EXIF stripping** : supprimer les métadonnées GPS/device avant stockage

### Upload GPX
**Architecture :** Le GPX est parsé côté client, les coordonnées sont extraites et envoyées comme géométrie PostGIS dans la table `activities`. Le fichier GPX brut n'est PAS stocké dans un bucket. Cela élimine :
- La complexité des storage policies cross-table (GPX → activity → participations)
- Le risque de servir un fichier XML malveillant stocké
- Le bucket `gpx` entièrement

**Validation du parsing client :**
1. **Validation XML sécurisée** : parser avec un parseur qui désactive les entités externes (prévention XXE)
2. **Limite d'expansion** : protection contre les XML bombs (billion laughs)
3. **Taille max** : 10MB côté client avant parsing
4. **Résultat** : seules les coordonnées extraites sont envoyées au serveur, pas le XML brut

---

## Authentification & Sessions

### Secure Storage
- Tokens d'auth stockés avec `expo-secure-store`, jamais `AsyncStorage`
- `AsyncStorage` = plaintext sur le device

### Session
- Access token : 1 heure (auto-refresh)
- Refresh token : 30 jours
- Changement de mot de passe : invalide tous les refresh tokens (force re-login sur tous les devices)

### Logout
- **Avant `signOut()` :** appeler `update_push_token(null)` pour arrêter immédiatement les notifications push
- Sans cela, un device partagé/vendu continue de recevoir les notifications du précédent utilisateur jusqu'à ce qu'un nouveau login écrase le token

### Email
- Changement d'email : nécessite vérification de l'ancien ET du nouvel email
- L'ancien email reçoit une notification de changement

### Âge
- `date_of_birth` obligatoire à l'inscription
- Vérification : 18 ans minimum (`CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years')`)
- App qui met en contact des inconnus en plein air → obligation légale

---

## Profil — Matrice de visibilité des données

| Champ | Non connecté | Connecté | Soi-même |
|-------|-------------|----------|----------|
| display_name | Oui | Oui | Oui |
| avatar | Oui | Oui | Oui |
| bio | Oui | Oui | Oui |
| sports & niveaux | Oui | Oui | Oui |
| historique activités | Non | Titres + ville | Détail complet |
| email | Non | Non | Oui |
| téléphone | Non | Non | Oui |
| date_of_birth | Non | Non | Oui |
| created_at | Oui | Oui | Oui |

Cette matrice définit directement les politiques RLS sur la table `users`.

---

## Rate Limiting

### Messages (mur d'événement)
```sql
-- Max 5 messages par 10 secondes par utilisateur par activité
SELECT count(*) FROM wall_messages
WHERE user_id = auth.uid()
  AND activity_id = p_activity_id
  AND created_at > NOW() - INTERVAL '10 seconds';
IF count >= 5 THEN RAISE EXCEPTION 'Rate limited';
```

### Demandes de participation
```sql
-- Max 10 demandes par heure par utilisateur
SELECT count(*) FROM participations
WHERE user_id = auth.uid()
  AND created_at > NOW() - INTERVAL '1 hour';
IF count >= 10 THEN RAISE EXCEPTION 'Rate limited';
```

### Création d'activités
- Free tier : 4 par mois (business rule)
- Tous tiers : max 2 par jour (anti-spam)
- Appliqué dans la fonction Postgres de création
- **Advisory lock par user** pour prévenir la race condition sur le rate limit :
  ```sql
  PERFORM pg_advisory_xact_lock(hashtext(auth.uid()::text || '_create_activity'));
  ```
  Sérialise les créations concurrentes du même utilisateur. Sans cela, deux appels simultanés pourraient tous deux passer le rate limit check.

### Requêtes API (Supabase)
- Anonyme (sans auth) : 30 req/min
- Authentifié : 100 req/min
- Configuré dans le dashboard Supabase

### Recherche géo
- Rayon de recherche max : 100km
- Appliqué dans la fonction de recherche PostGIS

---

## Protection des données

### Stratégie de suppression par table

| Table | À la suppression utilisateur | FK behavior | Raison |
|-------|------------------------------|-------------|--------|
| participations | Supprimer | ON DELETE CASCADE | Aucune raison de conserver |
| activities (créées) | Annuler (via Edge Function) puis anonymiser | ON DELETE CASCADE | L'Edge Function annule les actives + notifie AVANT deleteUser. CASCADE nettoie le reste. |
| wall_messages | Anonymiser | ON DELETE SET NULL (user_id) | Préserver le contexte de conversation, affiche "Deleted User" |
| private_messages | Supprimer | ON DELETE CASCADE | Confidentialité des deux parties |
| conversations | Supprimer | ON DELETE CASCADE (user_1 et user_2) | La conversation n'a plus de sens avec un participant supprimé |
| notifications | Supprimer | ON DELETE CASCADE | Données personnelles |
| reviews (en tant que reviewer) | Anonymiser | ON DELETE SET NULL (reviewer_id) | La note reste sur le profil du reviewed, reviewer affiché "Deleted User" |
| reviews (en tant que reviewed) | Supprimer | ON DELETE CASCADE (reviewed_user_id) | Le profil n'existe plus, les reviews sont sans objet |
| reports | Conserver | Pas de FK CASCADE | L'historique de modération doit survivre |
| blocked_users | Supprimer | ON DELETE CASCADE | Plus pertinent si l'utilisateur n'existe plus |

### Wall messages — anonymisation
```sql
user_id UUID REFERENCES users(id) ON DELETE SET NULL
-- L'UI affiche "Deleted User" quand user_id IS NULL
```

### Consentement
- `accepted_tos_at TIMESTAMPTZ` — horodatage acceptation CGU
- `accepted_privacy_at TIMESTAMPTZ` — horodatage acceptation politique de confidentialité
- Présents dans le modèle user dès Sprint 1

---

## Modération

### Champs utilisateur
- `is_admin BOOLEAN DEFAULT FALSE` — pour les outils de modération
- `suspended_at TIMESTAMPTZ NULL` — suspension réversible (NULL = actif)

### Suspension
- Un utilisateur suspendu est invisible : ses activités, messages et profil sont filtrés par RLS
- Différent de la suppression : réversible, données préservées

### Tables de modération
- `blocked_users` : créée Sprint 1, affecte les politiques RLS sur toutes les tables
- `reports` : créée Sprint 8 avec l'UI de signalement. RLS :
  - INSERT : tout utilisateur authentifié
  - SELECT : reporter voit ses propres reports + admins voient tout
  - UPDATE : admins uniquement (status : pending → dismissed / actioned)
  - DELETE : personne (l'historique de modération doit survivre)

---

## Intégrité des données

### Contraintes UNIQUE et CHECK critiques

```sql
-- Participations : un seul enregistrement par user/activité
UNIQUE (user_id, activity_id)

-- Reviews : un seul avis par reviewer/reviewed/activité
UNIQUE (reviewer_id, reviewed_user_id, activity_id)
CHECK (reviewer_id != reviewed_user_id)
CHECK (rating BETWEEN 1 AND 5)

-- Conversations : une seule conversation par paire d'utilisateurs
UNIQUE sur paire ordonnée (user_1, user_2) — la fonction de création ordonne les IDs
CHECK (user_1 != user_2)

-- Activities
CHECK (max_participants BETWEEN 2 AND 50)
CHECK (starts_at > NOW()) -- à la création uniquement
CHECK (duration >= INTERVAL '15 minutes') -- empêche les activités instantanées
CHECK (char_length(title) BETWEEN 3 AND 100)
CHECK (char_length(description) <= 2000)
sport_id REFERENCES sports(id) ON DELETE RESTRICT -- empêche suppression d'un sport utilisé

-- Users
CHECK (char_length(display_name) BETWEEN 2 AND 30)
CHECK (char_length(bio) <= 500)

-- Messages (wall + private)
CHECK (char_length(content) BETWEEN 1 AND 2000)

-- Reviews
CHECK (char_length(comment) <= 1000)

-- Reports
CHECK (char_length(reason) BETWEEN 10 AND 1000)
```

### Colonnes `updated_at`
Les tables `users` et `activities` ont une colonne `updated_at TIMESTAMPTZ DEFAULT NOW()` mise à jour automatiquement par un trigger :
```sql
CREATE FUNCTION update_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```
Utilisé pour le cache invalidation (TanStack Query), la détection de données stales, et l'audit trail.

### Concurrent join protection
```sql
-- Fonction Postgres avec verrou de ligne
-- Vérifie d'abord que l'activité est joinable
SELECT status, max_participants INTO v_status, max_count
FROM activities WHERE id = p_activity_id FOR UPDATE;

IF v_status NOT IN ('published', 'in_progress') THEN
  RAISE EXCEPTION 'Activity is not joinable';
END IF;

SELECT count(*) INTO current_count
FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';

IF current_count >= max_count THEN RETURN FALSE;
```

### Verrouillage des champs d'activité
Après le premier participant accepté (hors créateur), les champs critiques sont verrouillés :
- Lieu (départ et rendez-vous)
- Date et heure
- Niveau requis
- Nombre de places max
- Mode de visibilité (empêche de passer en privé après que des participants aient trouvé l'activité sur la carte, et empêche de passer en private_link sans être Premium)

**Enforcement : Postgres trigger côté DB** (pas service layer — le service layer est côté client, bypassable via appel API direct) :
```sql
CREATE FUNCTION handle_activity_update() RETURNS TRIGGER AS $$
BEGIN
  -- Bypass pour fonctions autorisées (cancel, transition status, regenerate token)
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := NOW();
    RETURN NEW;
  END IF;

  -- INCONDITIONNELLES : colonnes jamais modifiables par le client
  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;

  -- CONDITIONNELLES : verrouillées quand des participants existent
  IF (SELECT count(*) FROM participations 
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location := OLD.location;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
  END IF;

  -- Auto-update updated_at
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```
**Même approche whitelist que users :** les colonnes protégées sont forcées à OLD. Le client ne peut modifier que les champs autorisés (title, description, sport_id, duration, meeting_point). Trigger unique — fusionne lock + updated_at.
**Note :** Les triggers se déclenchent sur TOUTES les opérations, y compris depuis les fonctions SECURITY DEFINER. Pour permettre aux fonctions autorisées de modifier le status et creator_id, utiliser une variable de session comme signal :

```sql
-- Dans la fonction autorisée (ex: cancel_activity) :
PERFORM set_config('junto.bypass_lock', 'true', true);  -- true = local to transaction
UPDATE activities SET status = 'cancelled' WHERE id = p_activity_id;

-- Dans le trigger check_activity_lock :
IF current_setting('junto.bypass_lock', true) = 'true' THEN
  RETURN NEW;  -- skip all checks
END IF;
```

Ce pattern garantit que seules les fonctions qui set le flag peuvent bypasser le trigger. Un client ne peut pas set cette variable car `set_config` est dans `pg_catalog` — non accessible via PostgREST/API REST.

**Règle : aucune fonction exposée publiquement ne doit appeler `set_config('junto.bypass_lock', ...)`**. Seules les fonctions internes (cron, triggers, fonctions appelées par d'autres fonctions) peuvent utiliser ce bypass.

### Modification d'activité — notification
Toute modification d'un champ (même non verrouillé, ex: description) déclenche une notification à tous les participants acceptés. Le participant peut alors décider de quitter l'activité.

### Quitter une activité — Postgres function
Le départ d'une activité passe par une fonction Postgres, pas un DELETE direct :
- **Verrouillage de ligne** : `SELECT ... FROM participations WHERE ... FOR UPDATE` — sérialise avec `remove_participant` pour éviter la race condition leave/remove
- Vérifie que le status actuel est `accepted` ou `pending` (pas `removed`)
- Vérifie que l'activité est `published` ou `in_progress`
- Direct DELETE sur participations bloqué par RLS
- Empêche un utilisateur `removed` de supprimer sa ligne et re-demander à rejoindre

### Transitions automatiques de statut (pg_cron ou Edge Function)
Job exécuté toutes les heures. Gère le cycle de vie complet :

```
published → in_progress   : quand starts_at <= NOW()
in_progress → completed   : quand starts_at + duration <= NOW()
                            → déclenche notification review aux participants
published → expired       : quand starts_at + 2h < NOW() (aucun participant n'a rejoint)
```

Empêche l'accumulation d'activités périmées sur la carte et garantit que les reviews sont déclenchées automatiquement.

### Deep links
- Tokens UUID v4 pour les activités privées par lien
- Non séquentiels, non devinables
- Validés côté serveur via RLS

---

## Configuration Supabase

### À faire au setup du projet
- [ ] Désactiver GraphQL (non utilisé)
- [ ] Restreindre l'accès direct à la base (IP whitelist pour le développement uniquement)
- [ ] Configurer le rate limiting API (30/min anon, 100/min auth)
- [ ] Configurer la durée de session (1h access, 30j refresh)
- [ ] Vérifier que le changement d'email nécessite la vérification des deux adresses
- [ ] Activer RLS sur chaque nouvelle table AVANT tout insert
- [ ] Verrouiller les redirect URIs OAuth : Google Cloud Console (uniquement le callback Supabase) + Supabase Auth Site URL et Additional Redirect URLs (uniquement le deep link scheme de l'app)
- [ ] Vérifier que la confirmation email est ACTIVÉE (empêche l'inscription avec un email non possédé)
- [ ] Configurer le mot de passe minimum : 8 caractères
- [ ] Vérifier qu'un statement timeout est configuré (empêche les queries pathologiquement coûteuses)

---

## Notifications push — contenu

### Règle
Les notifications apparaissent sur l'écran de verrouillage. Ne jamais inclure de contenu sensible :
```
❌ "Marie : On se retrouve chez moi, 14 rue de..."
✅ "Marie a envoyé un message dans Escalade Briançon"
```

---

## Sanitisation des inputs texte

### Règle
Tous les champs texte libre (titre, description, bio, messages, commentaires, raisons de signalement) sont nettoyés côté serveur via un trigger ou une fonction Postgres qui strip les tags HTML. Même si React Native n'a pas de DOM vulnérable, les données pourraient être rendues dans un contexte web futur (dashboard admin, partage, etc.).

---

## Anti-abus complémentaire

### Removal définitif
Un participant retiré d'une activité par le créateur ne peut pas être re-accepté pour la même activité. Le status `removed` est final. Empêche le cycling accept/remove qui bombarderait le participant de notifications.

### Blocage — directionnalité

Le blocage a un comportement **différent selon le contexte** :

| Contexte | Comportement |
|----------|-------------|
| Mur d'événement | **Unidirectionnel** — A bloque B → A ne voit plus les messages de B. B voit toujours les messages de A. (Évite les trous de conversation pour les autres participants) |
| Messages privés | **Bidirectionnel** — ni A ni B ne peut envoyer de message à l'autre. Création de conversation bloquée dans les deux sens. |
| Rejoindre une activité | **Unidirectionnel** — B ne peut pas rejoindre les activités de A (vérifié dans `join_activity`). A peut toujours rejoindre les activités de B. |
| Découverte (carte/liste) | **Unidirectionnel** — A ne voit pas les activités créées par B. B voit toujours les activités de A. |
| Liste des participants | **Unidirectionnel** — A ne voit pas B dans la liste, mais le compteur total reste exact (inclut les bloqués). Empêche l'affichage d'un utilisateur bloqué tout en préservant l'exactitude du compteur. |
| Reviews | **Unidirectionnel** — A ne voit pas les reviews écrites par B sur son profil. Mais la review de B compte dans la note moyenne de A. L'évaluation globale reste honnête, l'affichage individuel filtre les bloqués. |

### Rate limiting conversations
Max 10 nouvelles conversations privées par heure par utilisateur. Empêche le spam de masse via DM.

### Reviews — enforcement DB
Le reviewer ET le reviewed doivent être des participants acceptés de la même activité. Vérification dans la fonction Postgres de création de review. Empêche le review bombing par des comptes n'ayant jamais participé.

### Stripe webhook idempotency
Stocker les `event_id` Stripe traités. Ignorer les doublons. Empêche les attaques par replay et les doubles traitements légitimes.

**Ordre critique :** Traiter l'événement D'ABORD, stocker l'event_id ENSUITE. Si le traitement échoue et l'ID est déjà stocké, l'événement ne sera jamais retraité. En stockant après, un retry de Stripe trouve l'event_id absent et relance le traitement.

### Account enumeration
Supabase Auth configuré pour retourner des messages d'erreur uniformes (login et inscription). Un attaquant ne peut pas déterminer si un email est enregistré.

---

## Changement de tier — règles métier

### Premium → Free (downgrade)
- Les activités existantes (publiées, en cours) **restent actives** — pas d'annulation rétroactive
- Les activités privées par lien existantes conservent leur mode de visibilité
- La création de nouvelles activités est bloquée tant que le nombre d'activités actives (published + in_progress) dépasse 4/mois
- La création de nouvelles activités privées par lien est bloquée
- Le badge "Vérifié" est retiré du profil et des pins

### Pro → non-Pro (révocation)
- Le badge Pro est un **check display-time** basé sur `is_pro_verified` — pas stocké sur chaque activité
- Quand `is_pro_verified = false`, toutes les activités du user perdent automatiquement l'affichage "Sortie Pro" sans migration de données
- La vitrine Pro (liens, certifications) est masquée
- Les activités existantes restent actives en mode non-Pro

---

## Deep links — Android App Links (Sprint 8)

Pour le lancement public, utiliser des Android App Links (vérifiés par domaine, `https://junto.app/invite/{uuid}`) en plus ou à la place des custom scheme links (`junto://`). Les App Links sont cryptographiquement vérifiés — seule notre app peut les intercepter. Empêche le phishing par interception de liens.

---

## Suppression de compte — Edge Function

La suppression d'un compte utilisateur nécessite la suppression de l'entrée dans `auth.users`, ce qui requiert la clé `service_role`. Cette opération **ne peut pas se faire depuis le client**.

**Architecture :**
1. Le client appelle une Edge Function (pas une RPC Postgres)
2. L'Edge Function vérifie l'identité (`auth.uid()` du JWT)
3. **Avant la suppression :** annule toutes les activités `published` et `in_progress` du user (status → cancelled) et notifie tous les participants acceptés. Les activités `completed` et `expired` sont conservées (anonymisées par le CASCADE SET NULL).
4. Appelle `supabase.auth.admin.deleteUser(userId)` avec la clé `service_role`
5. La suppression de `auth.users` déclenche CASCADE sur `public.users` via FK
6. Les FK `ON DELETE CASCADE` et `ON DELETE SET NULL` sur chaque table exécutent la stratégie automatiquement
7. Retourne succès au client → redirect écran d'accueil

**Pourquoi l'étape 3 :** Sans annulation préalable, CASCADE supprimerait silencieusement les activités en cours — les participants perdraient leur événement sans être notifiés. L'annulation + notification protège les autres utilisateurs.

**Atomicité :** L'étape 3 (annulation) est réversible si l'étape 4 (deleteUser) échoue — les activités sont juste annulées, ce qui est un état valide. Pas de données corrompues en cas de partial failure.

---

## Bootstrap admin

Le premier utilisateur admin est créé **manuellement via le SQL Editor du dashboard Supabase** :
```sql
UPDATE users SET is_admin = TRUE WHERE email = 'admin@junto.app';
```
Jamais via l'app. Documenté dans DECISIONS.md.

---

## Ce document est la référence sécurité
Toute question de sécurité se réfère à ce document. Mis à jour au fil du développement.
