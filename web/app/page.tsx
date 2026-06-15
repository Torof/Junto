import FinalCTA from './components/final-cta';
import Footer from './components/footer';
import Hero from './components/hero';
import Pillars from './components/pillars';
import Pro from './components/pro';
import Screenshots from './components/screenshots';
import Sports from './components/sports';
import TwoWorlds from './components/two-worlds';
import UpcomingTrips from './components/upcoming-trips';

// Re-render at most every 5 min so the live outings section stays fresh.
export const revalidate = 300;

// Layered arc (2026-06-11): Hero plants the concept → TwoWorlds frames
// the peer/pro duality at a glance (orange vs blue, the page-wide color
// language) → community deep-dive (light: how it works + live outings)
// → pro deep-dive (dark zone) → breadth → see the app → download.
export default function Home() {
  return (
    <main>
      <Hero />
      <TwoWorlds />
      <Pillars />
      <UpcomingTrips />
      <Pro />
      <Sports />
      <Screenshots />
      <FinalCTA />
      <Footer />
    </main>
  );
}
