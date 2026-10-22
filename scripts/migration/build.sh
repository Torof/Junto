#!/usr/bin/env bash
# Phase B — apply the prepared build files to the NEW (rehearsal) project, in
# order, each in its own psql session and single transaction; stop at the first
# error. Run by Scott; the password is typed at its own prompt only.
#   bash scripts/migration/build.sh <new-project-ref>
set -uo pipefail
umask 077
OLD_REF=lvjlthzdydzatcvwwriu
NEW_REF="${1:-}"
[[ "$NEW_REF" =~ ^[a-z0-9]{20}$ ]] || { echo "Usage : bash scripts/migration/build.sh <référence du nouveau projet>"; exit 1; }
[ "$NEW_REF" != "$OLD_REF" ] || { echo "C'est la référence de l'ANCIEN projet — arrêt."; exit 1; }
WORK="${JUNTO_MIG_WORK:-$HOME/junto-migration}"
BUILD="$WORK/build"
LOGS="$WORK/build-logs"
[ -d "$BUILD" ] || { echo "Pas de $BUILD — la préparation n'est pas faite."; exit 1; }
grep -q "$NEW_REF" "$BUILD/60_reference_data.sql" || { echo "Les fichiers ont été préparés pour un autre projet — arrêt."; exit 1; }
command -v psql >/dev/null || { echo "psql introuvable : sudo apt install postgresql-client"; exit 1; }
echo "Colle l'adresse « Session pooler » du NOUVEAU projet ($NEW_REF), telle quelle (avec [YOUR-PASSWORD])."
read -rp "Adresse : " URL
case "$URL" in *"postgres.$NEW_REF"*) ;; *) echo "Cette adresse n'est pas celle du projet $NEW_REF — arrêt, rien n'a été fait."; exit 1;; esac
URL=$(printf '%s' "$URL" | sed -E 's#^(postgres(ql)?://[^:/@]+)(:.*)?@([^@]*)$#\1@\4#')
read -rsp "Mot de passe de la base (ne s'affiche pas) : " PGPASSWORD; echo
export PGPASSWORD PGCONNECT_TIMEOUT=15
rm -rf "$LOGS"; mkdir -p "$LOGS"
for f in "$BUILD"/*.sql; do
  name=$(basename "$f" .sql)
  printf '%-40s ' "$name"
  if psql "$URL" -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=default --single-transaction -f "$f" > "$LOGS/$name.log" 2>&1; then
    echo "ok"
  else
    echo "ÉCHEC (rien de ce fichier n'est appliqué) — voir $LOGS/$name.log"
    unset PGPASSWORD
    echo "Dis-moi « build échoué » : je lis le journal."
    exit 1
  fi
done
unset PGPASSWORD
echo "Construction terminée. Dis-moi « build fait »."
