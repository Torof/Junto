import FinalCTA from './components/final-cta';
import Footer from './components/footer';
import Hero from './components/hero';
import Organisation from './components/organisation';
import Sports from './components/sports';
import TwoWorlds from './components/two-worlds';
import UpcomingTrips from './components/upcoming-trips';

// Re-render at most every 5 min so the live outings section stays fresh.
export const revalidate = 300;

// Layered arc: Hero plants the concept (real map + real pins) → TwoWorlds
// (merged: the peer/pro duality, each world's full pitch under its own map)
// → Organisation (the four logistics pillars — what makes Junto an
// organizer, not a feed) → live outings → breadth → download.
export default function Home() {
  return (
    <main>
      <Hero />
      <TwoWorlds />
      <Organisation />
      <UpcomingTrips />
      <Sports />
      <FinalCTA />
      <Footer />
    </main>
  );
}
