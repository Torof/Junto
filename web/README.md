# Junto — Web (landing + share preview)

Next.js app deployed on Vercel.

## Routes
- `/` — landing page (download CTA)
- `/activity/[id]` — public activity preview + open-in-app + download
- `/invite/[token]` — private-link invitation
- `/.well-known/assetlinks.json` — Android App Links verification

## Deploy

**Vercel auto-deploys on every push to `main`** (project linked, Root Directory = `web`). No manual steps.

Env vars (Vercel project settings): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_APK_DOWNLOAD_URL` (point at the Play Store listing once live).

`public/.well-known/assetlinks.json` carries the real EAS signing fingerprint (verified 2026-06-11). At store release, ADD the Play App Signing cert fingerprint alongside it (Play Console → App integrity).
