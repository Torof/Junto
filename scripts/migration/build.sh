#!/usr/bin/env bash
# Phase B — apply the prepared build files to the NEW (rehearsal) project, in
# order, each in its own psql session and single transaction; stop at the first
# error. Run by Scott: the connection string is typed at the prompt only.
#   bash scripts/migration/build.sh
set -uo pipefail
WORK="${JUNTO_MIG_WORK:-$HOME/junto-migration}"
BUILD="$WORK/build"
LOGS="$WORK/build-logs"
[ -d "$BUILD" ] || { echo "Pas de $BUILD — la préparation n'est pas faite."; exit 1; }
command -v psql >/dev/null || { echo "psql introuvable : sudo apt install postgresql-client"; exit 1; }
echo "Colle l'adresse « Session pooler » du NOUVEAU projet (répétition), mot de passe inclus."
read -rsp "Adresse : " NEW_DB_URL; echo
case "$NEW_DB_URL" in *lvjlthzdydzatcvwwriu*) echo "C'est l'ANCIEN projet — arrêt, rien n'a été fait."; exit 1;; esac
rm -rf "$LOGS"; mkdir -p "$LOGS"
export PGCONNECT_TIMEOUT=15
for f in "$BUILD"/*.sql; do
  name=$(basename "$f" .sql)
  printf '%-40s ' "$name"
  if psql "$NEW_DB_URL" -X -v ON_ERROR_STOP=1 --single-transaction -f "$f" > "$LOGS/$name.log" 2>&1; then
    echo "ok"
  else
    echo "ÉCHEC (rien de ce fichier n'est appliqué) — voir $LOGS/$name.log"
    unset NEW_DB_URL
    echo "Dis-moi « build échoué » : je lis le journal."
    exit 1
  fi
done
unset NEW_DB_URL
echo "Construction terminée. Dis-moi « build fait » et donne-moi la référence du projet."
