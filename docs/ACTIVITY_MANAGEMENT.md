# Junto — Gestion des activités

## Vue d'ensemble
Règles et flux de gestion du cycle de vie d'une activité — de la création à la clôture, incluant la gestion des participants et les annulations.

---

## Cycle de vie d'une activité

```
Création → Publication → Demandes → Acceptations → Jour J → Clôture
```

---

## Création

### Prérequis
- Compte utilisateur actif
- Numéro de téléphone vérifié (obligatoire pour la première création)
- Abonnement Premium si plus de 4 activités créées dans le mois (comptes Free)

### Champs de création
- Type de sport
- Titre et description
- Niveau requis
- Nombre de places
- Point de départ (pin sur carte)
- Point de rendez-vous (pin sur carte — peut différer du départ)
- Tracé de l'itinéraire (dessiné à la main ou import GPX)
- Date et heure
- Durée estimée
- Mode de visibilité (4 options)

### Les 4 modes de visibilité
| Mode | Visible sur carte | Accès |
|------|------------------|-------|
| Public | ✅ | Direct |
| Sur acceptation | ✅ | Validation créateur requise |
| Privé par lien | ❌ | Lien = accès direct |
| Privé par lien + validation | ❌ | Lien + validation créateur |

---

## Gestion des participants

### Demandes de participation
- Le créateur reçoit une notification pour chaque demande
- Il peut consulter le profil du demandeur — score de présence, badges, historique
- Il accepte ou refuse

### Capacité
- Une fois le nombre de places atteint → plus de demandes possibles
- Le créateur peut augmenter le nombre de places si nécessaire

### Exclusion d'un participant
- Le créateur peut exclure un participant accepté avant le jour J
- Le participant exclu est notifié
- L'exclusion n'impacte pas le score de présence du participant

---

## Annulation d'une activité

### Annulation unilatérale par le créateur
- Possible à tout moment
- Déclenche un malus sur le score de présence du créateur
- Tous les participants sont notifiés immédiatement

### Annulation par vote du groupe
- Le créateur initie un vote "annuler l'activité ?"
- Tous les participants acceptés reçoivent une notification et peuvent voter
- Délai de réponse : 2-3 heures maximum
- **Si 2/3 des participants votent pour annuler** → activité annulée, aucun malus pour personne
- **Si moins de 2/3** → activité maintenue, le créateur doit honorer ou annuler unilatéralement avec malus

### Annulation par un participant
- Un participant peut se retirer de l'activité à tout moment
- Plus de 12h avant → annulation propre, pas de pénalité sur le score de présence
- Moins de 12h avant → pénalité sur le score de présence

---

## Clôture d'une activité

### Processus
1. Activité passée → statut automatiquement "terminée"
2. Le créateur confirme les présences des participants
3. Les scores de présence sont mis à jour
4. Les participants reçoivent une invitation à attribuer des badges (48h)
5. L'activité est archivée et accessible en lecture seule dans les historiques

---

## Backlog V2
- Malus progressif selon la proximité de l'annulation avec la date de l'activité
- Liste d'attente automatique si l'activité est complète
- Possibilité de reporter une activité sans annuler
- Modération des activités signalées comme inappropriées
