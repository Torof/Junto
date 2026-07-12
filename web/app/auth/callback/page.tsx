'use client';

import { useEffect, useState } from 'react';
import { OpenAppLink } from '../../open-app-link';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? '#';

// Signup email confirmation bridge — mirror of the reset-password bridge.
// Supabase confirms the email, redirects here with the token, and we
// forward it to the app via junto://auth-confirm so the confirmation link
// logs the user straight into Junto (no re-entering credentials right
// after signing up — Scott 2026-07-12).
export default function EmailVerifiedPage() {
  const [deepLink, setDeepLink] = useState<string | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const url = new URL(window.location.href);
    const hash = window.location.hash.startsWith('#')
      ? new URLSearchParams(window.location.hash.slice(1))
      : new URLSearchParams();

    // Two shapes Supabase can deliver:
    //   a) query: ?token_hash=...&type=signup  (template uses {{ .TokenHash }})
    //   b) fragment: #access_token=...&refresh_token=...&type=signup
    const tokenHash = url.searchParams.get('token_hash');
    const accessToken = hash.get('access_token');
    const refreshToken = hash.get('refresh_token');
    const type = url.searchParams.get('type') ?? hash.get('type') ?? 'signup';

    let params: URLSearchParams | null = null;
    if (tokenHash) {
      params = new URLSearchParams({ token_hash: tokenHash, type });
    } else if (accessToken && refreshToken) {
      params = new URLSearchParams({ access_token: accessToken, refresh_token: refreshToken, type });
    }

    if (!params) {
      setDeepLink('');
      return;
    }

    setDeepLink(`junto://auth-confirm?${params.toString()}`);
  }, []);

  if (deepLink === null) {
    return (
      <main style={pageStyle}>
        <p style={{ color: 'var(--text-secondary)', fontSize: 16 }}>Chargement…</p>
      </main>
    );
  }

  if (deepLink === '') {
    return (
      <main style={pageStyle}>
        <h1 style={{ fontSize: 26, fontWeight: 800, marginBottom: 12 }}>Lien invalide</h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: 16, lineHeight: 1.5 }}>
          Ce lien de confirmation a expiré ou est mal formé. Connecte-toi avec ton email et ton
          mot de passe depuis l&apos;app.
        </p>
      </main>
    );
  }

  return (
    <main style={pageStyle}>
      <div style={iconStyle}>✓</div>

      <h1 style={{ fontSize: 28, fontWeight: 800, marginBottom: 12 }}>Email confirmé !</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 16, lineHeight: 1.5, marginBottom: 32 }}>
        Ton compte Junto est prêt. Ouvre l&apos;app pour continuer.
      </p>

      <OpenAppLink deepLink={deepLink} />

      <a
        href={APK_DOWNLOAD_URL}
        style={{ marginTop: 16, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}
      >
        Pas encore Junto installé ? Télécharger
      </a>
    </main>
  );
}

const pageStyle: React.CSSProperties = {
  minHeight: '100vh',
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  justifyContent: 'center',
  padding: 24,
  maxWidth: 480,
  margin: '0 auto',
  textAlign: 'center',
};

const iconStyle: React.CSSProperties = {
  width: 88,
  height: 88,
  borderRadius: 44,
  background: 'rgba(46, 204, 113, 0.2)',
  border: '2px solid var(--success)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  marginBottom: 24,
  fontSize: 44,
};
