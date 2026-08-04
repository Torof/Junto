# Junto — Plan de construction (par axes)

> **Phase de pré-construction assumée (2026-08-04).** Après une phase « je fonce »
> (tests, nom, domaine) qui a servi à concrétiser et à apprendre, on passe à une
> planification délibérée, **sans précipitation**. On prépare en amont (docs,
> discussions, brainstorm, maquettes, recherche) *avant* de reconstruire.

## Comment on travaille

Chaque item passe par le même pipeline :

> **Explorer** (discuter / brainstorm) → **Étudier** (recherche / concurrents / grand public) → **Maquetter** → **Décider** (doc / décision) → **Construire**.

On ne code qu'**après validation** ; pour toute fonction DB, la chaîne d'autorisation est présentée et validée avant code (cf. `CLAUDE.md`).

## Positionnement (transversal) — le miroir de Summeet

Le concurrent le plus proche est **Summeet** (trouver des partenaires de sorties en montagne, France+CH, communauté déjà là ; mais **zéro pro**, orga légère, et « on s'y perd, trop d'infos » — notre **anti-exemple UX**). AtClub = matcheur de partenaires (loin de nous).

- **Summeet mène par les partenaires** ; l'orga est légère.
- **Junto mène par la carte + l'organisation profonde** (transport · matériel · présence · fiabilité · **pros**) ; le partenariat est **secondaire**.
- Identité en une phrase : **« Junto, c'est trouver ET organiser des sorties. »** Les partenaires sont un **moyen** (Discovery), pas le titre.
- Histoire d'acquisition en 3 couches : **pros** (offre toujours là, besoin grand public, seedable → moteur d'entrée) · **activités entre pairs** (le cœur) · **Discovery** (bootstrap secondaire).
- Boussole design : **joli, moderne, mais simple et accessible** — on en fait plus *dessous* en restant lisible *dessus*.

---

## Les axes

### A · Pro / acquisition grand public
- **Objectif** : faire des pros le **moteur d'entrée** grand public (offre toujours sur la carte, besoin concret mal servi par les offices de tourisme, familles/touristes/débutants).
- **Statut** : **déjà construit** (vitrines, offres, pins, avis). Reste = **go-to-market + polish**, pas du build.
- **Questions ouvertes** : comment seed l'offre (recruter guides/écoles Hautes-Alpes) ? confiance côté grand public (afficher qualif/vérif, contact/réservation ultra-simple) ? lien avec la monétisation (pros = 1er paywall probable).
- **Backlog** : recrutement pros locaux · polish flow découverte/contact d'un pro pour non-initiés.

### B · Messagerie / hub chat  — **[AXE ACTIF]**
- **Objectif** : remonter le chat au **standard attendu** (table-stakes), le **centraliser** et le rendre **vivant**, sans rien retirer de l'activité.
- **Statut** : **design validé en maquettes** (2026-08-04), non construit. Spec → `docs/sprint-messaging.md`.
- **Décision ouverte structurante** : refonte **présentation** (agréger les 3 sources) **vs données** (modèle de conversation unifié).
- **Reste à faire** : vérifier « inviter depuis une sortie existante » + l'invitation reçue contre leurs écrans réels · assembler « créer une sortie depuis le chat » · trancher le fork présentation/données.

### C · Positionnement & marque
- **Objectif** : figer le positionnement « miroir de Summeet » ; trancher le **renommage**.
- **Statut** : positionnement clair (ci-dessus) ; **nom rouvert** (Junto abandonné — cf. `DECISIONS.md` 2026-07-29 géocoding n'a rien à voir ; le nom : direction **coordination**, ex. *Kordina*, à confirmer + check domaine/marque). Logo actuel gardé pour l'instant.
- **Questions ouvertes** : nom final + domaine + marque · quand rebrand (pré-lancement = le moins cher).

### D · Découverte (partenaires)
- **Objectif** : trouver des partenaires **où qu'on soit** — **secondaire**, bootstrap cold-start.
- **Statut** : **design décidé** (`docs/sprint-discovery.md`), non construit. « Oui mais secondaire » (menu + entrée contextuelle carte, jamais la porte d'entrée). Backend ~60 % (00072).
- **v2 à refondre** : Discovery « gros » = **canaux ouverts + propositions de sortie** (au-delà du simple « dispos »). Parké.

### E · Recherche & retours grand public
- **Objectif** : aller chercher le grand public, poser des questions, structurer les retours.
- **Statut** : à lancer. Étude concurrents faite (Summeet, AtClub).
- **Backlog** : questions structurées par axe · dogfooding testeurs.

### F · Préparation lancement
- Nom / domaine / emails / fiche store. **Dé-priorisé** (pas pressé). Dépend de l'axe C (nom).

### G · Durcissement / sécurité
- **Largement fait** (audits 2026-07-27/28, migrations 00344-00349). Invariants dans `SECURITY.md` + mémoire.

---

## État d'avancement (2026-08-04)
Axe **B (messagerie)** en cours de cadrage/maquettes. Prochaine reprise : points 1-3 de l'axe B (voir `docs/sprint-messaging.md` § Prochaines étapes).
