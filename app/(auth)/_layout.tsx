import { useEffect, useMemo, useState } from 'react';
import { Redirect, Stack } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { useAuth } from '@/hooks/use-auth';
import { usePresenceGeofences } from '@/hooks/use-presence-geofences';
import { usePresenceOfflineFlusher } from '@/hooks/use-presence-offline-flusher';
import { BackgroundLocationPrompt, shouldAskForBackgroundLocation } from '@/components/background-location-prompt';

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

  // Second-layer guard: if the root AuthGate is mid-resolve when a back-
  // button or transition lands here, intercept suspended users before any
  // child screen renders. AUDIT_SECURITY_2 M6.
  if (isSuspended) {
    return <Redirect href="/(visitor)/suspended" />;
  }
  const screenOptions = useMemo(() => ({
    headerStyle: { backgroundColor: colors.background },
    headerTintColor: colors.textPrimary,
    contentStyle: { backgroundColor: colors.background },
  }), [colors]);

  usePresenceGeofences(true);
  usePresenceOfflineFlusher();

  const [showBgLocationPrompt, setShowBgLocationPrompt] = useState(false);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const should = await shouldAskForBackgroundLocation();
      if (!cancelled && should) setShowBgLocationPrompt(true);
    })();
    return () => { cancelled = true; };
  }, []);

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
      <BackgroundLocationPrompt visible={showBgLocationPrompt} onClose={() => setShowBgLocationPrompt(false)} />
    </>
  );
}
