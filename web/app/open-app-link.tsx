'use client';

import { useEffect } from 'react';

interface Props {
  deepLink: string;
}

export function OpenAppLink({ deepLink }: Props) {
  // Try to auto-open the app on mount; fallback to button if it fails
  useEffect(() => {
    const t = setTimeout(() => {
      window.location.href = deepLink;
    }, 300);
    return () => clearTimeout(t);
  }, [deepLink]);

  return (
    <a
      href={deepLink}
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
