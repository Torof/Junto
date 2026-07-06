'use client';

import { useEffect, useState } from 'react';

interface Props {
  deepLink: string; // junto://path/to/screen
}

const ANDROID_PACKAGE = 'app.getjunto';

// Chrome on Android blocks plain custom-scheme navigations (both the JS
// auto-redirect and, in most versions, junto:// anchors). The reliable format
// is an intent:// URL carrying the scheme + package — tapped from a user
// gesture it opens the app, and falls back to the Play page for the package
// when the app isn't installed. iOS and desktop keep the raw scheme link.
function androidIntentHref(deepLink: string): string {
  const path = deepLink.replace(/^junto:\/\//, '');
  return `intent://${path}#Intent;scheme=junto;package=${ANDROID_PACKAGE};end`;
}

export function OpenAppLink({ deepLink }: Props) {
  // Resolved client-side (userAgent) to avoid an SSR/hydration mismatch.
  const [href, setHref] = useState(deepLink);

  useEffect(() => {
    const isAndroid = /android/i.test(navigator.userAgent);
    const target = isAndroid ? androidIntentHref(deepLink) : deepLink;
    setHref(target);

    // Best-effort auto-open. Browsers usually require a user gesture for
    // app-opening navigations, so the button below stays the reliable path.
    const t = setTimeout(() => {
      window.location.href = target;
    }, 300);
    return () => clearTimeout(t);
  }, [deepLink]);

  return (
    <a
      href={href}
      style={{
        display: 'inline-block',
        background: 'var(--cta)',
        color: 'var(--text)',
        padding: '14px 28px',
        borderRadius: 999,
        fontSize: 16,
        fontWeight: 700,
      }}
    >
      Ouvrir dans Junto
    </a>
  );
}
