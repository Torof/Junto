import FinalCTA from './components/final-cta';
import Footer from './components/footer';
import Hero from './components/hero';
import Particuliers from './components/particuliers';
import Pro from './components/pro';
import Screenshots from './components/screenshots';
import Sports from './components/sports';
import TwoWorlds from './components/two-worlds';
import UpcomingTrips from './components/upcoming-trips';

// Re-render at most every 5 min so the live outings section stays fresh.
export const revalidate = 300;

// Layered arc: Hero plants the concept → Screenshots show the app right
// away (see it before reading about it) → TwoWorlds frames the peer/pro
// duality at a glance (orange vs blue, the page-wide color language) →
// community deep-dive (light: how it works + live outings) → pro deep-dive
// (dark zone) → breadth → download.
export default function Home() {
  return (
    <main>
      <Hero />
      <Screenshots />
      <TwoWorlds />
      <Particuliers />
      <UpcomingTrips />
      <Pro />
      <Sports />
      <FinalCTA />
      <Footer />
    </main>
  );
}
