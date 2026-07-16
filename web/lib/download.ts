// Single source of truth for the public APK download link.
//
// Every new APK build produces a fresh EAS artifact URL. To ship a new build to
// the site: update THIS one line and push to `main` — Vercel auto-deploys. This
// replaces the former NEXT_PUBLIC_APK_DOWNLOAD_URL Vercel env var so the link
// lives in version control and can be bumped alongside a build (no dashboard).
//
// Current: v0.1.3 build #13 (rnmapbox 10.3.2), EAS preview APK.
export const APK_DOWNLOAD_URL =
  'https://expo.dev/artifacts/eas/fS7ozN_5dZR-92rI3bkFhB2mo3vvlVoC9aLYhL9et3s.apk';
