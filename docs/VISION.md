# Junto — Vision long terme

Ce fichier capture les directions stratégiques et les features signature potentielles. Pas une roadmap, pas un backlog. Un cap, un horizon.

---

## v2 — Carte enrichie : événements + spots

### L'idée

La carte Junto v1 affiche des **événements** (activités ponctuelles, datées, sociales). La v2 ajoute une couche de **spots** : lieux permanents et riches en information (canyons, sites d'escalade, départs de rando, déco parapente, itinéraires de ski de rando, etc.).

### Deux types de pins

| Type | Description | Cycle de vie |
|------|-------------|--------------|
| **Événement** | "Escalade samedi 10h, cherche partenaires" | Éphémère, lié à une date |
| **Spot** | "Canyon de la Carança" | Permanent, accumulé dans le temps |

### Pourquoi c'est puissant pour les sports outdoor

- Les pratiquants pensent par lieu, pas par événement ("je vais à Céüse ce weekend"). Le lieu est le nom commun, l'événement est l'instance.
- Les **photos** trouvent enfin une maison durable : ancrées au spot, accumulées par toutes les activités qui s'y passent.
- À la création d'une activité, "choisir un spot existant" auto-remplit la localisation et hérite du contexte (photos, beta, conditions).
- Chaque spot devient une base de connaissance vivante : matos requis, parking, saison idéale, qui y est allé récemment, dernières conditions.
- Junto devient le *Wikipedia + Meetup* des spots outdoor d'une région.

### Pourquoi c'est lourd

- C'est un **changement de direction produit**, pas une feature. Le mental model des users change : "trouver des activités" → "explorer des spots et des activités".
- **Cold start** : il faut peupler les spots. Trois sources possibles : admin curé (lent), submission users avec validation (modération lourde), import OSM/POI (qualité variable).
- **Encombrement carte** : événements + spots dans la même zone → besoin d'un filtrage UI fort.
- **Risque de scope explosion** : pages spot = commentaires, ratings, conditions reports, edit history, etc. Rabbit hole sans fond.
- **Deux value props dans une app** = plus dur à expliquer en 5 secondes à un nouveau user.

---

## Stratégie : partenariat plutôt que compétition

### Le contexte

Sortir le modèle spots en mode "build everything ourselves" met Junto en compétition directe avec des communautés établies depuis des décennies :
- **descentecanyon** (canyoning)
- **camptocamp** (alpinisme, ski de rando)
- **climbing topos papier + apps** (escalade)
- **Paragliding Earth** (parapente)
- **Visorando, AllTrails** (randonnée)

Ces apps ont :
- Des années de contenu curé
- Des communautés émotionnellement attachées
- Une réputation déjà construite

Les battre sur leur terrain est extrêmement coûteux et probablement perdant.

### L'angle wu wei : aller avec le courant

Plutôt que de construire un concurrent, **partenariat ou intégration via API** :

- Junto apporte ce que ces apps n'ont pas : **carte géolocalisée d'activités sociales + alertes en temps réel + couche people-to-people**.
- Ces apps apportent ce que Junto n'a pas : **contenu topo riche, photos historiques, communauté experte, beta accumulée**.

Symbiose. Le user Junto voit le topo descentecanyon enrichi de son canyon préféré, descentecanyon récupère du trafic et de la visibilité auprès des organisateurs d'activités.

### Conditions pour activer cette stratégie

1. **Junto v1 doit avoir de la traction** — sans audience, on n'a rien à offrir.
2. **Approche les communautés en partenaire**, pas en demandeur. Le pitch : "vous avez le contenu, on a la couche sociale + carte. Pourquoi pas combiner ?"
3. **Commencer par les communautés ouvertes / API-friendly** (camptocamp est sous CC, OSM, certaines plateformes ont déjà des APIs publiques).
4. **Identité Junto reste claire** : Junto n'est pas le successeur des topos. C'est le complément social qui leur manquait.

---

## Principes guides pour la suite

1. **Garder la simplicité de la value prop v1** tant que la traction n'est pas là. *"Find outdoor sports partners near you"* — c'est ça, point.
2. **Ne pas construire de fonctionnalités qui mettent Junto en compétition frontale avec un acteur établi**. Soit on innove sur un terrain vide, soit on partenariat.
3. **Prioriser l'asymétrie d'avantage** : ce que Junto fait mieux/différemment que tout le monde (carte + alertes + people layer outdoor), pas ce que tout le monde fait déjà bien.
4. **wu wei** : adapter, partenariser, créer du gagnant-gagnant. Ne jamais forcer une feature contre l'écosystème existant.
