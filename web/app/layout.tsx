import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Junto — Trouve des partenaires d\'activités outdoor',
  description: 'Junto est une app pour organiser et rejoindre des sorties outdoor près de chez toi : escalade, rando, parapente, canyon...',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
