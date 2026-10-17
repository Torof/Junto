# Junto — Web (landing + share preview)

Next.js app deployed on Vercel.

## Routes
- `/` — landing page (download CTA)
- `/activity/[id]` — public activity preview + open-in-app + download
- `/invite/[token]` — private-link invitation
- `/.well-known/assetlinks.json` — Android App Links verification

## Deploy

**Vercel auto-deploys on every push to `main`** (project linked, Root Directory = `web`). No manual steps.

Env vars (Vercel project settings): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and optionally `NEXT_PUBLIC_PLAY_STORE_URL` — when set, every download CTA and the QR point at the Play listing (label « Télécharger sur Google Play »); when empty they fall back to the direct Android build in `lib/download.ts`.

## Landing v4 (2026-10-17)

`app/page.tsx` composes `app/components/landing/*` — the « carte vivante » page validated on the design canvas (2PqvqtoLhTxdU9mVVk784Z). Live data is read anonymously: `activities_with_coords` (public, published, upcoming) feeds the hero pins and the departures board; `pro_offerings_with_coords` feeds the pro section. Both degrade to calm empty states when there is nothing to show. Partners, channel and profile blocks are illustrative (the app's demo personas). The iOS waitlist form calls the `join_ios_waitlist` RPC and falls back to a contact e-mail while that function does not exist.

`public/.well-known/assetlinks.json` carries the real EAS signing fingerprint (verified 2026-06-11). At store release, ADD the Play App Signing cert fingerprint alongside it (Play Console → App integrity).
