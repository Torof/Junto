import type { Metadata } from 'next';
import '../components/landing/landing.css';
import { ProsHero, ProsOrganise, ProsShowcase, ProsTalk } from '../components/landing/pros-page';
import Download from '../components/landing/download';
import { fetchOffers } from '../components/landing/data';
import { mockOffers } from '../components/landing/mock-data';
import { APK_DOWNLOAD_URL } from '@/lib/download';

export const metadata: Metadata = {
  title: 'askandgo pour les pros — ta vitrine et ton outil d’organisation',
  description: 'Guides, moniteurs, accompagnateurs : publie tes offres sur la carte, reçois tes réservations et les fiches de tes clients, échange avec eux — dans une seule app.',
};

// Same freshness and launch-window fill as the landing (page.tsx).
export const revalidate = 300;
const MOCK_BELOW = 4;

export default async function ProsPage() {
  const realOffers = await fetchOffers(12);
  const offers = realOffers.length >= MOCK_BELOW ? realOffers : [...realOffers, ...mockOffers()];
  const playStore = process.env.NEXT_PUBLIC_PLAY_STORE_URL?.trim();
  const playUrl = playStore && playStore.length > 0 ? playStore : APK_DOWNLOAD_URL;

  return (
    <main className="l-page">
      <ProsHero offers={offers} />
      <ProsShowcase />
      <ProsOrganise />
      <ProsTalk />
      <Download
        playUrl={playUrl}
        isPlayStore={Boolean(playStore)}
        heading={<>Crée ta page pro.<br /><em>Les pratiquants te trouvent.</em></>}
        lead="Télécharge l’app, puis Menu → Devenir pro. Tes offres sont en ligne dès la validation de ton compte."
      />
    </main>
  );
}
