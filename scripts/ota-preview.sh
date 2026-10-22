#!/usr/bin/env bash
# Publish a PREVIEW over-the-air update, safely (migration 2026-10-22: preview
# and production point to different Supabase projects).
#   bash scripts/ota-preview.sh "message"          # build, check, publish
#   bash scripts/ota-preview.sh --check "message"  # build and check only
# 1. builds the bundle with the EAS `preview` environment (never the local .env,
#    which still points to the old project) and WITHOUT the Metro cache (it keeps
#    inlined EXPO_PUBLIC_* values across builds — a stale host could slip in),
#    2. refuses unless the bundle names
#    the preview project and NOT the old one, 3. publishes exactly that bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
EXPECTED=fajfigpwfdwmchhzecwe   # preview database (new project)
FORBIDDEN=lvjlthzdydzatcvwwriu  # old project (production until phase F)
CHECK_ONLY=false; [ "${1:-}" = "--check" ] && { CHECK_ONLY=true; shift; }
MSG="${1:?Usage : bash scripts/ota-preview.sh [--check] \"message\"}"

rm -rf dist
npx eas env:exec preview "npx expo export --output-dir dist --clear" --non-interactive > /tmp/ota-preview-export.log 2>&1 \
  || { tail -20 /tmp/ota-preview-export.log; echo "ARRÊT : la construction a échoué."; exit 1; }
BUNDLES=$(find dist/_expo/static/js -type f \( -name '*.hbc' -o -name '*.js' \))
[ -n "$BUNDLES" ] || { echo "ARRÊT : aucun bundle produit."; exit 1; }
for b in $BUNDLES; do
  grep -aq "$EXPECTED" "$b" || { echo "ARRÊT : $b ne vise pas le projet preview ($EXPECTED)."; exit 1; }
  if grep -aq "$FORBIDDEN" "$b"; then echo "ARRÊT : $b contient l'ancien projet ($FORBIDDEN)."; exit 1; fi
done
echo "Vérifié : $(echo "$BUNDLES" | wc -l) bundle(s) visent $EXPECTED, aucun ne nomme l'ancien projet."
$CHECK_ONLY && { echo "(--check : rien n'est publié)"; exit 0; }
npx eas update --branch preview --environment preview --skip-bundler --input-dir dist --message "$MSG" --non-interactive
