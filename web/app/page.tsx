import FinalCTA from './components/final-cta';
import Footer from './components/footer';
import Hero from './components/hero';
import HowItWorks from './components/how-it-works';
import Pillars from './components/pillars';
import Pro from './components/pro';
import Screenshots from './components/screenshots';
import Sports from './components/sports';
import UpcomingTrips from './components/upcoming-trips';

// Re-render at most every 5 min so the live outings section stays fresh.
export const revalidate = 300;

export default function Home() {
  return (
    <main>
      <Hero />
      <Pillars />
      <HowItWorks />
      <UpcomingTrips />
      <Screenshots />
      <Sports />
      <Pro />
      <FinalCTA />
      <Footer />
    </main>
  );
}
