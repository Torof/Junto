import { useEffect, useMemo, useState } from 'react';
import { Redirect, Stack } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { useAuth } from '@/hooks/use-auth';
import { usePresenceGeofences } from '@/hooks/use-presence-geofences';
import { usePresenceOfflineFlusher } from '@/hooks/use-presence-offline-flusher';
import { BackgroundLocationPrompt, shouldAskForBackgroundLocation } from '@/components/background-location-prompt';

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
        <Stack.Screen name="admin/moderation" options={{ title: 'Moderation' }} />
        <Stack.Screen name="create-alert" />
        <Stack.Screen name="legal/terms" options={{ title: '' }} />
        <Stack.Screen name="legal/privacy" options={{ title: '' }} />
        <Stack.Screen name="peer-review/[id]" options={{ title: '' }} />
      </Stack>
      <BackgroundLocationPrompt visible={showBgLocationPrompt} onClose={() => setShowBgLocationPrompt(false)} />
    </>
  );
}
