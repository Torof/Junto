// Rewrites incoming deep-link paths before Expo Router resolves them.
//
// Contact-share links are `https://askandgo.io/u/<uuid>` (or getjunto.app) (and the matching
// applink / junto://u/<uuid>) — a deliberate rename of the profile route. There
// is no `/u` screen; map a well-formed UUID to the real profile route. Every
// other path (activity / invite / pro / …) passes through untouched.
const U_PATH = /(?:^|\/)u\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:$|[/?#])/;

// Account e-mail links (App Links since v18): https://<host>/auth/reset-password
// and /auth/callback carry ?token_hash=…&type=… — the same screens the site
// relays to (junto://reset-password, junto://auth-confirm), query kept.
const AUTH_PATH = /(?:^|\/)auth\/(reset-password|callback)(?=$|[/?#])/;

export function redirectSystemPath({ path }: { path: string; initial: boolean }): string {
  try {
    const m = path.match(U_PATH);
    if (m) return `/profile/${m[1]}`;
    const a = path.match(AUTH_PATH);
    if (a && a.index !== undefined) {
      const rest = path.slice(a.index + a[0].length).replace(/^\/+/, '');
      return `/${a[1] === 'callback' ? 'auth-confirm' : 'reset-password'}${rest}`;
    }
  } catch {
    // fall through — never let a malformed link crash cold-start routing
  }
  return path;
}
