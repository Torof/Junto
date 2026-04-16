import * as Sentry from '@sentry/react-native';
import * as Updates from 'expo-updates';
import Constants from 'expo-constants';

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
];

function scrub(obj: unknown, depth = 0): unknown {
  if (depth > 4 || obj == null) return obj;
  if (Array.isArray(obj)) return obj.map((v) => scrub(v, depth + 1));
  if (typeof obj === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj)) {
      if (SENSITIVE_KEYS.some((s) => k.toLowerCase().includes(s))) {
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

export function initSentry() {
  if (__DEV__) return;

  const dsn = process.env.EXPO_PUBLIC_SENTRY_DSN;
  if (!dsn) return;

  const channel = Updates.channel || 'unknown';

  // Temporary: auto-consent for preview builds during pre-launch dogfooding.
  // Production requires explicit user consent (ToS + settings toggle).
  const autoConsent = channel === 'preview';
  if (!autoConsent) return;

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
}

export function setSentryUser(userId: string | null) {
  if (__DEV__) return;
  Sentry.setUser(userId ? { id: userId } : null);
}

export const wrap = Sentry.wrap;
