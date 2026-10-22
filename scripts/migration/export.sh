#!/usr/bin/env bash
# Phase A — export the OLD project's structure + reference/security data (read-only).
# Run by Scott in his own terminal. The password is typed at its own prompt:
# never displayed, never stored, never on a command line (not visible in `ps`).
#   bash scripts/migration/export.sh
set -euo pipefail
umask 077
OLD_REF=lvjlthzdydzatcvwwriu
WORK="${JUNTO_MIG_WORK:-$HOME/junto-migration}"
mkdir -p "$WORK/export" "$WORK/archive"
command -v pg_dump >/dev/null || { echo "pg_dump introuvable : sudo apt install postgresql-client"; exit 1; }
echo "pg_dump : $(pg_dump --version)"
echo "Colle l'adresse « Session pooler » de l'ANCIEN projet, telle quelle (avec [YOUR-PASSWORD], sans le remplacer)."
read -rp "Adresse : " URL
case "$URL" in *"postgres.$OLD_REF"*) ;; *) echo "Ce n'est pas l'adresse de l'ancien projet — arrêt."; exit 1;; esac
URL=$(printf '%s' "$URL" | sed -E 's#^(postgres(ql)?://[^:/@]+)(:.*)?@([^@]*)$#\1@\4#')   # drop any password part
read -rsp "Mot de passe de la base (ne s'affiche pas) : " PGPASSWORD; echo
export PGPASSWORD PGCONNECT_TIMEOUT=15
psql "$URL" -X -A -t -c "select 'connexion ok : ' || current_database()" || { unset PGPASSWORD; exit 1; }
# pg_dump 18 can also carry planner statistics: never wanted here.
STATS=""; [ "$(pg_dump --version | grep -oE '[0-9]+' | head -1)" -ge 18 ] && STATS="--no-statistics"
pg_dump "$URL" --schema-only -n public -n private --no-owner $STATS -f "$WORK/export/schema.sql"
# Reference data + security data that must survive the empty migration
# (banned e-mail fingerprints: the re-signup block after a suspended account is deleted).
pg_dump "$URL" --data-only -t public.sports -t public.gear_catalog -t public.banned_email_hashes \
  --column-inserts $STATS -f "$WORK/export/reference.sql"
# Archive only (NOT restored — empty-database decision): moderation history.
pg_dump "$URL" --data-only -t public.admin_actions -t public.late_cancels --column-inserts $STATS \
  -f "$WORK/archive/history-$(date +%F).sql"
psql "$URL" -X -A -t -c "select version()" > "$WORK/export/server-version.txt"
unset PGPASSWORD
echo
echo "Export terminé dans $WORK/export (archive de l'historique de modération dans $WORK/archive) :"
ls -la "$WORK/export"
echo "Dis-moi « export fait » : je prends la suite."
