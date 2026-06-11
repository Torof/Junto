# Junto — Procédure de réponse aux incidents (violation de données)

> SOP RGPD Art. 33/34 — créé à l'audit prod 2026-06-11. Junto est opéré en solo : cette procédure est volontairement courte et exécutable par une seule personne sous stress. La relire une fois par trimestre.

## Contact

- Canal de signalement : **contact@getjunto.app** (mentionné dans la privacy policy)
- Autorité : **CNIL** — notification en ligne via <https://www.cnil.fr/fr/notifier-une-violation-de-donnees-personnelles>

## 1. Détection — où regarder

| Source | Quoi | Où |
|---|---|---|
| Sentry | erreurs anormales, patterns d'abus | sentry.io (ingest DE) |
| Supabase Logs | requêtes anormales, erreurs auth, volumétrie | Dashboard → Logs (vérifier la rétention du plan : Free = 1 jour, Pro = 7 jours, à confirmer) |
| Supabase Auth | connexions suspectes, vagues de signups | Dashboard → Authentication |
| Signalement externe | email d'un utilisateur / chercheur | contact@getjunto.app |

## 2. Qualification (dans l'heure)

Répondre par écrit (notes horodatées, même brouillonnes) :
1. **Quoi** : quelles données sont concernées ? (emails, DOB, positions, messages, photos…)
2. **Combien** : nombre d'utilisateurs touchés (requêtes SQL de comptage — les garder)
3. **Comment** : vecteur (clé fuitée, faille RLS, compte admin compromis, dépendance…)
4. **En cours ?** : la fuite est-elle stoppée ou active ?

**Risque pour les personnes ?** Si les données exposées peuvent causer un préjudice (positions géographiques ! emails + DOB, messages privés) → présomption OUI.

## 3. Containment immédiat

Selon le vecteur, dans l'ordre de brutalité croissante :
- Rotation de la clé compromise (anon key : Dashboard → Settings → API ; service_role idem ; secrets EAS : `eas env:update`)
- REVOKE/désactivation de la fonction ou policy fautive (`supabase db push` d'une migration corrective)
- Suspension du/des comptes attaquants (`admin_suspend_user`)
- Pause de l'API : Dashboard → Settings → pause project (extrême — app morte, mais fuite stoppée)

## 4. Notification CNIL — 72h chrono depuis la prise de connaissance

- Obligatoire sauf si « peu probable que la violation engendre un risque » (notes de qualification = la justification, dans les deux sens)
- Formulaire en ligne CNIL ; une notification initiale incomplète sous 72h vaut mieux qu'une complète hors délai (compléments possibles ensuite)
- Contenu : nature de la violation, catégories et volumes, conséquences probables, mesures prises

## 5. Notification des utilisateurs — si risque élevé

- Canal : email (via Supabase Auth/SMTP) + bandeau in-app si pertinent
- Contenu : ce qui s'est passé, quelles données, ce que Junto a fait, ce que l'utilisateur doit faire (changer son mot de passe…), contact
- Langage clair, pas de minimisation

## 6. Post-mortem (sous 2 semaines)

- Écrire le déroulé dans `docs/` (date, vecteur, timeline, impact, correctifs)
- Corriger la racine (migration, audit ciblé de la classe de faille — cf. les patterns SECURITY.md)
- Mettre à jour cette procédure si elle a frotté

## Registre

Tenir la liste des incidents (même mineurs / sans notification) ici :

| Date | Résumé | Notifié CNIL ? | Post-mortem |
|---|---|---|---|
| — | — | — | — |
