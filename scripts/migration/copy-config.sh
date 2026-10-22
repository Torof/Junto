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
# On failure, show the HTTP status and Supabase's message (never contains a secret).
call() {  # call METHOD PATH [BODYFILE] → body on stdout; non-zero + message on failure
  local out="$WORK/.resp" code
  if [ -n "${3:-}" ]; then
    code=$(curl -s -o "$out" -w '%{http_code}' -X "$1" -H "Authorization: Bearer $SUPABASE_TOKEN" -H "Content-Type: application/json" --data-binary @"$3" "$API/$2")
  else
    code=$(curl -s -o "$out" -w '%{http_code}' -X "$1" -H "Authorization: Bearer $SUPABASE_TOKEN" "$API/$2")
  fi
  if [ "${code:0:1}" != 2 ]; then echo "  → $1 $2 : HTTP $code $(head -c 300 "$out")" >&2; rm -f "$out"; return 1; fi
  cat "$out"; rm -f "$out"
}
get() { call GET "$1"; }
patch() { call PATCH "$1" "$2" > /dev/null; }

for part in config/auth postgrest; do
  name=${part//\//-}
  # The old configuration stays in memory: Supabase returns the SMTP password in
  # clear, so the copy written to disk is redacted first.
  OLD_JSON=$(get "$OLD/$part") || { echo "Lecture de l'ancien projet impossible ($part) — jeton valide ?"; unset SUPABASE_TOKEN; exit 1; }
  export OLD_JSON
  # Body = every setting except secrets — but the SMTP password is carried over
  # from the old project (memory only: the SMTP settings cannot be saved without it).
  BODY=$(python3 - "$WORK/old-$name.json" "$WORK/patch-$name.json" "$WORK/secrets-$name.txt" <<'PY'
import json, os, re, sys
redacted, out, sec = sys.argv[1:4]
d = json.loads(os.environ['OLD_JSON'])
SECRET = re.compile(r'(smtp_pass|secret|auth_token|api_key|private_key|_key$|^jwt_secret)')
keep, secrets = {}, []
for k, v in d.items():
    if SECRET.search(k):
        if v not in (None, '', False) and k != 'smtp_pass': secrets.append(k)
        continue
    if v is None: continue
    keep[k] = v
json.dump(keep, open(out, 'w'))  # what is compared afterwards (no secret)
json.dump({k: ('<retiré>' if SECRET.search(k) and v not in (None, '', False) else v) for k, v in d.items()}, open(redacted, 'w'))
open(sec, 'w').write('\n'.join(secrets))
body = dict(keep)
if d.get('smtp_pass') and d.get('smtp_host'): body['smtp_pass'] = d['smtp_pass']
print(json.dumps(body))
PY
)
  unset OLD_JSON
  if ! printf '%s' "$BODY" | call PATCH "$NEW/$part" /dev/stdin > /dev/null; then
    unset BODY SUPABASE_TOKEN; echo "Écriture refusée sur le nouveau projet ($part) — dis-le-moi, je lis $WORK."; exit 1
  fi
  unset BODY
  get "$NEW/$part" | python3 - "$WORK/patch-$name.json" "$part" "$WORK/secrets-$name.txt" "$WORK/new-$name.json" <<'PY'
import json, re, sys
want, part, sec, newfile = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3], sys.argv[4]
got = json.load(sys.stdin)
SECRET = re.compile(r'(smtp_pass|secret|auth_token|api_key|private_key|_key$|^jwt_secret)')
json.dump({k: ('<retiré>' if SECRET.search(k) and v not in (None, '', False) else v) for k, v in got.items()}, open(newfile, 'w'))
diff = sorted(k for k, v in want.items() if got.get(k) != v)
print(f"{part} : {len(want)} réglages copiés, {len(diff)} différent(s) après copie" + (f" : {', '.join(diff)}" if diff else ""))
if part == 'config/auth': print(f"  mot de passe SMTP repris de l'ancien projet : {'oui' if got.get('smtp_pass') else 'non'}")
s = open(sec).read().split()
if s: print(f"  secrets NON copiés (à saisir à la main dans le tableau de bord) : {', '.join(s)}")
PY
done
unset SUPABASE_TOKEN
echo "Terminé. Les fichiers de travail (sans secret) sont dans $WORK. Tu peux révoquer le jeton maintenant."
