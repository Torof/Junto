import '@/i18n';
import { initSentry, wrap } from '@/lib/sentry';
initSentry();
import { useEffect, useState, useRef } from 'react';
import { Slot, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AppState, View } from 'react-native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useAuth } from '@/hooks/use-auth';
import { useNetworkAwareness } from '@/hooks/use-network';
import { usePushNotifications } from '@/hooks/use-push-notifications';
import { supabase } from '@/services/supabase';
import { useMessageStore } from '@/store/message-store';
import { useMapStyleStore } from '@/store/map-style-store';
import { LogoSpinner } from '@/components/logo-spinner';
import { ThemeProvider, useResolvedTheme } from '@/components/theme-provider';
import { useColors } from '@/hooks/use-theme';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,
      retry: 2,
    },
  },
});

function AuthGate() {
  useNetworkAwareness();
  const { isLoading, isAuthenticated, needsOnboarding, isSuspended } = useAuth();
  usePushNotifications(isAuthenticated && !needsOnboarding && !isSuspended);
  const segments = useSegments();
  const router = useRouter();
  const [isReady, setIsReady] = useState(false);
  const transitionRan = useRef(false);
  const { loadReadState } = useMessageStore();
  const loadMapStyle = useMapStyleStore((s) => s.load);

  useEffect(() => {
    loadReadState();
    loadMapStyle();
  }, [loadReadState, loadMapStyle]);

  useEffect(() => {
    if (isLoading) return;

    // Cold-start guard: on the very first render, expo-router may not have
    // processed the incoming deep link yet (segments will be empty). Wait
    // until segments resolves so we don't redirect away from the deep link.
    if ((segments as string[]).length === 0) return;

    const inAuthGroup = segments[0] === '(auth)';
    const inVisitorGroup = segments[0] === '(visitor)';
    const inOnboarding = inVisitorGroup && (segments as string[])[1] === 'onboarding';
    const inSuspended = inVisitorGroup && (segments as string[])[1] === 'suspended';

    // Determine whether the user is already on the right route. If not, we
    // issue a redirect and keep the loading overlay up until the segments
    // update — prevents a flash of the wrong screen on cold start.
    let onCorrectRoute: boolean;
    if (isAuthenticated && isSuspended) {
      onCorrectRoute = inSuspended;
      if (!inSuspended) router.replace('/(visitor)/suspended');
    } else if (isAuthenticated && needsOnboarding) {
      onCorrectRoute = inOnboarding;
      if (!inOnboarding) router.replace('/(visitor)/onboarding');
    } else if (isAuthenticated && !needsOnboarding) {
      onCorrectRoute = inAuthGroup;
      if (!inAuthGroup) router.replace('/(auth)/(tabs)/carte');
    } else {
      onCorrectRoute = !inAuthGroup && !inSuspended;
      if (inAuthGroup || inSuspended) router.replace('/(visitor)');
    }

    if (onCorrectRoute) setIsReady(true);

    // Trigger activity status transitions once per session (no pg_cron available)
    if (isAuthenticated && !transitionRan.current) {
      transitionRan.current = true;
      (async () => {
        await supabase.rpc('check_activity_transitions' as 'accept_tos');
        await queryClient.invalidateQueries({ queryKey: ['activities'] });
      })();
    }
  }, [isLoading, isAuthenticated, needsOnboarding, segments, router]);

  // Re-run transition check when app returns to foreground
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active' && isAuthenticated) {
        (async () => {
          await supabase.rpc('check_activity_transitions' as 'accept_tos');
          await queryClient.invalidateQueries({ queryKey: ['activities'] });
        })();
      }
    });
    return () => sub.remove();
  }, [isAuthenticated]);

  // Always render Slot so expo-router can populate segments; overlay the
  // loading screen on top until we're sure we're on the correct route.
  // This avoids the flash of default visitor content on cold start.
  const resolvedTheme = useResolvedTheme();
  const themeColors = useColors();

  return (
    <>
      <StatusBar style={resolvedTheme === 'dark' ? 'light' : 'dark'} />
      <Slot />
      {(isLoading || !isReady) && (
        <View style={{
          position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
          backgroundColor: themeColors.background,
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 10,
        }} pointerEvents="auto">
          <LogoSpinner size={64} />
        </View>
      )}
    </>
  );
}

function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <ThemeProvider>
          <QueryClientProvider client={queryClient}>
            <AuthGate />
          </QueryClientProvider>
        </ThemeProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

export default wrap(RootLayout);
