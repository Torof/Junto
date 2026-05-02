import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import { trace, captureInfo } from './sentry';
import { startPresenceForegroundService } from './presence-foreground-service';

// Headless task that fires when a data-carrying push lands while the app
// is killed/backgrounded. Registered via Notifications.registerTaskAsync.
//
// Purpose: when the server emits 'presence_pre_warning' at T-15min, this
// task starts the foreground location service so we can auto-validate
// presence even on Samsung/Xiaomi/etc. where geofence Enter delivery is
// unreliable for closed apps.
export const BACKGROUND_NOTIFICATION_TASK = 'junto.bg-notification';

interface BgNotificationPayload {
  notification?: {
    data?: Record<string, unknown> | string;
    request?: {
      content?: {
        data?: Record<string, unknown>;
      };
    };
  };
}

function readNotificationData(payload: unknown): Record<string, unknown> | null {
  const p = payload as BgNotificationPayload;
  // Android FCM data-only path: data is the top-level dict on the
  // notification field. iOS APNs path: data lives under request.content.
  // Belt-and-suspenders: try both. Some Android skins also send the data
  // as a JSON string that needs parsing.
  let raw: unknown = p?.notification?.request?.content?.data ?? p?.notification?.data;
  if (typeof raw === 'string') {
    try {
      raw = JSON.parse(raw);
    } catch {
      return null;
    }
  }
  if (raw && typeof raw === 'object') return raw as Record<string, unknown>;
  return null;
}

TaskManager.defineTask(BACKGROUND_NOTIFICATION_TASK, async ({ data, error }) => {
  if (error) {
    trace('notif.bg', 'task fired with error', { reason: String(error) });
    return;
  }

  const payload = readNotificationData(data);
  if (!payload) {
    trace('notif.bg', 'task fired without parseable data');
    return;
  }

  const type = typeof payload.type === 'string' ? payload.type : null;
  captureInfo('notif.bg', 'task fired', { type });

  // Only one type triggers the foreground service today: the T-15min
  // pre-warning. Other notification types still wake this handler on
  // some platforms (Android queues the data delivery alongside the
  // visual) but we no-op for them.
  if (type === 'presence_pre_warning') {
    await startPresenceForegroundService();
  }
});

// Register at module load so the OS knows about the task before any
// push lands. Idempotent — Expo handles redundant registers.
Notifications.registerTaskAsync(BACKGROUND_NOTIFICATION_TASK).catch((err) => {
  trace('notif.bg', 'registerTaskAsync failed', {
    message: err instanceof Error ? err.message : String(err),
  });
});
