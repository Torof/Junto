import '@/i18n';
import { useEffect, useState } from 'react';
import { Slot, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useAuth } from '@/hooks/use-auth';
import { useNetworkAwareness } from '@/hooks/use-network';
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
  const { isLoading, isAuthenticated, needsOnboarding } = useAuth();
  const segments = useSegments();
  const router = useRouter();
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (isLoading) return;

    const inAuthGroup = segments[0] === '(auth)';
    const inOnboarding = segments[0] === '(visitor)' && (segments as string[])[1] === 'onboarding';

    if (isAuthenticated && needsOnboarding && !inOnboarding) {
      router.replace('/(visitor)/onboarding');
    } else if (isAuthenticated && !needsOnboarding && !inAuthGroup) {
      router.replace('/(auth)/(tabs)/carte');
    } else if (!isAuthenticated && inAuthGroup) {
      router.replace('/(visitor)');
    }

    setIsReady(true);
  }, [isLoading, isAuthenticated, needsOnboarding, segments, router]);

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
    <QueryClientProvider client={queryClient}>
      <AuthGate />
    </QueryClientProvider>
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
