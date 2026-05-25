import * as SecureStore from 'expo-secure-store';

const DEVICE_ID_KEY = 'junto.push.deviceId';

// RFC 4122 v4 UUID without an extra dep.
function generateUuid(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// Persisted in SecureStore so the same physical install reports the
// same device_id across token rotations + sign-outs. Shared by the
// push registration hook and the sign-out / permission-denied flows
// that need to revoke a previously-registered token.
export async function getOrCreateDeviceId(): Promise<string> {
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

// Read-only variant used by sign-out + permission-denied paths. We
// don't want to create a fresh device_id at sign-out time (a freshly
// generated one would never match a server-side row, so the revoke
// would be a guaranteed no-op). Returns null if no device_id is
// persisted — caller skips the revoke RPC in that case.
export async function readDeviceId(): Promise<string | null> {
  try {
    return await SecureStore.getItemAsync(DEVICE_ID_KEY);
  } catch {
    return null;
  }
}
