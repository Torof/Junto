// Rewrites incoming deep-link paths before Expo Router resolves them.
//
// Contact-share links are `https://getjunto.app/u/<uuid>` (and the matching
// applink / junto://u/<uuid>) — a deliberate rename of the profile route. There
// is no `/u` screen; map a well-formed UUID to the real profile route. Every
// other path (activity / invite / pro / …) passes through untouched.
const U_PATH = /(?:^|\/)u\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:$|[/?#])/;

export function redirectSystemPath({ path }: { path: string; initial: boolean }): string {
  try {
    const m = path.match(U_PATH);
    if (m) return `/profile/${m[1]}`;
  } catch {
    // fall through — never let a malformed link crash cold-start routing
  }
  return path;
}
