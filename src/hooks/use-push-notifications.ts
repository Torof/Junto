import { useEffect, useRef, useState } from 'react';
import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { useRouter, useRootNavigationState } from 'expo-router';
import { supabase } from '@/services/supabase';
import { pushTokenService } from '@/services/push-token-service';
import { getOrCreateDeviceId } from '@/utils/device-id';
import { colors } from '@/constants/theme';

// Module-level so hook remounts (auth changes) never re-route the same tap.
let lastRoutedResponseId: string | null = null;

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
  // Cold-start tap replay must wait for the navigator to actually exist:
  // a fixed timer raced auth resolution — pushing before the root state
  // was ready made the pushed screen the ROOT (no tab bar, no back arrow;
  // Scott's notification-tap bug, 2026-07-10 — the deep-link anchor fix
  // didn't cover this imperative path).
  const rootNavigationState = useRootNavigationState();
  const navReady = rootNavigationState?.key != null;
  const [coldResponse, setColdResponse] = useState<Notifications.NotificationResponse | null>(null);

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
    // Handle taps on received notifications. `handle` is shared between the
    // live listener AND the cold-start path: when the app is LAUNCHED by the
    // tap, the response fires before this listener exists, so we replay it
    // via getLastNotificationResponseAsync (deduped — module-level marker —
    // so a re-mount or a stale "last response" never routes twice).
    const handle = (response: Notifications.NotificationResponse) => {
      const responseId = `${response.notification.request.identifier}:${response.notification.date}`;
      if (lastRoutedResponseId === responseId) return;
      lastRoutedResponseId = responseId;
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
    };
    const sub = Notifications.addNotificationResponseReceivedListener(handle);
    // Cold start: capture the tap that launched the app; the effect below
    // replays it only once the navigator is ready AND the user is authed
    // (dedup marker makes a double-handle harmless).
    Notifications.getLastNotificationResponseAsync()
      // prev ?? response: keep the first capture — a fresh object identity
      // on every effect re-run would loop render <-> effect forever.
      .then((response) => { if (response) setColdResponse((prev) => prev ?? response); })
      .catch(() => {});

    if (coldResponse && navReady && enabled) {
      handle(coldResponse);
    }

    return () => { sub.remove(); };
  }, [router, coldResponse, navReady, enabled]);
}
