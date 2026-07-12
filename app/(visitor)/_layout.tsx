import { Stack } from 'expo-router';

// Native Stack (not a bare Slot) so each visitor screen gets a full-height
// native screen container — the same treatment the (auth) group's Stack
// gives, without which the Mapbox map on the teaser screen mis-measured its
// height and clipped pins at a line ~30% up (Scott 2026-07-12).
export default function VisitorLayout() {
  return <Stack screenOptions={{ headerShown: false }} />;
}
