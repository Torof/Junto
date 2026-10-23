#!/usr/bin/env bash
# Edge Functions smoke test — every function refuses a caller without credentials.
# Run after each `supabase functions deploy`. No secret needed: only refusals are tested,
# so nothing is sent, deleted or billed. Targets the linked project (supabase/.temp/project-ref).
set -euo pipefail
cd "$(dirname "$0")/.."
ref=$(cat supabase/.temp/project-ref)
base="https://${ref}.supabase.co/functions/v1"
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
exit $fail
