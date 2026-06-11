import * as Sentry from '@sentry/react-native';
import * as Updates from 'expo-updates';
import Constants from 'expo-constants';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Production consent (RGPD Art. 7) — diagnostics are OFF by default and
// only initialize after the user opts in via the settings toggle.
// Preview builds keep auto-consent for dogfooding (DECISIONS 2026-05).
const CONSENT_KEY = 'junto.sentry_consent';

const SENSITIVE_KEYS = [
  'presence_token',
  'invite_token',
  'access_token',
  'refresh_token',
  'jwt',
  'authorization',
  'apikey',
  'password',
  'email',
  'phone',
  'lat',
  'lng',
  'latitude',
  'longitude',
  'body',
  'content',
  'message',
  'description',
  'bio',
  'details',
  'hint',
  // PII — display_name is the only real name we carry. Add common
  // aliases too in case future code uses them.
  'display_name',
  'name',
  'full_name',
];

function scrub(obj: unknown, depth = 0): unknown {
  if (depth > 4 || obj == null) return obj;
  if (Array.isArray(obj)) return obj.map((v) => scrub(v, depth + 1));
  if (typeof obj === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj)) {
      // Exact match against the sensitive list. Substring matching
      // over-redacted Sentry's own context fields (e.g. "simulator"
      // contained "lat" → got redacted → Sentry discarded it as the
      // wrong type). Snake_case compound names with sensitive
      // suffixes (`user_email`, `auth_token`, etc.) should be added
      // to the list explicitly when they appear.
      if (SENSITIVE_KEYS.includes(k.toLowerCase())) {
        out[k] = '[REDACTED]';
      } else {
        out[k] = scrub(v, depth + 1);
      }
    }
    return out;
  }
  return obj;
}

let eventCount = 0;
const MAX_EVENTS_PER_SESSION = 50;

let initialized = false;

export function initSentry() {
  if (__DEV__) return;

  const channel = Updates.channel || 'unknown';

  if (channel === 'preview') {
    // Dogfooding builds: auto-consent, init synchronously at boot.
    initializeSentry();
    return;
  }

  // Production: init only if the user previously opted in. Fire-and-
  // forget — losing the first few ms of crash coverage is acceptable;
  // collecting before consent is not.
  AsyncStorage.getItem(CONSENT_KEY)
    .then((v) => {
      if (v === 'true') initializeSentry();
    })
    .catch(() => {});
}

export async function getSentryConsent(): Promise<boolean> {
  try {
    return (await AsyncStorage.getItem(CONSENT_KEY)) === 'true';
  } catch {
    return false;
  }
}

// Settings toggle entry point. Granting initializes Sentry live;
// revoking stops the client and clears the stored consent (full stop
// takes effect on next app start for anything already buffered).
export async function setSentryConsent(granted: boolean): Promise<void> {
  try {
    await AsyncStorage.setItem(CONSENT_KEY, granted ? 'true' : 'false');
  } catch {}
  if (__DEV__) return;
  if (granted) {
    initializeSentry();
  } else if (initialized) {
    await Sentry.close().catch(() => {});
    initialized = false;
  }
}

function initializeSentry() {
  if (initialized) return;

  const dsn = process.env.EXPO_PUBLIC_SENTRY_DSN;
  if (!dsn) return;

  const channel = Updates.channel || 'unknown';
  const version = Constants.expoConfig?.version ?? '0.0.0';
  const buildNumber =
    Constants.expoConfig?.android?.versionCode?.toString() ??
    Constants.expoConfig?.ios?.buildNumber ??
    '0';

  Sentry.init({
    dsn,
    environment: channel,
    release: `com.junto.app@${version}+${buildNumber}`,
    sendDefaultPii: false,
    tracesSampleRate: 0,
    attachScreenshot: false,
    attachViewHierarchy: false,
    enableAutoSessionTracking: true,
    maxBreadcrumbs: 30,
    normalizeDepth: 3,
    integrations: (defaults) =>
      defaults.filter((i) => i.name !== 'Console'),
    beforeBreadcrumb(breadcrumb) {
      if (breadcrumb.category === 'fetch' || breadcrumb.category === 'xhr') {
        if (breadcrumb.data) {
          delete (breadcrumb.data as Record<string, unknown>).request_headers;
          delete (breadcrumb.data as Record<string, unknown>).response_headers;
        }
      }
      return breadcrumb;
    },
    beforeSend(event) {
      if (eventCount++ >= MAX_EVENTS_PER_SESSION) return null;
      if (event.extra) event.extra = scrub(event.extra) as typeof event.extra;
      if (event.contexts) event.contexts = scrub(event.contexts) as typeof event.contexts;
      if (event.request?.data) event.request.data = scrub(event.request.data);
      return event;
    },
  });

  // Sanity ping. If you can see this event in the Sentry dashboard within
  // a minute of app start, wiring is working end-to-end (DSN bundled, JS
  // init ran, native SDK accepted it). If nothing lands, the failure is
  // upstream of this line — check that the APK includes the native module
  // and that Updates.channel actually returns 'preview' on this build.
  Sentry.captureMessage('[sentry.init] initialized', {
    level: 'info',
    extra: { channel, version, buildNumber },
  });

  initialized = true;
}

export function setSentryUser(userId: string | null) {
  if (__DEV__) return;
  Sentry.setUser(userId ? { id: userId } : null);
}

// Lightweight breadcrumb helper for diagnostic trails (presence flow, geofence
// events, RPC outcomes). No-op in dev so we don't ship breadcrumb churn.
export function trace(
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (__DEV__) return;
  // Scrub at the call site, not just in beforeSend. If a breadcrumb
  // is dropped before send (buffer flush, network) the raw payload
  // would otherwise leave the device.
  Sentry.addBreadcrumb({
    category,
    message,
    level: 'info',
    data: data ? (scrub(data) as Record<string, unknown>) : undefined,
  });
}

// Surface a real Sentry event (not just a breadcrumb) so silent failures in
// the background flow are visible in the dashboard. Use sparingly — reserve
// for paths where breadcrumbs alone wouldn't surface the issue (no parent
// event to attach them to, e.g. headless task failures).
export function captureWarning(
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (__DEV__) return;
  Sentry.captureMessage(`[${category}] ${message}`, {
    level: 'warning',
    extra: data ? (scrub(data) as Record<string, unknown>) : undefined,
  });
}

// Diagnostic-level event. Same shape as captureWarning but level='info' so
// it stays out of the warning/error queues. Use for confirming a code path
// reached a checkpoint we'd otherwise have no visibility into (e.g. the
// headless geofence task firing on a closed app — we want to know it
// happened, not flag it as a problem).
export function captureInfo(
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (__DEV__) return;
  Sentry.captureMessage(`[${category}] ${message}`, {
    level: 'info',
    extra: data ? (scrub(data) as Record<string, unknown>) : undefined,
  });
}

export const wrap = Sentry.wrap;
