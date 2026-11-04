# askandgo — Web (landing + share preview)

Next.js app deployed on Vercel.

## Routes
- `/` — landing page (download CTA)
- `/pros` — landing for pros
- `/activity/[id]` — public activity preview + open-in-app + download
- `/invite/[token]` — private-link invitation
- `/u/[id]` — public user profile preview
- `/pro/[id]` — public pro page preview
- `/pro/offering/[id]` — public pro offering preview
- `/auth/callback`, `/auth/reset-password` — auth bridges back into the app
- `/legal/privacy`, `/legal/terms`, `/legal/mentions`, `/legal/account-deletion`
- `/.well-known/assetlinks.json` — Android App Links verification

## Deploy

**Vercel auto-deploys on every push to `main`** (project linked, Root Directory = `web`). No manual steps.

Env vars (Vercel project settings): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and optionally `NEXT_PUBLIC_PLAY_STORE_URL` — when set, every download CTA and the QR point at the Play listing (label « Télécharger sur Google Play »); until then they fall back to the direct Android build (APK) in `lib/download.ts`.

## Landing v4 (2026-10-17)

`app/page.tsx` composes `app/components/landing/*` — the « carte vivante » page validated on the design canvas (2PqvqtoLhTxdU9mVVk784Z). Live data is read anonymously: `activities_with_coords` (public, published, upcoming) feeds the hero pins and the departures board; `pro_offerings_with_coords` feeds the pro section. Both degrade to calm empty states when there is nothing to show. Partners, channel and profile blocks are illustrative (the app's demo personas).

`public/.well-known/assetlinks.json` carries the signing fingerprints for `app.getjunto` (including the Play App Signing cert) and `app.getjunto.preview`.
