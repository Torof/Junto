'use client';

import { useEffect, useState } from 'react';
import { OpenAppLink } from '../../open-app-link';

import { APK_DOWNLOAD_URL } from '@/lib/download';

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
    // Only the one-time code is relayed (email templates use {{ .TokenHash }}
    // since 2026-10-23); a link carrying raw session tokens is ignored.
    const tokenHash = url.searchParams.get('token_hash');
    const type = url.searchParams.get('type') ?? 'signup';
    const params = tokenHash ? new URLSearchParams({ token_hash: tokenHash, type }) : null;

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
        Ton compte askandgo est prêt. Ouvre l&apos;app pour continuer.
      </p>

      <OpenAppLink deepLink={deepLink} />

      <a
        href={APK_DOWNLOAD_URL}
        style={{ marginTop: 16, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}
      >
        Pas encore askandgo installé ? Télécharger
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
