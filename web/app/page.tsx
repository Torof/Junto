import './components/landing/landing.css';
import Hero from './components/landing/hero';
import DeparturesBoard from './components/landing/departures-board';
import LaunchDemo from './components/landing/launch-demo';
import Partners from './components/landing/partners';
import ChannelsTrust from './components/landing/channels-trust';
import Pros from './components/landing/pros';
import Download from './components/landing/download';
import { fetchOffers, fetchUpcomingOutings } from './components/landing/data';
import { mockOffers, mockOutings } from './components/landing/mock-data';
import { APK_DOWNLOAD_URL } from '@/lib/download';

// Launch window: while the real reads come back with fewer rows than this,
// illustrative rows fill the board and the offers (Scott 2026-10-17). Past
// the threshold the page is fully dynamic — nothing to flip.
const MOCK_BELOW = 4;

// Re-render at most every 5 min so the live board and offers stay fresh.
export const revalidate = 300;

// Landing v4 « la carte vivante » (maquette validée 2026-10-17):
// hero (real map, pins, four paths) → 1 Rejoins (live board) → 2 Lance
// (demo form + what happens inside) → 3 Partenaires → canaux + confiance →
// 4 Pros (live offers) → Télécharger + footer.
export default async function Home() {
  const [realOutings, realOffers] = await Promise.all([fetchUpcomingOutings(12), fetchOffers(12)]);
  const outings = (realOutings.length >= MOCK_BELOW ? realOutings : [...realOutings, ...mockOutings()])
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at));
  const offers = realOffers.length >= MOCK_BELOW ? realOffers : [...realOffers, ...mockOffers()];
  const playStore = process.env.NEXT_PUBLIC_PLAY_STORE_URL?.trim();
  const playUrl = playStore && playStore.length > 0 ? playStore : APK_DOWNLOAD_URL;

  return (
    <main className="l-page">
      <Hero outings={outings} offers={offers} playUrl={playUrl} />
      <DeparturesBoard outings={outings} />
      <LaunchDemo />
      <Partners />
      <ChannelsTrust />
      <Pros offers={offers} />
      <Download playUrl={playUrl} isPlayStore={Boolean(playStore)} />
    </main>
  );
}
