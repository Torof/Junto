# Junto — UX / UI

## Identité visuelle

### Ton général
Aventure et adrénaline, sans excès. "Outdoor sérieux" — puissant mais pas agressif.
Référence vestimentaire : Arc'teryx, Patagonia — premium, aventure, confiance.

### Mode
**Dark mode par défaut** — cohérent avec l'énergie outdoor et la lisibilité sur carte.

---

## Palette de couleurs

### Couleurs principales
| Rôle | Couleur | Hex |
|------|---------|-----|
| Fond principal | Bleu nuit | `#0D1B2A` |
| Surfaces secondaires / Cards | Bleu moyen | `#1B3A5C` |
| CTA / Pins / Accents / Actions | Orange vif | `#F4642A` |

### Couleurs neutres
| Rôle | Couleur | Hex |
|------|---------|-----|
| Texte principal | Blanc cassé | `#F5F5F0` |
| Texte secondaire / Placeholders | Gris clair | `#8A9BB0` |

### Couleurs sémantiques
| Rôle | Couleur | Hex |
|------|---------|-----|
| En cours / Accepté / Succès | Vert | `#2ECC71` |
| Annulé / Refusé / Erreur | Rouge | `#E74C3C` |
| En attente / Bientôt | Jaune | `#F39C12` |

---

## Typographie
- **Titres :** Montserrat Bold — puissant, lisible, moderne
- **Corps :** Inter Regular — propre, universel, excellent rendu mobile

---

## UX Principles

### Valeur immédiate
L'utilisateur voit des activités autour de lui sans créer de compte. Pas d'écran intermédiaire — directement sur la carte.

### Friction progressive
Chaque étape de friction est justifiée par une action concrète :
- Voir → aucune friction
- Rejoindre → créer un compte
- Créer → vérifier son numéro

### Double vue découverte
- **Vue carte** (défaut) — exploration visuelle, pins géolocalisés
- **Vue liste** — recherche filtrée style Leboncoin

### 3 niveaux d'information
Pin → Pop-up → Page complète. On dévoile progressivement selon l'intérêt de l'utilisateur.

---

## Flows UX détaillés

### Flow Onboarding visiteur
```
Ouverture app
    → Détection pays via IP
    → Carte centrée sur la région
    → Bandeau "Activer la localisation"
        → Accepte → carte recentrée précisément
        → Refuse → champ recherche par ville
    → Activités visibles immédiatement
```

### Flow Inscription
```
Tap "Rejoindre" sur une activité (ou bouton connexion)
    → Écran connexion
        → Google (1 tap)
        → Email + mot de passe
    → Nom généré aléatoirement (modifiable)
    → Accès immédiat à l'app
    → Action initiale reprise automatiquement
```

### Flow Participant — Rejoindre une activité
```
Carte principale
    → Tap sur pin (niveau 1)
    → Pop-up rapide (niveau 2)
    → Tap "Voir l'activité"
    → Page événement complète (niveau 3)
        → Activité publique → bouton "Rejoindre" → accès direct au mur
        → Activité sur acceptation → bouton "Demander à rejoindre"
            → Notification créateur
            → Accepté → notification → accès au mur
            → Refusé → notification
```

### Flow Créateur — Créer une activité
```
Bouton "+" flottant sur la carte
    → Si pas de compte → inscription
    → Si première création → vérification numéro de téléphone
    → Étape 1 : Sport + titre + description + niveau + places
    → Étape 2 : Point de départ (pin carte) + point RDV + tracé + date/heure + durée
    → Étape 3 : Mode de visibilité
    → Étape 4 : Récap → Publier
    → Activité publiée → visible selon mode de visibilité choisi
```

### Flow Créateur — Gérer les demandes
```
Notification : "X veut rejoindre votre activité"
    → Page événement mode gestion
    → Voir profil du demandeur
    → Accepter → X accède au mur + notification envoyée
    → Refuser → notification envoyée à X
```

---

## Composants UI clés

### Pin sur la carte
- Icône sport + couleur selon statut
- Orange = disponible
- Vert = en cours
- Gris = complet / passé
- Badge "Pro" pour les sorties professionnelles

### Pop-up activité
- Card flottante en bas d'écran au tap sur pin
- Photo / icône sport, titre, date, niveau, places, avatar créateur
- Bouton "Voir l'activité" → page complète

### Card activité (vue liste)
- Même info que pop-up en format liste scrollable

### Bouton CTA principal
- Orange `#F4642A`, border-radius généreux, Montserrat Bold

### Badge statut
- Pill coloré selon statut sémantique
- En cours (vert), Bientôt (jaune), Complet (gris), Pro (orange avec icône)

### Barre de navigation
- 4 onglets en bas : Carte, Mes activités, Messagerie, Profil
- Icône active en orange, inactive en gris clair
