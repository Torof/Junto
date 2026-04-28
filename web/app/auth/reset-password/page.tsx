'use client';

import { useEffect, useState } from 'react';
import { OpenAppLink } from '../../open-app-link';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? '#';

export default function ResetPasswordBridge() {
  const [deepLink, setDeepLink] = useState<string | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const url = new URL(window.location.href);
    const tokenHash = url.searchParams.get('token_hash');
    const type = url.searchParams.get('type') ?? 'recovery';

    if (!tokenHash) {
      setDeepLink('');
      return;
    }

    const params = new URLSearchParams({ token_hash: tokenHash, type });
    setDeepLink(`junto://reset-password?${params.toString()}`);
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
        <h1 style={{ fontSize: 26, fontWeight: 800, marginBottom: 12 }}>
          Lien invalide
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: 16, lineHeight: 1.5 }}>
          Ce lien de réinitialisation a expiré ou est mal formé. Demande un nouvel email depuis l'app.
        </p>
      </main>
    );
  }

  return (
    <main style={pageStyle}>
      <div style={iconStyle}>🔑</div>

      <h1 style={{ fontSize: 26, fontWeight: 800, marginBottom: 12 }}>
        Réinitialiser ton mot de passe
      </h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 16, lineHeight: 1.5, marginBottom: 32 }}>
        Ouvre Junto pour choisir un nouveau mot de passe.
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
  background: 'rgba(255, 165, 0, 0.18)',
  border: '2px solid var(--cta)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  marginBottom: 24,
  fontSize: 40,
};
