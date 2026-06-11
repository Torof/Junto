# Junto — Checklist de test de release manuelle

> Rescopé au walk #1 (2026-06-11) : remplace les "tests e2e automatisés" comme gate pré-launch ; la suite automatisée (Maestro/Detox) viendra post-launch. À dérouler sur un device Android réel avant chaque release store (build production) — ~30 minutes. Cocher ou noter l'échec + commit de fix.

## Compte & auth
- [ ] Signup email neuf → email de confirmation reçu → confirmation → onboarding (DOB 18+, CGU) → arrivée carte
- [ ] Signup avec DOB < 18 ans → refusé
- [ ] Logout → login → session persiste après kill de l'app
- [ ] Reset password : demande → email → lien → nouveau mot de passe → re-login
- [ ] Lien invite (`getjunto.app/invite/...`) depuis un chat externe → ouvre l'app directement (App Links)

## Carte & découverte
- [ ] Mode visiteur (sans compte) : carte + pins activités visibles
- [ ] Les 3 types de pins se distinguent au premier regard (UA teardrop / RA carte / PP cercle)
- [ ] Filtres : sport, date, niveau, rayon — la carte ET le drawer réagissent
- [ ] Décocher "Pros" → PP **et** RA disparaissent ensemble
- [ ] Les 5 styles de carte : pins lisibles sur chacun (satellite inclus)

## Cycle de vie activité
- [ ] Créer une activité (4 étapes, avec GPX + objectif) → pin sur la carte
- [ ] Créer avec `starts_at` > 6 mois → erreur propre
- [ ] Rejoindre depuis le 2e compte (public direct + mode approval : demande → accepter)
- [ ] Mur : envoyer/éditer/supprimer un message, realtime sur l'autre device
- [ ] Transport : proposer des places, demander un siège, accepter → conversation seedée
- [ ] Gear : déclarer, s'attribuer
- [ ] Annuler l'activité → participants notifiés (pending inclus) → disparaît de "En attente"
- [ ] Demande pending sur activité qui se termine → disparaît de "En attente" (mig 00263)

## Présence (le flux critique)
- [ ] T-2h : notification pre-warning reçue
- [ ] Fenêtre de validation : feedback géo sur l'écran activité, validation auto par géofence app fermée (si OS le permet) OU
- [ ] QR : créateur affiche → participant scanne → confirmé
- [ ] Peer review post-activité : voter → reliability score bouge

## Messagerie
- [ ] DM : envoyer, répondre (reply), éditer, supprimer ; realtime des deux côtés
- [ ] Envoyer ~5 messages rapides d'affilée → AUCUN popup de rate limit (mig 00264)
- [ ] Blocage : bloquer l'autre compte → DM impossible, pins de ses activités disparus de la carte
- [ ] Partage de trace GPX dans un DM → préviewable, importable

## Pro
- [ ] Page pro : vitrine, galerie (upload/réordonner/supprimer), catalogue
- [ ] Créer un offering → pin RA sur la carte au bon endroit ; cap 12 atteint → erreur propre
- [ ] Avis : poster (étoiles seules + étoiles+texte), modifier, supprimer ; réponse du pro ; push `review_received` reçu ; moyenne mise à jour sur le héros
- [ ] Signaler un avis → visible dans la modération admin

## RGPD & compte
- [ ] Toggle "Partager les rapports de plantage" : ON → event arrive dans Sentry ; OFF → plus rien
- [ ] Suppression de compte : profil/photos/messages purgés, messages de mur anonymisés, retour à l'écran visiteur
- [ ] getjunto.app : /legal/privacy, /legal/terms, /legal/mentions (infos entité remplies), /legal/account-deletion répondent

## Régressions connues à re-vérifier
- [ ] Clavier : DM + chat d'activité + composer d'avis + report — l'input reste visible au-dessus du clavier
- [ ] Org-tab transport : s'affiche correctement (bug 2026-05-10, résolu par mig 00230 — confirmer une fois)
