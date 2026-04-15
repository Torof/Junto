# Junto — Flux Jour J

## Vue d'ensemble
Système complet pour le jour de l'activité — de la coordination au point de rendez-vous jusqu'au calcul du score de présence et l'attribution des badges.

---

## Avant le départ

### Partage de position en temps réel
- Tous les participants acceptés peuvent voir la position des autres sur la carte
- Actif uniquement le jour de l'activité, dans une fenêtre temporelle définie (ex: 2h avant le départ)
- Permet de se retrouver facilement au point de rendez-vous entre inconnus

### Alerte de no-show
- Si un participant n'a pas confirmé sa présence 30 minutes avant le départ → notification automatique envoyée à tous
- Le créateur peut décider d'attendre ou de partir sans lui

---

## Au départ — Confirmation de présence

### Principe
Chaque participant confirme "je suis là" via un bouton dans l'app. La confirmation est validée uniquement par géolocalisation.

### Validation géolocalisée
- L'app vérifie que le téléphone est physiquement dans un rayon défini autour du point de rendez-vous
- Rayon par défaut : 200 à 500 mètres
- En zone reculée ou montagne : rayon élargi jusqu'à 1km possible
- Le créateur peut ajuster le rayon lors de la création de l'activité
- Si hors rayon → confirmation impossible, bouton désactivé
- Empêche les confirmations frauduleuses depuis chez soi

---

## Après l'activité — Confirmation finale

### Rôle du créateur
- Le créateur confirme définitivement les présences de chaque participant
- Cette confirmation finale déclenche le calcul et la mise à jour du score de présence de chacun
- En cas de désaccord entre la géoloc et la réalité terrain → la confirmation créateur prime

### Attribution des badges
- Après la confirmation finale → invitation envoyée à tous les participants pour attribuer des badges de réputation
- Optionnel, pas obligatoire
- Fenêtre d'attribution : 48h après la fin de l'activité

---

## Résumé du flux

```
J-30min   → Alerte si participant non confirmé
Heure H   → Partage de position actif
Au RDV    → Bouton "je suis là" + validation géoloc
Après     → Confirmation créateur → score de présence mis à jour
+48h      → Invitation attribution badges
```

---

## Double validation de présence
1. **Géoloc au départ** — vérification automatique par l'app
2. **Confirmation créateur à la fin** — validation humaine finale

Ce double système rend la triche très difficile et garantit l'intégrité du score de présence.

---

## Backlog V2
- Historique de position partageable post-activité (tracé du groupe)
- Confirmation de présence par QR code en alternative à la géoloc (zones sans réseau)
- Notification au créateur si un participant est très en retard sur le trajet
