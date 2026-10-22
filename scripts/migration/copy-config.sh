#!/usr/bin/env bash
# Phase D — copy the Auth and Data API configuration from the OLD project to the
# NEW one through the Supabase Management API. Run by Scott: the access token is
# typed at its own prompt, never stored, never printed, never in argv.
# Secrets (SMTP password, provider secrets, hook secrets…) are NOT copied: the
# script lists which ones exist so they can be entered by hand in the dashboard.
#   bash scripts/migration/copy-config.sh <new-project-ref>
set -euo pipefail
umask 077
OLD=lvjlthzdydzatcvwwriu
NEW="${1:-}"
[[ "$NEW" =~ ^[a-z0-9]{20}$ && "$NEW" != "$OLD" ]] || { echo "Usage : bash scripts/migration/copy-config.sh <référence du nouveau projet>"; exit 1; }
WORK="${JUNTO_MIG_WORK:-$HOME/junto-migration}/config"; mkdir -p "$WORK"
echo "Jeton d'accès Supabase : tableau de bord → ton avatar → Account preferences → Access Tokens → Generate new token."
read -rsp "Jeton (ne s'affiche pas) : " SUPABASE_TOKEN; echo
export SUPABASE_TOKEN
API=https://api.supabase.com/v1/projects
get() { curl -sf -H "Authorization: Bearer $SUPABASE_TOKEN" "$API/$1"; }
patch() { curl -sf -X PATCH -H "Authorization: Bearer $SUPABASE_TOKEN" -H "Content-Type: application/json" --data-binary @"$2" "$API/$1" > /dev/null; }

for part in config/auth postgrest; do
  name=${part//\//-}
  get "$OLD/$part" > "$WORK/old-$name.json" || { echo "Lecture de l'ancien projet impossible ($part) — jeton valide ?"; unset SUPABASE_TOKEN; exit 1; }
  python3 - "$WORK/old-$name.json" "$WORK/patch-$name.json" "$WORK/secrets-$name.txt" <<'PY'
import json, re, sys
src, out, sec = sys.argv[1:4]
d = json.load(open(src))
SECRET = re.compile(r'(smtp_pass|secret|auth_token|api_key|private_key|_key$|^jwt_secret)')
keep, secrets = {}, []
for k, v in d.items():
    if SECRET.search(k):
        if v not in (None, '', False): secrets.append(k)
        continue
    if v is None: continue
    keep[k] = v
json.dump(keep, open(out, 'w'))
open(sec, 'w').write('\n'.join(secrets))
PY
  if ! patch "$NEW/$part" "$WORK/patch-$name.json"; then
    echo "Écriture refusée sur le nouveau projet ($part) — dis-le-moi, je lis $WORK."; unset SUPABASE_TOKEN; exit 1
  fi
  get "$NEW/$part" > "$WORK/new-$name.json"
  python3 - "$WORK/patch-$name.json" "$WORK/new-$name.json" "$part" "$WORK/secrets-$name.txt" <<'PY'
import json, sys
want, got, part, sec = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3], sys.argv[4]
diff = sorted(k for k, v in want.items() if got.get(k) != v)
print(f"{part} : {len(want)} réglages copiés, {len(diff)} différent(s) après copie" + (f" : {', '.join(diff)}" if diff else ""))
s = open(sec).read().split()
if s: print(f"  secrets NON copiés (à saisir à la main dans le tableau de bord) : {', '.join(s)}")
PY
done
unset SUPABASE_TOKEN
echo "Terminé. Les fichiers de travail (sans secret) sont dans $WORK. Tu peux révoquer le jeton maintenant."
