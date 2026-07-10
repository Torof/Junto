import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from '@/services/supabase';
import { enqueueGeoEvent, isTerminalPresenceRejection } from './presence-offline-cache';
import { trace, captureInfo } from './sentry';

// Post-window Enters can repeat all day (GPS flicker at a 300m radius in
// broken terrain) and re-posting on the same notification id RE-ALERTS on
// Android (no setOnlyAlertOnce anywhere in expo-notifications) — dedup to
// one "détectée" notif per activity once the geo window is closed.
const POSTWINDOW_NOTIF_KEY = '@junto/presence-postwindow-notified';
const POSTWINDOW_NOTIF_TTL_MS = 30 * 60 * 60 * 1000;

async function shouldPostPostWindowNotif(activityId: string): Promise<boolean> {
  try {
    const raw = await AsyncStorage.getItem(POSTWINDOW_NOTIF_KEY);
    const map: Record<string, number> = raw ? JSON.parse(raw) : {};
    const now = Date.now();
    for (const key of Object.keys(map)) {
      const ts = map[key];
      if (ts == null || now - ts > POSTWINDOW_NOTIF_TTL_MS) delete map[key];
    }
    if (map[activityId] != null) return false;
    map[activityId] = now;
    await AsyncStorage.setItem(POSTWINDOW_NOTIF_KEY, JSON.stringify(map));
    return true;
  } catch {
    return true; // best-effort — worst case is one extra notif
  }
}

// Task name must be a constant defined at the top of a module that's imported
// at app startup (see _layout). Expo TaskManager requires the task to be
// registered before TaskManager.startGeofencingAsync runs.
export const PRESENCE_GEOFENCE_TASK = 'junto.presence-geofence';

// Headless GPS fix budget. The OS gives the task ~30s total; we cap the GPS
// wait at 8s so there's room for the RPC + slot updates. If we don't get a
// fresh fix in time, we enqueue for replay rather than guess from the
// region center (which would let stale-fused-location false positives
// silently auto-confirm presence).
const FRESH_FIX_TIMEOUT_MS = 8_000;
// Reject GPS samples too imprecise to safely auto-confirm. Mirrors the
// foreground watcher's threshold and stays inside the 300m server-side
// distance gate even at the radius edge.
const ACCURACY_THRESHOLD_M = 100;

async function getFreshFix(): Promise<Location.LocationObject | null> {
  try {
    return await Promise.race([
      Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High }),
      new Promise<null>((resolve) => setTimeout(() => resolve(null), FRESH_FIX_TIMEOUT_MS)),
    ]);
  } catch {
    return null;
  }
}

interface GeofenceEvent {
  eventType: Location.GeofencingEventType;
  region: Location.LocationRegion & { identifier?: string };
}

