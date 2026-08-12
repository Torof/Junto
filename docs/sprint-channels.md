# Sprint — Canaux de discussion (Discovery « gros », v2 activée)

**Statut : conception validée (Scott 2026-08-09), PHASE 1 CONSTRUITE (sur preview).**

Phase 1 livrée (2026-08-09) : mig 00381 (table channels + widening name CHECK) · 00382 (channel_bans + create/join/leave/search) · 00383 (rename/remove_member/close + delete_message ext + read-only trigger) · 00384 (hub + get_channel) · 00385 (get_channel_members). Client : `channels.tsx` (liste), `create-channel.tsx` (form + dédup), `conversation/[id]` (vue canal : en-tête, join-gating, lecture seule si fermé, sheet animateur rename/close/membres+retrait), hub + menu « Canaux ». i18n FR+EN complet. **Reste = phase 2** (proposer une sortie + surfaçage carte).

Active la brique parkée du PLAN (« Discovery gros = canaux ouverts + propositions de sortie, façon Summeet, distincts des groupes privés »). Le type `conversations.type='channel'` était **réservé** (mig 00353) — on construit dessus, on ne recrée pas de système.

## Concept
Un **canal** = une conversation `type='channel'` **ouverte** (on rejoint librement, sans être contact), **persistante**, cadrée par un **thème = lieu + sport** (ex. « Rando · Briançonnais »). Les membres discutent, demandent, retrouvent, et (phase 2) proposent des sorties. **Distinct des groupes privés** (contacts only, fermés).

Risque n°1 = **fragmentation** (canaux vides/doublons = ville fantôme au cold-start). Le modèle concentre les gens dans peu de canaux trouvables.

## Décisions (Scott 2026-08-09)
1. **Création structurée lieu + sport, avec dédup** : à la création, si un canal ouvert équivalent existe (même sport + base < ~15 km) → proposer *Rejoindre* / *Créer quand même* (`force`).
2. **Trouver = liste cherchable** (espace « Canaux », filtres sport + lieu via Photon). Pas d'épingles sur la carte en v1.
3. **Modération = créateur animateur + signalement** : le créateur peut renommer / retirer un message / retirer un membre / fermer. Signalement global existant. Blocage = masque perso.

## Garde-fous (cadrage « table-stakes, pas maximaliste »)
- Les canaux **complètent** la carte, ne sont pas la porte d'entrée (comme Discovery = secondaire).
- **Pas de push par message** (badge / mentions seulement — un canal ouvert est bruyant).
- **Pas de Slack-creep** : pas de fils, rôles multiples, réactions en v1.

## Modèle de données
- `conversations.type='channel'` : nom, membres, messages, realtime, blocage.
- **`channels`** (1:1) : `conversation_id PK`, `sport_key`, `base GEOGRAPHY(POINT,4326) + base_label`, `description`, `created_by`, `closed_at`, `created_at`. RLS **SELECT ouvert authenticated** (canal public — son lieu EST son identité, ≠ dispos Discovery qui cachent la base), écritures SECURITY DEFINER only, GIST sur base, whitelist trigger.

## Fonctions + chaînes d'autorisation (toutes REVOKE anon)
- **`create_channel(sport, lng, lat, label, name, description, force)`** : auth → non suspendu → sport actif → lieu valide → longueurs → cap (≤5 créés ouverts/user + cap/jour) → dédup si `!force` (renvoie l'existant + `duplicate`) → crée conversation+channels + créateur membre.
- **`join_channel(id)`** : auth → non suspendu → conv channel non fermée → pas bloqué par le créateur → pas déjà membre → insère membre (join ouvert).
- **`leave_channel(id)`** : auth → membre → retire.
- **`search_channels(query, sport, near_lng, near_lat, radius)`** : auth → non suspendu → canaux ouverts filtrés + `member_count` + `is_member`, triés proximité/activité.
- **Modération créateur** : `rename_channel`, `remove_channel_member`, `close_channel` ; retrait message = extension `delete_message` (créateur retire tout message de SON canal).
- **Poster/lire** : réutilise `send_message` + `get_conversation_messages` (gatés appartenance).
- **Hub** : `get_my_conversations` étendu au `type='channel'` (identité = nom + lieu·sport).

## Écrans
- `app/(auth)/channels.tsx` — « Canaux » : recherche (sport + lieu) + liste + « Créer un canal ». Entrées : menu + hub.
- `app/(auth)/create-channel.tsx` — form (sport, lieu, nom, description) + gestion doublon.
- Vue canal = réutilise `conversation/[id]` + en-tête canal (nom, membres, Rejoindre/Quitter, menu animateur).

## Découpage
- **Phase 1 (socle)** : table + create/join/leave/search/modération + liste + form + vue canal + hub. Pas de push par message.
- **Phase 2** : « Proposer une sortie » depuis le canal (crée l'activité → poste la carte) + surfaçage contextuel carte.

## Défauts
Nom « Canaux » · dédup même sport + base < 15 km · cap création 5/user.
