import '@/i18n';
import { initSentry, wrap } from '@/lib/sentry';
initSentry();
import { useEffect, useState, useRef } from 'react';
import { Slot, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AppState, View, ActivityIndicator, StyleSheet } from 'react-native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useAuth } from '@/hooks/use-auth';
import { useNetworkAwareness } from '@/hooks/use-network';
import { usePushNotifications } from '@/hooks/use-push-notifications';
import { supabase } from '@/services/supabase';
import { useMessageStore } from '@/store/message-store';
import { colors } from '@/constants/theme';

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

  useEffect(() => {
    loadReadState();
  }, [loadReadState]);

  useEffect(() => {
    if (isLoading) return;

    // Cold-start guard: on the very first render, expo-router may not have
    // processed the incoming deep link yet (segments will be empty). Wait
    // until segments resolves to avoid redirecting away from the deep link.
    if (segments.length === 0) {
      setIsReady(true);
      return;
    }

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

  if (isLoading || !isReady) {
    return (
      <View style={styles.loading}>
        <StatusBar style="light" />
        <ActivityIndicator size="large" color={colors.cta} />
      </View>
    );
  }

  return (
    <>
      <StatusBar style="light" />
      <Slot />
    </>
  );
}

function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <QueryClientProvider client={queryClient}>
          <AuthGate />
        </QueryClientProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

export default wrap(RootLayout);

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
