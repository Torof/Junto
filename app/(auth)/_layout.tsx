import { useEffect, useMemo, useState } from 'react';
import { Stack } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { usePresenceGeoWatcher } from '@/hooks/use-presence-geo-watcher';
import { usePresenceGeofences } from '@/hooks/use-presence-geofences';
import { BackgroundLocationPrompt, shouldAskForBackgroundLocation } from '@/components/background-location-prompt';

export default function AuthLayout() {
  const colors = useColors();
  const screenOptions = useMemo(() => ({
    headerStyle: { backgroundColor: colors.background },
    headerTintColor: colors.textPrimary,
    contentStyle: { backgroundColor: colors.background },
  }), [colors]);

  usePresenceGeoWatcher(true);
  usePresenceGeofences(true);

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
        <Stack.Screen name="conversation/[id]" options={{ title: '' }} />
        <Stack.Screen name="admin/moderation" options={{ title: 'Moderation' }} />
        <Stack.Screen name="create-alert" />
        <Stack.Screen name="legal/terms" options={{ title: '' }} />
        <Stack.Screen name="legal/privacy" options={{ title: '' }} />
        <Stack.Screen name="rate-participants/[id]" options={{ title: '' }} />
        <Stack.Screen name="peer-review/[id]" options={{ title: '' }} />
      </Stack>
      <BackgroundLocationPrompt visible={showBgLocationPrompt} onClose={() => setShowBgLocationPrompt(false)} />
    </>
  );
}
