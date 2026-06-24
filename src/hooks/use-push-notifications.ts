import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { useRouter } from 'expo-router';
import { supabase } from '@/services/supabase';
import { pushTokenService } from '@/services/push-token-service';
import { getOrCreateDeviceId } from '@/utils/device-id';
import { colors } from '@/constants/theme';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

// Returns the push token on success, or one of two distinct "no
// token" reasons so the caller can decide whether to revoke a
// previously-registered token.
type RegisterResult =
  | { kind: 'token'; token: string }
  | { kind: 'denied' } // OS-level permission denied
  | { kind: 'skip' };  // not a real device or no projectId — nothing to revoke

async function registerForPushAsync(): Promise<RegisterResult> {
  if (!Device.isDevice) return { kind: 'skip' };

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
  if (finalStatus !== 'granted') return { kind: 'denied' };

  const projectId = Constants.expoConfig?.extra?.eas?.projectId;
  if (!projectId) return { kind: 'skip' };

  const token = await Notifications.getExpoPushTokenAsync({ projectId });
  return { kind: 'token', token: token.data };
}

export function usePushNotifications(enabled: boolean) {
  const router = useRouter();
  const registered = useRef(false);

  useEffect(() => {
    if (!enabled || registered.current) return;
    registered.current = true;

    (async () => {
      const result = await registerForPushAsync();
      if (result.kind === 'token') {
        const deviceId = await getOrCreateDeviceId();
        await supabase.rpc('register_push_token' as 'accept_tos', {
          p_token: result.token,
          p_device_id: deviceId,
        } as unknown as never);
      } else if (result.kind === 'denied') {
        // OS-level permission denied (either freshly refused or the
        // user revoked it since last launch). If we registered a
        // token in a previous session, it's now useless — revoke it
        // server-side so send-push stops targeting this device.
        await pushTokenService.revokeForCurrentDevice();
      }
      // 'skip': not a real device or no projectId — nothing to revoke.
    })();
  }, [enabled]);

  useEffect(() => {
    // Handle taps on received notifications
    const sub = Notifications.addNotificationResponseReceivedListener((response) => {
      const data = response.notification.request.content.data as {
        activity_id?: string;
        conversation_id?: string;
        pro_id?: string;
        offering_id?: string;
        type?: string;
      };
      // Peer-review pushes land on the review screen (mirrors the in-app
      // notification router) — not the activity detail.
      if ((data?.type === 'rate_participants' || data?.type === 'peer_review_closing') && data.activity_id) {
        router.push(`/(auth)/peer-review/${data.activity_id}`);
      }
      // Seat-request push: land the driver on the chat thread (00206
      // seeds the conversation on request creation) so they can talk
      // before the accept/decline. Falls back to the requests tab for
      // older notifs that don't carry conversation_id, and for the
      // edge case where requester+driver were blocked at request time.
      else if (data?.type === 'seat_request' && data.conversation_id) {
        router.push(`/(auth)/conversation/${data.conversation_id}`);
      } else if (data?.type === 'contact_request' || data?.type === 'seat_request') {
        router.push('/(auth)/(tabs)/messagerie?tab=requests');
      } else if (data?.type === 'contact_request_accepted') {
        router.push('/(auth)/(tabs)/messagerie');
      } else if (data?.conversation_id) {
        router.push(`/(auth)/conversation/${data.conversation_id}`);
      } else if (data?.offering_id) {
        // review_received / review_reply on an offering
        router.push(`/(auth)/pro/offering/${data.offering_id}`);
      } else if (data?.pro_id) {
        // review_received / review_reply on the pro page
        router.push(`/(auth)/pro/${data.pro_id}`);
      } else if (data?.activity_id) {
        router.push(`/(auth)/activity/${data.activity_id}`);
      }
    });
    return () => sub.remove();
  }, [router]);
}
