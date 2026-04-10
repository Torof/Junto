# Junto — Mode de Fonctionnement

## Rôles

### Scott (Maître d'œuvre)
- Valide chaque décision avant tout développement
- Teste et inspecte chaque livrable
- Définit les priorités
- Prend toutes les décisions finales produit et techniques

### Claude Code (Développeur)
- Propose des solutions techniques
- Écrit le code sur validation explicite de Scott
- Signale les risques, alternatives et problèmes en amont
- Documente ce qui est construit
- Ne code jamais sans validation explicite

---

## Règles absolues

- **Jamais de code sans validation explicite de Scott**
- Je propose, Scott dispose
- Si je vois un problème ou un risque → je le soulève AVANT de coder, jamais après
- Une feature à la fois — pas de développement en bloc
- Chaque sprint se termine par une validation de Scott avant de passer au suivant

---

## Workflow de développement

### Pour chaque feature
Voir `CLAUDE.md` → "Before Any Feature" pour le checklist complet (lecture docs, proposition, validation, code, commit, test, merge).

### Pour chaque sprint
1. On définit ensemble les features du sprint
2. On les développe une par une
3. Scott valide le sprint complet
4. On tag le sprint (v0.x.0)
5. On passe au sprint suivant

---

## Git & Versioning

### Branches
- Une branche par feature : `sprint-1/auth`, `sprint-1/mapbox-base`
- `main` toujours stable et validé par Scott
- Merge vers `main` uniquement après validation explicite

### Commits
- **Format :** Conventional Commits avec double `-m`
  - Premier `-m` : description concise (titre)
  - Second `-m` : détail si nécessaire
- **Langue :** Anglais
- **Fréquence :** Après chaque unité logique fonctionnelle
- **Préfixes :** `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`
- **Exemple :**
  ```bash
  git commit -m "feat: add Google login" -m "Uses Supabase Auth with OAuth redirect, handles token refresh and session persistence"
  ```

### Tags
- Un tag par sprint validé : `v0.1.0` (Sprint 1), `v0.2.0` (Sprint 2), etc.
- Permet de revenir à l'état de n'importe quel sprint

### DECISIONS.md
- Log des décisions techniques non évidentes
- Format : décision + pourquoi + alternative considérée
- Mis à jour au fil du développement

---

## CI/CD

### GitHub Actions
- **Push sur n'importe quelle branche :** lint + typecheck
- **Merge vers main :** lint + typecheck
- **Tag sprint (v0.x.0) :** EAS Build (preview + production APK)
- **Trigger manuel :** EAS Build (pour test mid-sprint par Scott)

### npm audit
- Intégré au pipeline CI
- Échoue si vulnérabilité high/critical détectée

### OTA Updates
- EAS Update configuré dès le départ
- Permet de pousser des correctifs JS sans passer par le Play Store

### Build
- Expo custom dev build (requis pour Mapbox)
- Scott teste sur son téléphone Android via dev build

---

## Structure du projet

```
/app                — Expo Router : routes file-based (les fichiers = les écrans)
/src
  /components       — composants réutilisables
  /store            — Zustand stores (UI state uniquement)
  /services         — appels Supabase et APIs externes
  /hooks            — custom hooks
  /types            — types TypeScript
  /utils            — fonctions utilitaires
  /constants        — couleurs, tailles, configs, design tokens
  /assets           — images, icônes, fonts
  /i18n             — fichiers de traduction (fr.json, en.json)
/supabase
  /migrations       — fichiers SQL versionnés
  /seed.sql         — données de test
```

---

## Dépendances

- **Packages standards** (zustand, i18next, etc.) : ajoutés sans demander
- **Packages inhabituels ou lourds** : validation de Scott requise avant installation
- **`package-lock.json`** toujours commité pour builds reproductibles

---

## Gestion des bugs
- Bug trouvé pendant les tests → on le corrige avant de passer à la feature suivante
- Bug critique (crash, data loss) → priorité absolue, on arrête tout

---

## Références
- Conventions de code, stack quick reference → `CLAUDE.md`
- Stack technique détaillée → `TECH_STACK.md`
- Modèle de sécurité → `SECURITY.md`

---

## Ce document est la référence processus
En cas de doute sur le workflow, les rôles, ou le git, ce document fait foi.
Pour les conventions de code et la sécurité, voir les documents référencés ci-dessus.
