#!/usr/bin/env bash
# API smoke test on the linked project (supabase/.temp/project-ref), seen from outside like a client.
# 1. Edge Functions refuse a caller without credentials (run after each `functions deploy`).
# 2. The REST API exposes only `public`: PostGIS internals (extensions) and the pg_net queue (net)
#    are out of reach. These belong to supabase_admin, so their grants cannot be revoked from the
#    database (PV-1, PV-4) — what protects them is that the API does not expose those schemas.
# Only refusals are tested: nothing is sent, deleted or billed. The public (anon) key is fetched
# at run time and never printed.
set -euo pipefail
cd "$(dirname "$0")/.."
ref=$(cat supabase/.temp/project-ref)
base="https://${ref}.supabase.co/functions/v1"
rest="https://${ref}.supabase.co/rest/v1"
anon=$(npx supabase projects api-keys --project-ref "$ref" -o json 2>/dev/null \
  | python3 -c "import sys,json; print(next(k['api_key'] for k in json.load(sys.stdin) if k.get('name') == 'anon'))")
fail=0
check() { # name, expected codes (regex), curl args...
  local name=$1 expect=$2; shift 2
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@")
  if [[ $code =~ ^($expect)$ ]]; then echo "  ok   $name → $code"; else echo "  FAIL $name → $code (expected $expect)"; fail=1; fi
}
echo "Edge Functions on ${ref}:"
check 'send-push sans secret'          '401|403' -X POST "$base/send-push" -H 'Content-Type: application/json' -d '{"user_ids":[]}'
check 'send-push avec un faux secret'  '401|403' -X POST "$base/send-push" -H 'Content-Type: application/json' -H 'x-junto-push-secret: faux' -d '{"user_ids":[]}'
check 'delete-account sans compte'     '401|403' -X POST "$base/delete-account"
check 'delete-account jeton bidon'     '401|403' -X POST "$base/delete-account" -H 'Authorization: Bearer faux.jeton.bidon'
check 'snap-trail sans compte'         '401|403' -X POST "$base/snap-trail" -H 'Content-Type: application/json' -d '{}'
check 'trace-elevation sans compte'    '401|403' -X POST "$base/trace-elevation" -H 'Content-Type: application/json' -d '{}'
echo "REST API on ${ref}:"
check 'carte publique lisible (témoin)'        '200'     "$rest/activities_with_coords?select=id&limit=1" -H "apikey: $anon"
check 'schéma extensions non exposé'          '406'     "$rest/spatial_ref_sys?select=srid&limit=1" -H "apikey: $anon" -H 'Accept-Profile: extensions'
check '_postgis_stats injoignable'            '404'     -X POST "$rest/rpc/_postgis_stats" -H "apikey: $anon" -H 'Content-Type: application/json' -d '{}'
check 'schéma net (file HTTP) non exposé'     '406'     "$rest/http_request_queue?select=id&limit=1" -H "apikey: $anon" -H 'Accept-Profile: net'
check 'file HTTP absente de public'           '404'     "$rest/http_request_queue?select=id&limit=1" -H "apikey: $anon"
exit $fail
