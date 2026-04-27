import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import * as SecureStore from 'expo-secure-store';
import Constants from 'expo-constants';
import { useRouter } from 'expo-router';
import { supabase } from '@/services/supabase';
import { colors } from '@/constants/theme';

const DEVICE_ID_KEY = 'junto.push.deviceId';

// RFC 4122 v4 UUID without an extra dep. Persisted in SecureStore so the
// same physical install reports the same device_id across token rotations.
function generateUuid(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

async function getOrCreateDeviceId(): Promise<string> {
  try {
    const existing = await SecureStore.getItemAsync(DEVICE_ID_KEY);
    if (existing) return existing;
  } catch {
    // SecureStore can fail on simulators / first-launch races — fall through.
  }
  const fresh = generateUuid();
  try {
    await SecureStore.setItemAsync(DEVICE_ID_KEY, fresh);
  } catch {
    // Best-effort: even if persistence fails, we still pass *some* device_id.
  }
  return fresh;
}

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

async function registerForPushAsync(): Promise<string | null> {
  if (!Device.isDevice) return null;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'default',
      importance: Notifications.AndroidImportance.DEFAULT,
      lightColor: colors.cta,
    });
  }

  const { status: existing } = await Notifications.getPermissionsAsync();
  let finalStatus = existing;
  if (existing !== 'granted') {
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }
  if (finalStatus !== 'granted') return null;

  const projectId = Constants.expoConfig?.extra?.eas?.projectId;
  if (!projectId) return null;

  const token = await Notifications.getExpoPushTokenAsync({ projectId });
  return token.data;
}

export function usePushNotifications(enabled: boolean) {
  const router = useRouter();
  const registered = useRef(false);

  useEffect(() => {
    if (!enabled || registered.current) return;
    registered.current = true;

    (async () => {
      const token = await registerForPushAsync();
      if (!token) return;
      const deviceId = await getOrCreateDeviceId();
      await supabase.rpc('register_push_token' as 'accept_tos', {
        p_token: token,
        p_device_id: deviceId,
      } as unknown as never);
    })();
  }, [enabled]);

  useEffect(() => {
    // Handle taps on received notifications
    const sub = Notifications.addNotificationResponseReceivedListener((response) => {
      const data = response.notification.request.content.data as {
        activity_id?: string;
        conversation_id?: string;
        type?: string;
      };
      if (data?.type === 'contact_request' || data?.type === 'seat_request') {
        router.push('/(auth)/(tabs)/messagerie?tab=requests');
      } else if (data?.type === 'contact_request_accepted') {
        router.push('/(auth)/(tabs)/messagerie');
      } else if (data?.conversation_id) {
        router.push(`/(auth)/conversation/${data.conversation_id}`);
      } else if (data?.activity_id) {
        router.push(`/(auth)/activity/${data.activity_id}`);
      }
    });
    return () => sub.remove();
  }, [router]);
}
