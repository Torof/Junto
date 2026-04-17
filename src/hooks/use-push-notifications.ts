import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { useRouter } from 'expo-router';
import { supabase } from '@/services/supabase';

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
      lightColor: '#F4642A',
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
      await supabase.rpc('register_push_token' as 'accept_tos', {
        p_token: token,
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
      if (data?.type === 'contact_request') {
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
