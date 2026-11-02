# Audit pro — novembre 2026

Audit de sécurité de la partie pro (migrations 00554-00577, fonctions serveur d'agenda, écrans pro et parcours client), lancé le 2026-11-02 : 6 relecteurs indépendants, chaque point reproduit sur la base en transaction annulée par un vérificateur. 30 points, tous confirmés, aucun critique ni grave. Puis la suite de tests (fichiers 17 à 21, 2026-11-02) a ajouté les points « T-… ».

Les identifiants sont ceux des tests (`known` dans `supabase/tests/*.test.sql`) : un test marqué `xfail` décrit le comportement voulu et échoue tant que le point n'est pas corrigé. Corrigé = le test passe → retirer l'identifiant du test et cocher ici.

Recommandations validées par Scott le 2026-11-02. **Statut 2026-11-02 : tout est corrigé** (migrations 00578-00579, fonctions d'agenda redéployées, app en preview) sauf ce qui est marqué ci-dessous. Suite complète : 4 007 vérifications, 0 échec ; seule faille connue restante : CALENDAR-7-PLATFORM.

**Restent ouverts** : CALENDAR-7 (schéma `net` propriété de Supabase — révocation sans effet de notre côté ; non exposé par l'API) ; VITRINE-2 (lot séparé, après B8) ; T-WORDING (libellé des notifications sur plusieurs jours) ; SESSIONS-3 / BOOKINGS-2 / BOOKINGS-3 / SESSIONS-5 corrigés dans le code mais non testables en un seul bloc (courses).

## Base de données

| Id | Gravité | Point | Correctif prévu | Test |
|---|---|---|---|---|
| SESSIONS-1 / GRANTS-1 | moyenne | La confirmation « minimum atteint » ne retombe jamais (inscription puis désinscription) | Retirée quand le total repasse sous le minimum ; « Maintenir » reste ; baisse du minimum → reconfirmation | 19 |
| SESSIONS-2 | moyenne | Annulation auto d'une sortie acceptée après le rappel J-2 ; le « Participants min » existant devient annulation auto sans choix | Agir après le rappel = « Maintenir » ; case `auto_cancel` désactivée par défaut | 19 |
| SESSIONS-4 | faible | Un compte peut remplir une date fixe (taille de groupe déclarée) | ≤ 6 personnes par inscription, ≤ 3 inscriptions à venir par pro | 19 |
| SESSIONS-5 | faible | Résa manuelle rattachée à une date en cours d'annulation (course) | Relire le statut de la date sous verrou | commentaire (course) |
| SESSIONS-6 | faible | La suspension d'un pro laisse ses dates fixes et confirmations | Fermer dates + confirmations, plages commencées incluses | 19 |
| SESSIONS-3 / BOOKINGS-2 / BOOKINGS-3 | faible | Ordre des verrous inversé → interblocage possible (cron du jour annulé en entier) | Même ordre partout ; cron sortie par sortie | commentaires (course) |
| BOOKINGS-1 | moyenne | Le pro peut écrire indéfiniment à ses anciens clients | Refus 7 jours après la fin (`junto.outing_closed`) ; demande en attente passée refusée | 17 |
| BOOKINGS-4 | faible | Notification d'annulation nommant un client bloqué | Notification sans nom | 17 |
| BOOKINGS-5 | doc | Le motif d'annulation apparaît dans l'aperçu du push (comme tout message privé) | Corriger SECURITY.md | — |
| VITRINE-1 | moyenne | Photos de la communauté sans réservation, non signalables, remplaçables | Réservation terminée exigée ; signalement + retrait admin ; pas de remplacement de fichier | 20 (et 06 l. 222-229 à adapter) |
| VITRINE-2 | faible | L'admin ne peut pas retirer le contenu de la page pro | Lot séparé, après fermeture de B8 | — |
| VITRINE-3 | faible | Avis possible pendant une sortie de plusieurs jours | Fin de sortie exigée | 20 |
| VITRINE-4 | faible | Couverture hors galerie | Photo de la galerie exigée | 20 |
| CALENDAR-4 | faible | Lien d'export et import ressuscités après désinscription puis retour | Supprimés à la désinscription | 18 |
| CALENDAR-5 | faible | Résultat d'import périmé après changement d'adresse | `calendar_import_apply` reçoit l'adresse lue | 18 |
| CALENDAR-7 | faible | Fonctions réseau (pg_net) exécutables par les clients (non exposées) | Révoquer | 18 |
| GRANTS-2 | faible | ~214 fonctions sans `extensions` dans search_path | Balayage + test socle | 00 |
| GRANTS-3 | faible | Droits par défaut : lecture visiteur sur les futures tables | Révoquer anon (+ adapter M5 dans 10) | 00 |
| GRANTS-4 | faible | Visiteur : accès au schéma private et à 3 fonctions internes | Révoquer | 00 |
| CLIENT-1 (base) | moyenne | Fiches vides `{}` comptées comme remplies ; `[]` refusé | Compter les fiches remplies ; accepter `[]` | 17 |

## Fonctions serveur (corrigées le 2026-11-02, non testables en SQL)

CALENDAR-1 (calendrier piégé bloquant l'import pour tous), CALENDAR-2 (récurrences anciennes ignorées), CALENDAR-3 (fuseaux partagés entre pros), CALENDAR-6 (pliage des lignes ICS) — commit `6e2c4a0e`, à déployer avec la 00578.

## App (corrigés le 2026-11-02, commits `03afb58a`, `f12bc890`)

CLIENT-1/2 (place des participants dans les fiches), CLIENT-3 (cache des places), CLIENT-4 (sorties commencées la veille), CLIENT-5 (note du client sur une date fixe), CLIENT-6 (double tap).

## Trouvés par la suite de tests

| Id | Point | Correctif prévu | Test |
|---|---|---|---|
| DB-WP-1 | `set_gpx_trace_waypoints` : un appel refusé ne compte pas dans la limite (même défaut que 00483) | Compter l'appel avant la validation | 21 |
| DOC-WAYPOINTS | `set_gpx_trace_waypoints` absent de SECURITY.md | Documenter la chaîne | 13 |
| T-CAL-DATE | Une date impossible fait échouer tout `calendar_import_apply` sans erreur enregistrée | Ignorer les dates invalides | — |
| T-CAL-NAMES | `calendar_feed_bookings` renvoie les noms même avec « masquer les noms » (masqués par la fonction serveur seulement) | Masquer aussi en base | — |
| T-CAL-TIER | `calendar_import_targets` ne vérifie pas `tier = 'pro'` | Ajouter le contrôle | — |
| T-CAL-UNPLUG | Débrancher l'import compte dans la limite de 10 changements par jour | Ne pas compter le débranchement (adapter AG10 dans 18) | — |
| T-OUTING-PENDING | `cancel_outing` avec motif écrit aussi aux clients seulement en attente (ouvre un fil) | Motif aux clients acceptés seulement | — |
| T-COOLDOWN | Un client dont la demande a été refusée par une date fixe posée ne peut pas s'y inscrire pendant 1 h | Pas de délai ni de comptage quand le refus vient du pro | — |
| T-REVOKED-CANCEL | Doc : « un pro révoqué garde l'annulation, comme `cancel_outing` » — mais `cancel_outing` exige un pro validé | Aligner (à trancher) | — |
| T-SESSION-CONF | Les confirmations d'une date annulée ne sont jamais supprimées (sans effet aujourd'hui) | Supprimer à l'annulation | — |
| T-BYPASS | `cascade_block_cleanup` laisse `junto.bypass_lock` actif jusqu'à la fin de la transaction | Le refermer | — |
| T-WORDING | Refus / annulation d'une résa sur plusieurs jours : seul le jour de départ est cité | Citer la plage | — |
