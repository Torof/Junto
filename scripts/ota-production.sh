#!/usr/bin/env bash
# Publish a PRODUCTION over-the-air update — only what was first published to
# preview and validated there (house rule, Scott 2026-10-23).
#   bash scripts/ota-production.sh "message"
# Refuses unless: the working tree is clean and pushed, and one of the last
# preview updates was built from the same app code (docs and scripts may differ). Then builds with the
# EAS `production` environment, without the Metro cache, checks the bundle
# names the live project and not the old one, and publishes that bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
EXPECTED=fajfigpwfdwmchhzecwe   # live database (since phase F, 2026-10-23)
FORBIDDEN=lvjlthzdydzatcvwwriu  # old project (cut, kept for rollback)
MSG="${1:?Usage : bash scripts/ota-production.sh \"message\"}"

[ -z "$(git status --porcelain)" ] || { echo "ARRÊT : des modifications ne sont pas commitées."; exit 1; }
git fetch -q origin
HEAD_SHA=$(git rev-parse HEAD)
[ "$HEAD_SHA" = "$(git rev-parse '@{u}')" ] || { echo "ARRÊT : le commit courant n'est pas poussé."; exit 1; }
python3 - "$HEAD_SHA" <<'PY' || { echo "ARRÊT : ce commit ($HEAD_SHA) ne correspond à aucune publication preview récente — preview d'abord."; exit 1; }
import json, subprocess, sys
def eas_json(*args):
    out = subprocess.run(['npx', 'eas', *args, '--json', '--non-interactive'], capture_output=True, text=True).stdout
    return json.loads(out[out.find('[') if out.find('[') != -1 and (out.find('{') == -1 or out.find('[') < out.find('{')) else out.find('{'):])
groups = [u['group'] for u in eas_json('update:list', '--branch', 'preview', '--limit', '5')['currentPage']]
APP_PATHS = ['app', 'src', 'assets', 'app.config.ts', 'package.json', 'package-lock.json', 'babel.config.js', 'metro.config.js']
for g in groups:
    for sha in {u.get('gitCommitHash') for u in eas_json('update:view', g)} - {None}:
        # Same app code as a validated preview update (docs/scripts may differ).
        same = subprocess.run(['git', 'diff', '--quiet', sha, sys.argv[1], '--', *APP_PATHS]).returncode == 0
        if same:
            print(f'Preview validée correspondante : {sha[:7]}')
            sys.exit(0)
sys.exit(1)
PY

rm -rf dist
npx eas env:exec production "npx expo export --output-dir dist --clear" --non-interactive > /tmp/ota-production-export.log 2>&1 \
  || { tail -20 /tmp/ota-production-export.log; echo "ARRÊT : la construction a échoué."; exit 1; }
BUNDLES=$(find dist/_expo/static/js -type f \( -name '*.hbc' -o -name '*.js' \))
[ -n "$BUNDLES" ] || { echo "ARRÊT : aucun bundle produit."; exit 1; }
for b in $BUNDLES; do
  grep -aq "$EXPECTED" "$b" || { echo "ARRÊT : $b ne vise pas le projet en service ($EXPECTED)."; exit 1; }
  if grep -aq "$FORBIDDEN" "$b"; then echo "ARRÊT : $b contient l'ancien projet ($FORBIDDEN)."; exit 1; fi
done
echo "Vérifié : $(echo "$BUNDLES" | wc -l) bundle(s) visent $EXPECTED ; même code que la preview validée."
npx eas update --branch production --environment production --skip-bundler --input-dir dist --message "$MSG" --non-interactive
