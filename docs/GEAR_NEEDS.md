# Matériel nécessaire — spec

**Statut : conçu le 2026-07-09 (session Scott × Claude), maquette validée : en attente, dev : non planifié.**
Remplace conceptuellement l'ancienne feature « gear requests » (parkée, résidus DB retirés en mig 00194) — mais ce N'EST PAS elle : modèle plus petit, sans demandes ni prêts.

## Le principe en une phrase

**Junto ne juge jamais, Junto compte.** Le groupe déclare ses besoins ; Junto affiche la soustraction `besoin − apporté`.

## Pourquoi l'ancienne approche a échoué (et pourquoi celle-ci tient)

L'ancienne posait le problème comme « le système doit savoir ce qui manque » → jugement métier impossible (corde 60m pour 6 ? 15 dégaines pour une L à 17 ? → IA, tables par sport, subjectivité). L'inversion : **le jugement reste dans le groupe** (qui le fait déjà sur WhatsApp : « il nous faut 2 cordes, qui prend ? ») ; Junto ne fait que rendre la liste persistante et comptable.

## Règles du modèle

1. **Besoins collaboratifs.** Tout **participant accepté** (créateur inclus, sans rôle spécial — l'organisateur n'est pas un guide, il peut être le moins expérimenté du groupe) peut ajouter / modifier / retirer un besoin. Non-participants : lecture seule (même gating que le matériel actuel).
2. **Deux types de quantité :**
   - **Absolue** : « 2 cordes 60m » (pour le groupe).
   - **Par personne** : « 1 casque /pers » → besoin effectif = `taux × nb participants acceptés`, recalculé en continu quand le groupe change. (Seule règle « maligne » : une multiplication, pas un moteur.)
3. **Trois états, calcul trivial** (côté client, à partir des besoins + des apports existants `activity_gear`) :
   - ✓ **Couvert** : apporté ≥ besoin
   - ◐ **Partiel** : 0 < apporté < besoin (affiché « 12/18 »)
   - **À prévoir** : apporté = 0 → bouton **« Je l'apporte »** (ouvre le flux de contribution existant, quantité restante préremplie)
4. **Opt-in de fait.** Zéro besoin déclaré → l'onglet est identique à aujourd'hui (déclaratif pur). Aucune friction pour la sortie tranquille.
5. **Aucune coercition.** États purement visuels : pas de blocage, pas de notification de manque (v1), pas de rappel. La page informe, le groupe décide.

## Garde-fous (validation de saisie, jamais de jugement métier)

- **Catalogue d'abord** : besoins choisis dans le même catalogue typé que les apports ; texte libre possible (même sanitisation que le reste).
- **Plafond bête** : quantité 1–99 ; max ~30 besoins par activité (rate-limit anti-bruit).
- Le rapprochement besoin ↔ apport se fait par `catalog_key` quand présent, sinon par nom normalisé (même logique que l'agrégation actuelle).
- Litiges (« 47 dégaines pour 30 m ») : autocorrection sociale — tout est visible, tout participant corrige, le mur tranche. Le pire cas de la feature (un chiffre absurde, bénin) reste meilleur que le pire cas du statu quo (la 2ᵉ corde oubliée, dangereux).

## Hors périmètre (différences avec la feature parkée de 00194)

- Pas de « demandes » d'objet, pas de flux prêt/emprunt, pas d'auto-décrément, pas de notifications, pas de chat par objet.

## Esquisse technique (à affiner AVANT dev — chaîne d'autorisation à présenter à Scott)

- **Table** `activity_gear_needs` : `id, activity_id (FK CASCADE), name text, catalog_key text NULL, quantity int CHECK 1–99, per_person bool DEFAULT false, created_by (FK SET NULL), created_at/updated_at`. UNIQUE (activity_id, catalog_key/nom normalisé). RLS ENABLE + FORCE ; SELECT : participants acceptés + créateur ; **écritures uniquement via fonctions SECURITY DEFINER** (à ajouter à la liste « no direct client writes » de CLAUDE.md).
- **Fonctions** `upsert_gear_need`, `remove_gear_need` — chaîne d'autorisation : `auth.uid()` non nul → non suspendu → participant accepté ou créateur → activité active → sanitisation nom + plafonds. Erreurs sensibles génériques ; plafonds en `junto.<code>`.
- **Client** : couverture calculée côté client (aucun calcul serveur) ; « Je l'apporte » → éditeur d'item existant.

## Questions ouvertes

- **Attribution** « ajouté par X » sur chaque besoin : sobre ou pas du tout ? (v1 penche : pas du tout, le mur régule.)
- Libellé de section : « Matériel nécessaire » / « Besoins du groupe ».
- Faut-il un point discret sur l'onglet Matériel quand il reste du « à prévoir » ? (v1 : non.)
