# Junto — Définition Produit

## Les deux rôles utilisateur
Tout utilisateur connecté est à la fois potentiellement créateur et participant. Ce ne sont pas deux rôles fixes — c'est contextuel. Le même profil, avec des capacités qui se débloquent selon le niveau de vérification et l'abonnement.

---

## Les 3 tiers

### Free
- Rejoindre des activités : illimité
- Créer des activités : 4 par mois maximum
- Fonctionnalités de base

### Premium
- Rejoindre des activités : illimité
- Créer des activités : illimité
- Activités privées par lien
- Mise en avant sur la carte
- Badge vérifié
- Profil enrichi

### Pro (Professionnel vérifié)
- Tout le Premium
- Badge "Guide Professionnel Vérifié" — validé manuellement par Junto sur présentation de documents (SIRET, carte professionnelle, BPJEPS, brevet d'État, etc.)
- Vitrine professionnelle complète : liens externes (site, WhatsApp, Instagram), diplômes et certifications, spécialités, zones géographiques
- Historique des sorties organisées
- Avis des participants
- Paiement géré entièrement hors app — Junto est vitrine uniquement, pas intermédiaire financier
- Sur les pins et pop-ups : badge distinctif "Sortie Pro" visible par tous

---

## Les 4 modes de visibilité d'une activité

| Mode | Visible sur carte | Accès |
|------|------------------|-------|
| Public | ✅ | Direct — accès immédiat au mur |
| Sur acceptation | ✅ | Demande → validation créateur → accès au mur |
| Privé par lien | ❌ | Lien partagé = accès direct au mur |
| Privé par lien + validation | ❌ | Lien partagé + validation créateur → accès au mur |

**Règle universelle :** Le mur d'événement est accessible uniquement par les participants acceptés, quel que soit le mode de visibilité.

---

## Les 3 niveaux d'information d'une activité

### Niveau 1 — Le pin sur la carte
Visible par tous (visiteurs inclus)
- Icône du sport
- Titre court
- Heure de départ
- Places restantes

### Niveau 2 — Le pop-up rapide
Au tap sur le pin, visible par tous
- Sport + titre
- Date et heure
- Lieu de départ
- Niveau requis
- Places restantes
- Nom et photo du créateur
- Bouton "Voir l'activité"

### Niveau 3 — La page événement complète
- **Sans compte / non accepté :** infos complètes + description, bouton "Rejoindre" déclenche création de compte
- **Avec compte, non accepté :** peut envoyer une demande de participation
- **Avec compte, accepté :** accès au mur, chat, infos privées de coordination

---

## Création d'une activité — Champs

- Type de sport (sélection dans liste avec icônes)
- Titre de l'activité
- Description
- Niveau requis
- Nombre de places
- Point de départ (pin sur carte)
- Point de rendez-vous (pin sur carte — peut différer du départ)
- Tracé de l'itinéraire (dessiné à la main ou import GPX)
- Date et heure
- Durée estimée
- Mode de visibilité (4 options)

---

## Vérifications progressives pour créer

| Action | Prérequis |
|--------|-----------|
| Rejoindre une activité | Compte (email ou Google) |
| Créer une activité | Compte + numéro de téléphone vérifié |
| Créer plus de 4 activités/mois | Abonnement Premium |
| Badge Pro | Abonnement Pro + validation manuelle Junto |

---

## Profil utilisateur

- Photo (optionnelle)
- Nom (généré aléatoirement à l'inscription, modifiable)
- Bio
- Sports pratiqués et passions (pas que sportives)
- Niveau par sport
- Historique des activités passées (liste cliquable → page archivée en lecture seule)
- Profil public et accessible à tous

---

## Onboarding

### Visiteur (sans compte)
1. Ouverture app → détection pays via IP → carte centrée sur la région
2. Bandeau discret : "Activer la localisation pour voir les activités près de toi"
3. Activités visibles immédiatement — valeur directe
4. Si refus géoloc → champ de recherche par ville

### Inscription membre
1. Google ou Email
2. Nom généré aléatoirement (modifiable plus tard)
3. Photo vide — profil complétable à tout moment
4. Accès immédiat à l'app

### Devenir créateur
- Au moment de la première création → vérification numéro de téléphone obligatoire

### Géolocalisation
- Participant → optionnelle (fallback : recherche par ville)
- Créateur → obligatoire

---

## Règles métier importantes

- Un visiteur sans compte peut : voir la carte, voir les pins, voir les pop-ups, voir les pages événement (lecture seule)
- Un visiteur sans compte ne peut pas : rejoindre, créer, accéder au mur, voir les profils détaillés
- Le mur est toujours réservé aux participants acceptés
- Le créateur d'une activité est automatiquement participant accepté
- Une activité Pro affiche clairement son caractère professionnel et payant sur le pin et le pop-up
- Les paiements pour activités Pro se font entièrement hors app

---

## Messagerie privée
- Entre utilisateurs, indépendante du mur d'événement
- Non prioritaire pour le MVP
- À prévoir dans l'architecture dès le départ pour éviter refactoring

---

## App Map complète

### Zone publique (sans compte)
- Carte principale
- Vue liste des activités
- Pop-up rapide (niveau 2)
- Page événement (niveau 3) — lecture seule
- Profil utilisateur public — lecture seule
- Écran inscription / connexion
- Recherche par ville

### Authentification
- Connexion Google / Email
- Inscription + nom aléatoire
- Vérification numéro de téléphone (au moment de créer)

### Navigation principale (connecté) — 4 onglets
1. Carte
2. Mes activités
3. Messagerie
4. Profil

### Carte & Découverte
- Carte principale avec pins et filtres
- Vue liste
- Pop-up rapide
- Page événement complète
- Mur de l'événement
- Profil d'un autre utilisateur

### Création d'activité (flow en 4 étapes)
- Étape 1 : Sport et infos de base
- Étape 2 : Lieu et temps
- Étape 3 : Visibilité et places
- Étape 4 : Récap et publication

### Mes activités
- Liste activités créées
- Liste activités rejointes
- Gestion des demandes en attente (côté créateur)
- Page événement en mode gestion (côté créateur)

### Messagerie
- Liste des conversations
- Conversation privée

### Profil
- Mon profil public
- Édition du profil
- Historique des activités
- Paramètres
- Demande de compte Pro

### Paramètres
- Gestion abonnement (Free / Premium / Pro)
- Notifications
- Confidentialité
- Déconnexion / suppression du compte
