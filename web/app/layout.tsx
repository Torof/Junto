import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Junto — Sorties outdoor entre passionnés',
  description:
    'Rejoins une sortie, lance la tienne, trouve des partenaires où que tu sois — ou réserve avec un guide. Escalade, rando, parapente, canyon, vélo, ski de rando.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700;800;900&family=Montserrat:wght@700;800;900&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
