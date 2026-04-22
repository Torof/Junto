import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Junto — La commu outdoor près de chez toi',
  description: 'Junto est une app pour organiser et rejoindre des sorties outdoor près de chez toi : escalade, rando, parapente, canyon...',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700;800;900&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
