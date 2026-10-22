#!/usr/bin/env bash
# Our own full backup of the database — independent of the platform's backups.
# Run by Scott (password typed at its own prompt, never stored, never in argv).
#   bash scripts/db-backup.sh <project-ref>
# Writes ~/junto-backups/<ref>-<date>.dump (pg_dump custom format: restorable as a
# whole or table by table with pg_restore). Private to the user (umask 077).
set -euo pipefail
umask 077
REF="${1:-}"
[[ "$REF" =~ ^[a-z0-9]{20}$ ]] || { echo "Usage : bash scripts/db-backup.sh <référence du projet>"; exit 1; }
command -v pg_dump >/dev/null || { echo "pg_dump introuvable : sudo apt install postgresql-client"; exit 1; }
DIR="${JUNTO_BACKUP_DIR:-$HOME/junto-backups}"; mkdir -p "$DIR"
echo "Colle l'adresse « Session pooler » du projet $REF, telle quelle (avec [YOUR-PASSWORD])."
read -rp "Adresse : " URL
case "$URL" in *"postgres.$REF"*) ;; *) echo "Cette adresse n'est pas celle du projet $REF — arrêt."; exit 1;; esac
URL=$(printf '%s' "$URL" | sed -E 's#^(postgres(ql)?://[^:/@]+)(:.*)?@([^@]*)$#\1@\4#')
read -rsp "Mot de passe de la base (ne s'affiche pas) : " PGPASSWORD; echo
export PGPASSWORD PGCONNECT_TIMEOUT=15
OUT="$DIR/$REF-$(date +%F-%H%M).dump"
STATS=""; [ "$(pg_dump --version | grep -oE '[0-9]+' | head -1)" -ge 18 ] && STATS="--no-statistics"
pg_dump "$URL" -Fc $STATS -n public -n private -n auth -n storage -f "$OUT"
unset PGPASSWORD
pg_restore -l "$OUT" > /dev/null && echo "Sauvegarde lisible : $OUT ($(du -h "$OUT" | cut -f1))"
