#!/usr/bin/env bash
# Phase A — export the OLD project's structure + reference data (read-only).
# Run by Scott in his own terminal: the connection string (with its password)
# is typed at the prompt, never stored, never printed.
#   bash scripts/migration/export.sh
set -euo pipefail
WORK="${JUNTO_MIG_WORK:-$HOME/junto-migration}"
mkdir -p "$WORK/export"
command -v pg_dump >/dev/null || { echo "pg_dump introuvable : sudo apt install postgresql-client"; exit 1; }
echo "pg_dump : $(pg_dump --version)"
echo "Colle l'adresse « Session pooler » de l'ANCIEN projet (lvjlthzdydzatcvwwriu), mot de passe inclus."
echo "Elle ne s'affiche pas et n'est enregistrée nulle part."
read -rsp "Adresse : " OLD_DB_URL; echo
case "$OLD_DB_URL" in *lvjlthzdydzatcvwwriu*) ;; *) echo "Ce n'est pas l'adresse de l'ancien projet — arrêt."; exit 1;; esac
export PGCONNECT_TIMEOUT=15
# pg_dump 18 can also carry planner statistics: never wanted here.
STATS=""; [ "$(pg_dump --version | grep -oE '[0-9]+' | head -1)" -ge 18 ] && STATS="--no-statistics"
pg_dump "$OLD_DB_URL" --schema-only -n public -n private --no-owner $STATS -f "$WORK/export/schema.sql"
# Reference data + the security data that must survive an empty migration:
# banned e-mail fingerprints (re-signup block after a suspended account is deleted).
pg_dump "$OLD_DB_URL" --data-only -t public.sports -t public.gear_catalog -t public.banned_email_hashes \
  --column-inserts $STATS -f "$WORK/export/reference.sql"
psql "$OLD_DB_URL" -X -A -t -c "select version()" > "$WORK/export/server-version.txt"
unset OLD_DB_URL
echo
echo "Export terminé dans $WORK/export :"
ls -la "$WORK/export"
echo "Dis-moi « export fait » : je prends la suite."
