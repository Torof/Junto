import FinalCTA from './components/final-cta';
import Footer from './components/footer';
import Hero from './components/hero';
import Pillars from './components/pillars';
import Pro from './components/pro';
import Screenshots from './components/screenshots';
import Sports from './components/sports';
import UpcomingTrips from './components/upcoming-trips';

// Re-render at most every 5 min so the live outings section stays fresh.
export const revalidate = 300;

// Arc (reorg 2026-06-11): hook → how it works → live proof → who it's
// also for (pros) → breadth → see the app → download. Pillars absorbed
// the old HowItWorks (both pitched the same find/create/organize triad).
export default function Home() {
  return (
    <main>
      <Hero />
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
