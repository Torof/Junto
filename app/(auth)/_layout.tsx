import { Stack } from 'expo-router';
import { colors } from '@/constants/theme';

export default function AuthLayout() {
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.background },
        headerTintColor: colors.textPrimary,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="create/step1" options={{ headerShown: false, presentation: 'modal' }} />
      <Stack.Screen name="create/step2" options={{ headerShown: false, presentation: 'modal' }} />
      <Stack.Screen name="create/step3" options={{ headerShown: false, presentation: 'modal' }} />
      <Stack.Screen name="create/step4" options={{ headerShown: false, presentation: 'modal' }} />
      <Stack.Screen name="activity/[id]" options={{ headerShown: false }} />
      <Stack.Screen name="invite/[token]" options={{ headerShown: false }} />
      <Stack.Screen name="edit/[id]" options={{ headerShown: false }} />
      <Stack.Screen name="profile/[id]" options={{ title: '' }} />
      <Stack.Screen name="conversation/[id]" options={{ title: '' }} />
      <Stack.Screen name="confirm-presence/[id]" options={{ title: '' }} />
    </Stack>
  );
}