// Region identifier convention: `presence:<activity_id>:<lat>,<lng>:<startsAtMs>`
// (the last segment is absent on regions registered by pre-merge bundles —
// treat it as unknown and fall back to the old behavior).
// We only act on Enter events.
const WINDOW_BEFORE_MS = 15 * 60_000;
const WINDOW_AFTER_MS = 15 * 60_000;
TaskManager.defineTask(PRESENCE_GEOFENCE_TASK, async ({ data, error }) => {
  // Diagnostic: surface every task fire as a Sentry event so we can confirm
  // the OS is actually delivering geofence wakes when the app is closed.
  // Closed-app reliability on Android is OEM-dependent (Samsung/Xiaomi
  // aggressive kill, Doze throttling) — without this we have no way to
  // tell "OS never fired" from "fired but our code failed".
  captureInfo('presence.geofence', 'task fired', {
    has_error: !!error,
    has_data: !!data,
  });

  if (error) {
    trace('presence.geofence', 'task fired with error', { message: String(error) });
    return;
  }
  const { eventType, region } = (data ?? {}) as GeofenceEvent;
  if (eventType !== Location.GeofencingEventType.Enter) return;
  const id = region?.identifier ?? '';
  if (!id.startsWith('presence:')) return;

  const activityId = id.split(':')[1];
  if (!activityId) return;

  trace('presence.geofence', 'task: Enter event');

  const slotId = `presence-${activityId}`;

  // Regions are registered from T-2h so the OS can catch the outside→inside
  // transition, but the server only accepts anchors in T-15min..T+15min —
  // an Enter outside that window can never geo-validate anything (live RPC
  // and replay alike).
  const startsAtMs = Number(id.split(':')[3]);

  // Too early: don't fire a doomed RPC or poison the offline queue —
  // schedule the "détectée" notif to land at window open instead, so the
  // user opens the app right when the initial-state check can actually
  // confirm them.
  if (Number.isFinite(startsAtMs) && Date.now() < startsAtMs - WINDOW_BEFORE_MS) {
    trace('presence.geofence', 'task: Enter before window, deferring notif to window open');
    Notifications.scheduleNotificationAsync({
      identifier: slotId,
      content: {
        title: 'Présence détectée',
        body: "Tu es à portée de l'activité, valide ta présence.",
        data: { activity_id: activityId, type: 'presence_detected' },
        sound: true,
      },
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.DATE,
        date: new Date(startsAtMs - WINDOW_BEFORE_MS),
      },
    }).catch(() => {});
    return;
  }

  // Too late for geo: the anchor is past T+15min, so neither a live RPC nor
  // a cached replay of THIS event can succeed. Worse, enqueueing it can
  // evict a valid in-window event from the per-activity cap (GPS flicker at
  // a 300m radius produces repeated Enters all day while offline). QR
  // validation stays open until end+3h, so the notif is still worth showing
  // ONCE as a scan prompt — but nothing else, and never re-alerted on
  // every flicker episode.
  const geoWindowClosed = Number.isFinite(startsAtMs) && Date.now() > startsAtMs + WINDOW_AFTER_MS;

  if (geoWindowClosed) {
    if (await shouldPostPostWindowNotif(activityId)) {
      Notifications.scheduleNotificationAsync({
        identifier: slotId,
        content: {
          title: 'Présence détectée',
          body: "Tu es à portée de l'activité, valide ta présence.",
          data: { activity_id: activityId, type: 'presence_detected' },
          sound: true,
        },
        trigger: null,
      }).catch(() => {});
    }
    trace('presence.geofence', 'task: Enter after geo window, notif only (QR path remains)');
    return;
  }

  // First state: "Présence détectée". Same identifier across both states so
  // the OS slot is updated in place — never two notifs at once.
  Notifications.scheduleNotificationAsync({
    identifier: slotId,
    content: {
      title: 'Présence détectée',
      body: "Tu es à portée de l'activité, valide ta présence.",
      data: { activity_id: activityId, type: 'presence_detected' },
      sound: true,
    },
    trigger: null,
  }).catch(() => {});

  const capturedAt = new Date().toISOString();

  // Fetch a fresh high-accuracy GPS fix instead of trusting the region
  // center. Background-fused-location estimates can be minutes stale and
  // off by hundreds of meters (Doze + cell/wifi-only signals), so the OS
  // can fire Enter from a position that isn't actually inside the zone.
  // Sending the region center to the server bypasses the 150m distance
  // gate (distance to itself = 0) — a real GPS fix here lets the server
  // catch false positives.
  const fix = await getFreshFix();

  // Never enqueue coordinates we didn't measure. Replaying the REGION
  // CENTER hands the server a distance of exactly 0 and silently bypasses
  // its 150m gate — a stale-fused-location Enter fired from 2km away would
  // become a confirmed presence at the next flush. No fix in the headless
  // budget → no replayable evidence; the user still has the notif, the
  // initial-state check, the foreground service and QR.
  if (!fix) {
    trace('presence.geofence', 'task: no fresh fix, nothing replayable — notif only');
    return;
  }

  // A coarse fix is still a real measurement — enqueue THAT and let the
  // server compute the true distance at replay time.
  if (fix.coords.accuracy != null && fix.coords.accuracy > ACCURACY_THRESHOLD_M) {
    trace('presence.geofence', 'task: fix too coarse for live RPC, enqueue real fix for replay', {
      accuracy_m: Math.round(fix.coords.accuracy),
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: fix.coords.longitude,
      lat: fix.coords.latitude,
      captured_at: capturedAt,
    });
    return;
  }

  try {
    // Headless wakes can hit before supabase-js finishes restoring the
    // session from SecureStore. Explicitly await so the RPC carries a token.
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData?.session) {
      trace('presence.geofence', 'task: no session, enqueue for replay');
      await enqueueGeoEvent({
        activity_id: activityId,
        lng: fix.coords.longitude,
        lat: fix.coords.latitude,
        captured_at: capturedAt,
      });
      return;
    }

    const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
      p_activity_id: activityId,
      p_lng: fix.coords.longitude,
      p_lat: fix.coords.latitude,
      p_skip_push: true,
    } as unknown as { p_activity_id: string });

    if (!error) {
      trace('presence.geofence', 'task: RPC succeeded, replacing détectée with confirmée');
      // Dismiss the détectée notif and schedule confirmée under a DISTINCT
      // identifier. Re-scheduling on the same identifier is treated as an
      // update on Android — silent, no sound, sometimes invisible if the
      // user already dismissed the first. Distinct id = fresh delivery
      // with sound, so the user actually perceives the validation step.
      // Also cancel a still-PENDING deferred détectée (DATE trigger from a
      // pre-window Enter) — dismiss only clears the tray, not the schedule,
      // and a "valide ta présence" firing at T-15 after confirmation lies.
      await Notifications.cancelScheduledNotificationAsync(slotId).catch(() => {});
      await Notifications.dismissNotificationAsync(slotId).catch(() => {});
      Notifications.scheduleNotificationAsync({
        identifier: `${slotId}-confirmed`,
        content: {
          title: 'Présence confirmée',
          body: 'Ta présence à cette activité est confirmée.',
          data: { activity_id: activityId, type: 'presence_confirmed' },
          sound: true,
        },
        trigger: null,
      }).catch(() => {});
      return;
    }

    if (isTerminalPresenceRejection(error.message)) {
      trace('presence.geofence', 'task: RPC rejected (terminal), clearing détectée', {
        reason: error.message,
      });
      // The détectée notif we just posted says "valide ta présence" — for a
      // terminal rejection (left the activity, cancelled, too far per the
      // real fix) that's a lie sitting in the tray. Clear both the tray
      // and any pending deferred schedule.
      await Notifications.cancelScheduledNotificationAsync(slotId).catch(() => {});
      await Notifications.dismissNotificationAsync(slotId).catch(() => {});
      return;
    }

    trace('presence.geofence', 'task: RPC failed (non-terminal), enqueue for replay', {
      reason: error.message,
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: fix.coords.longitude,
      lat: fix.coords.latitude,
      captured_at: capturedAt,
    });
  } catch (err) {
    trace('presence.geofence', 'task: RPC threw, enqueue for replay', {
      message: err instanceof Error ? err.message : String(err),
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: fix.coords.longitude,
      lat: fix.coords.latitude,
      captured_at: capturedAt,
    });
  }
});
