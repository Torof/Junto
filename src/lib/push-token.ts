import { Platform } from 'react-native';
import * as Notifications from 'expo-notifications';
import * as Device from 'expo-device';
import Constants from 'expo-constants';
import { supabase } from '@/services/supabase';
import { getOrCreateDeviceId } from '@/utils/device-id';
import { colors } from '@/constants/theme';

// Registers this device's push token WITHOUT ever showing the OS dialog
// (lib/permissions.ts asks, at the moment it serves — Scott 2026-10-24).
// Android hands out its token without the display permission: a data-only push
// is what wakes the headless task that starts on-site presence detection, so
// the token is registered whatever the display permission (audit 2026-10-01).
// iOS needs the permission for a token at all.
export async function registerPushToken(): Promise<void> {
  if (!Device.isDevice) return;
  try {
    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'default',
        importance: Notifications.AndroidImportance.DEFAULT,
        lightColor: colors.cta,
      });
    }
    const { status } = await Notifications.getPermissionsAsync();
    if (Platform.OS !== 'android' && status !== 'granted') return;

    const projectId = Constants.expoConfig?.extra?.eas?.projectId;
    if (!projectId) return;
    const token = await Notifications.getExpoPushTokenAsync({ projectId });
    const deviceId = await getOrCreateDeviceId();
    await supabase.rpc('register_push_token', { p_token: token.data, p_device_id: deviceId });
  } catch {
    // Best effort — a failed registration retries on the next launch.
  }
}
