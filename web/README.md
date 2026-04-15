# Junto — Web (landing + share preview)

Next.js app deployed on Vercel.

## Routes
- `/` — landing page (download CTA)
- `/activity/[id]` — public activity preview + open-in-app + download
- `/invite/[token]` — private-link invitation
- `/.well-known/assetlinks.json` — Android App Links verification

## Deploy

1. Push the repo to GitHub.
2. On Vercel, import the project. Set **Root Directory** to `web`.
3. Add environment variables on Vercel:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `NEXT_PUBLIC_APK_DOWNLOAD_URL` (e.g. EAS build URL)
4. Deploy.
5. Note the Vercel URL (e.g. `junto.vercel.app`) — set it on the app side as `JUNTO_WEB_HOST` (EAS env), then rebuild the APK.
6. Once you have the SHA-256 fingerprint of your Android signing key (`eas credentials → Android → preview`), edit `public/.well-known/assetlinks.json` and replace the placeholder.
