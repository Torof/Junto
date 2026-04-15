import '@/i18n';
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

    const inAuthGroup = segments[0] === '(auth)';
    const inOnboarding = segments[0] === '(visitor)' && (segments as string[])[1] === 'onboarding';
    const inSuspended = segments[0] === '(visitor)' && (segments as string[])[1] === 'suspended';

    if (isAuthenticated && isSuspended) {
      if (!inSuspended) router.replace('/(visitor)/suspended');
    } else if (isAuthenticated && needsOnboarding) {
      if (!inOnboarding) router.replace('/(visitor)/onboarding');
    } else if (isAuthenticated && !needsOnboarding) {
      if (!inAuthGroup) router.replace('/(auth)/(tabs)/carte');
    } else if (!isAuthenticated) {
      if (inAuthGroup || inSuspended) router.replace('/(visitor)');
    }

    setIsReady(true);

    // Trigger activity status transitions once per session (no pg_cron available)
    if (isAuthenticated && !transitionRan.current) {
      transitionRan.current = true;
      void supabase.rpc('check_activity_transitions' as 'accept_tos');
    }
  }, [isLoading, isAuthenticated, needsOnboarding, segments, router]);

  // Re-run transition check when app returns to foreground
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active' && isAuthenticated) {
        void supabase.rpc('check_activity_transitions' as 'accept_tos');
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

export default function RootLayout() {
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

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
