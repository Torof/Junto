import { useMemo } from 'react';
import { Redirect, Stack } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { useAuth } from '@/hooks/use-auth';
import { usePresenceGeofences } from '@/hooks/use-presence-geofences';
import { usePresenceOfflineFlusher } from '@/hooks/use-presence-offline-flusher';

// Deep links (share links, notification taps on a cold start) land directly
// on activity/[id] & co — without an anchor the stack has NOTHING beneath
// the landed screen: no back arrow, no tab bar, the user is stranded on a
// single page (Scott's bug, 2026-07-10). Anchoring on (tabs) makes the
// router mount the tabs first, so the deep-linked page gets a back arrow
// that leads home.
export const unstable_settings = {
  anchor: '(tabs)',
};

export default function AuthLayout() {
  const colors = useColors();
  const { isSuspended } = useAuth();

  const screenOptions = useMemo(() => ({
    headerStyle: { backgroundColor: colors.background },
    headerShadowVisible: false,
    headerTintColor: colors.textPrimary,
    contentStyle: { backgroundColor: colors.background },
  }), [colors]);

  usePresenceGeofences(!isSuspended);
  usePresenceOfflineFlusher();

  // The background-location ask used to fire HERE, at the first authenticated
  // mount — i.e. straight after signup, before the user had seen a single
  // outing. Two reasons that was wrong (audit 2026-10-01): the system dialog is
  // a finite resource (the OS stops showing it after refusals), and at that
  // point the permission is inert anyway, since detection only watches outings
  // the user has already joined. It now fires on the first join of an outing
  // that needs presence — see activity-detail's handleJoin.

  // Second-layer guard: if the root AuthGate is mid-resolve when a back-
  // button or transition lands here, intercept suspended users before any
  // child screen renders. AUDIT_SECURITY_2 M6. AFTER the hooks: an early
  // return above them crashes React when isSuspended flips mid-session
  // (rules of hooks — audit 2026-09 M6).
  if (isSuspended) {
    return <Redirect href="/(visitor)/suspended" />;
  }

  return (
    <>
      <Stack screenOptions={screenOptions}>
        <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
        <Stack.Screen name="create/step1" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="create/step2" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="create/step3" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="create/step4" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="activity/[id]" options={{ title: '' }} />
        <Stack.Screen name="invite/[token]" options={{ headerShown: false }} />
        <Stack.Screen name="edit/[id]" options={{ headerShown: false }} />
        <Stack.Screen name="profile/[id]" options={{ title: '' }} />
        <Stack.Screen name="pro/[id]" options={{ title: '' }} />
        <Stack.Screen name="pro/edit" options={{ title: '', presentation: 'modal' }} />
        <Stack.Screen name="pro/offering/[id]" options={{ title: '' }} />
        <Stack.Screen name="pro/offering/edit" options={{ title: '', presentation: 'modal' }} />
        <Stack.Screen name="conversation/[id]" options={{ title: '' }} />
        <Stack.Screen name="admin/index" options={{ title: 'Administration' }} />
        <Stack.Screen name="admin/moderation" options={{ title: 'Modération' }} />
        <Stack.Screen name="admin/lookup" options={{ title: 'Recherche & modération' }} />
        <Stack.Screen name="create-alert" />
        <Stack.Screen name="create-group" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="my-contact" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="discovery-compose" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="discovery-zone" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="create-channel" options={{ headerShown: false, presentation: 'modal' }} />
        <Stack.Screen name="legal/terms" options={{ title: '' }} />
        <Stack.Screen name="legal/privacy" options={{ title: '' }} />
        <Stack.Screen name="peer-review/[id]" options={{ title: '' }} />
      </Stack>
    </>
  );
}
