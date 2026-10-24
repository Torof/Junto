import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { Camera } from 'expo-camera';
import { Linking } from 'react-native';
import { usePermissionPromptStore, type PermissionKind, type PermissionReason } from '@/store/permission-prompt-store';
import { registerPushToken } from '@/lib/push-token';

// The ONE way the app asks for a permission (Scott 2026-10-24): never on
// launch, only at the moment the user needs it, and always after an in-app
// card that says why (components/permission-prompt.tsx). The OS dialog opens
// only if they tap « Autoriser ». Background location keeps its own card
// (background-location-prompt.tsx), shown after joining a checked outing.

interface Status { granted: boolean; canAskAgain: boolean }

async function status(kind: PermissionKind): Promise<Status> {
  const r = kind === 'location'
    ? await Location.getForegroundPermissionsAsync()
    : kind === 'notifications'
      ? await Notifications.getPermissionsAsync()
      : await Camera.getCameraPermissionsAsync();
  return { granted: r.granted, canAskAgain: r.canAskAgain };
}

async function request(kind: PermissionKind): Promise<boolean> {
  const r = kind === 'location'
    ? await Location.requestForegroundPermissionsAsync()
    : kind === 'notifications'
      ? await Notifications.requestPermissionsAsync()
      : await Camera.requestCameraPermissionsAsync();
  return r.granted;
}

// Notifications are offered after an action, not asked for by it: a « Plus
// tard » is respected for a few days instead of returning at every join.
const NOTIF_LATER_KEY = 'junto_notif_later_at';
const NOTIF_LATER_MS = 3 * 24 * 60 * 60 * 1000;

async function notificationsSnoozed(): Promise<boolean> {
  try {
    const at = Number(await AsyncStorage.getItem(NOTIF_LATER_KEY));
    return Number.isFinite(at) && at > 0 && Date.now() - at < NOTIF_LATER_MS;
  } catch {
    return false;
  }
}

export async function askPermission(kind: PermissionKind, reason: PermissionReason): Promise<boolean> {
  const store = usePermissionPromptStore.getState();
  let current: Status;
  try {
    current = await status(kind);
  } catch {
    return false;
  }
  if (current.granted) {
    if (kind === 'location') store.setLocationGranted(true);
    return true;
  }

  if (kind === 'notifications') {
    // Blocked for good: the notifications screen carries its own banner —
    // no card after every action. Snoozed: wait it out.
    if (!current.canAskAgain || await notificationsSnoozed()) return false;
  }

  const blocked = !current.canAskAgain;
  const allow = await store.open({ kind, reason, blocked });
  if (!allow) {
    if (kind === 'notifications') AsyncStorage.setItem(NOTIF_LATER_KEY, String(Date.now())).catch(() => {});
    return false;
  }
  if (blocked) {
    Linking.openSettings().catch(() => {});
    return false;
  }

  let granted = false;
  try {
    granted = await request(kind);
  } catch {
    granted = false;
  }
  if (granted && kind === 'location') store.setLocationGranted(true);
  if (granted && kind === 'notifications') void registerPushToken();
  return granted;
}
