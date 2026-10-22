# Répétition générale de la migration

But : construire une copie de la base sur un **projet Supabase jetable**, prouver qu'elle est identique à l'ancienne, noter tout ce qui casse, corriger, recommencer jusqu'à ce que tout passe du premier coup — puis supprimer ce projet. L'ancien projet n'est jamais modifié : il est seulement lu.

**Les mots de passe restent chez toi.** Les deux seules commandes qui en ont besoin (export et construction) te demandent l'adresse de connexion à l'écran, sans l'afficher ni l'enregistrer. Tout le reste (vérifications, préparation, preuves, tests), je le fais avec ta connexion Supabase déjà active, sans mot de passe.

Dossier de travail : `~/junto-migration/` (hors du dépôt, rien n'y est commité).

## Ce que tu fais, dans l'ordre

**1. Installer l'outil PostgreSQL** (une fois)

```bash
sudo apt install postgresql-client
pg_dump --version
```

Ubuntu fournit la version 18 : elle sait lire une base 17. La répétition dira si elle convient aussi pour reconstruire.

**2. Créer le projet jetable** dans le tableau de bord Supabase : même organisation, **région UE (Francfort ou Paris)**, **Postgres 17**. Envoie-moi seulement sa **référence** (les 20 caractères dans son adresse), pas le mot de passe.

**3. Exporter l'ancien projet** (lecture seule)

Dans le tableau de bord de l'**ancien** projet : bouton **Connect** → **Session pooler** → copier l'adresse, et remplacer `[YOUR-PASSWORD]` par le mot de passe de la base.

```bash
cd ~/Desktop/Junto
bash scripts/migration/export.sh
```

Colle l'adresse quand elle est demandée (elle ne s'affiche pas). Dis-moi « export fait ».

**4. Attendre mon feu vert** : je vérifie le nouveau projet, je prépare les fichiers de construction et je les relis.

**5. Construire sur le projet jetable**

Même chose que l'étape 3, mais avec l'adresse « Session pooler » du **projet jetable** :

```bash
cd ~/Desktop/Junto
bash scripts/migration/build.sh
```

Le script s'arrête au premier problème (rien de l'étape en cause n'est appliqué). Dis-moi « build fait » ou « build échoué » : je lis les journaux dans `~/junto-migration/build-logs/`.

**6. Recommencer si besoin** : si quelque chose doit être corrigé, le plus propre est de supprimer le projet jetable et d'en recréer un (étape 2), puis de refaire l'étape 5 — l'export reste valable tant que l'ancien projet ne change pas.

**7. Fin** : quand la preuve est complète, tu supprimes le projet jetable.

## Ce que je fais (pour mémoire)

| Étape | Commande | Mot de passe |
|---|---|---|
| Vérifier le projet neuf | `npx supabase db query --experimental --linked -f scripts/migration/precheck-new.sql` depuis `~/junto-migration/link` | non |
| Préparer | `python3 scripts/migration/prepare.py <référence>` | non |
| Prouver la structure | `JUNTO_DB_WORKDIR=~/junto-migration/link node scripts/catalog-diff.mjs snapshot > new.json` puis `node scripts/catalog-diff.mjs old.json new.json` | non |
| Tests | `JUNTO_DB_WORKDIR=~/junto-migration/link JUNTO_DB_REF=<référence> npm run test:db` | non |

`~/junto-migration/link` est un dossier qui contient seulement `supabase/.temp/project-ref` (la référence du projet jetable) : les commandes ci-dessus visent alors ce projet, et le dépôt reste lié à l'ancien.
