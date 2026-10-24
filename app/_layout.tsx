import '@/i18n';
// Side-effect imports: TaskManager.defineTask must run on every app boot
// (including headless wakes from geofence Enter events, BG push delivery,
// and foreground-service location updates), so the task modules load
// from the root layout, not the auth-only layout.
import '@/lib/presence-geofence-task';
import '@/lib/presence-location-task';
import '@/lib/notification-bg-task';
import { useEffect, useState, useRef } from 'react';
import { Slot, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AppState, View } from 'react-native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { useAuth } from '@/hooks/use-auth';
import { useNetworkAwareness } from '@/hooks/use-network';
import { usePushNotifications } from '@/hooks/use-push-notifications';
import { useMessageStore } from '@/store/message-store';
import { useMapStyleStore } from '@/store/map-style-store';
import { useClusterStyleStore } from '@/store/cluster-style-store';
import { useFontStore } from '@/store/font-store';
import { LogoSpinner } from '@/components/logo-spinner';
import { ThemeProvider, useResolvedTheme } from '@/components/theme-provider';
import { ErrorBoundary } from '@/components/error-boundary';
import { PermissionPrompt } from '@/components/permission-prompt';
import { useColors } from '@/hooks/use-theme';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // 60s: long enough to cover screen-switch remounts, short enough
      // that returning to a tab shows fresh data. The previous 5min
      // window made re-visited screens feel stale (prod audit D).
      staleTime: 1000 * 60,
      gcTime: 1000 * 60 * 5,
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
  const loadClusterStyle = useClusterStyleStore((s) => s.load);
  const initFont = useFontStore((s) => s.init);
  const fontReady = useFontStore((s) => s.ready);

  useEffect(() => {
    loadReadState();
    loadMapStyle();
    loadClusterStyle();
    initFont();
  }, [loadReadState, loadMapStyle, loadClusterStyle, initFont]);

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
    const inResetPassword = inVisitorGroup && (segments as string[])[1] === 'reset-password';

    // Recovery flow: verifyOtp creates a real session, which would normally
    // bounce an authenticated user into (auth). Pin them to the password
    // form until they submit (which signs them out) or back out manually.
    if (inResetPassword) {
      setIsReady(true);
      return;
    }

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

    // Statuses move server-side every minute (pg_cron, mig 00491): just
    // refresh what this session shows once it is authenticated.
    if (isAuthenticated && !transitionRan.current) {
      transitionRan.current = true;
      void queryClient.invalidateQueries({ queryKey: ['activities'] });
    }
  }, [isLoading, isAuthenticated, needsOnboarding, segments, router]);

  // Refresh statuses when the app returns to foreground (the server moves them).
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active' && isAuthenticated) {
        void queryClient.invalidateQueries({ queryKey: ['activities'] });
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
      <PermissionPrompt />
      {/* The font gate keeps the first screen from flashing in the system font. */}
      {(isLoading || !isReady || !fontReady) && (
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
      <ErrorBoundary>
        <SafeAreaProvider>
          <ThemeProvider>
            <QueryClientProvider client={queryClient}>
              <BottomSheetModalProvider>
                <AuthGate />
              </BottomSheetModalProvider>
            </QueryClientProvider>
          </ThemeProvider>
        </SafeAreaProvider>
      </ErrorBoundary>
    </GestureHandlerRootView>
  );
}

export default RootLayout;
