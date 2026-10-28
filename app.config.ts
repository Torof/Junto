import { ExpoConfig, ConfigContext } from 'expo/config';

// Dev variant: `APP_VARIANT=preview` (set on the eas.json preview profile) gives
// a distinct package + name + scheme so the dev app installs ALONGSIDE the Play
// tester build (no signature/package conflict). Same slug/projectId → same EAS
// project + OTA channels. Auth is email/password, so the different package is safe.
const IS_PREVIEW = process.env.APP_VARIANT === 'preview';
// Web hosts the app opens links for: the primary one (askandgo.io since
// 2026-10-28) first, then getjunto.app for links shared before the rename.
const WEB_HOST = process.env.JUNTO_WEB_HOST ?? 'askandgo.io';
const WEB_HOSTS = [...new Set([WEB_HOST, 'getjunto.app'])];

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: IS_PREVIEW ? 'Askandgo (dev)' : 'Askandgo',
  slug: 'junto',
  version: '0.1.4',
  orientation: 'portrait',
  icon: './assets/askandgo_icon_square.png',
  // 'automatic' + expo-system-ui (2026-10-26): the activity follows the night
  // mode the ThemeProvider sets from the in-app theme, so system dialogs
  // match the app instead of the phone (takes effect with the next build).
  userInterfaceStyle: 'automatic',
  scheme: IS_PREVIEW ? 'juntodev' : 'junto',
  newArchEnabled: true,
  splash: {
    image: './assets/askandgo_icon_square.png',
    resizeMode: 'contain',
    backgroundColor: '#3F7A56',
  },
  android: {
    package: IS_PREVIEW ? 'app.getjunto.preview' : 'app.getjunto',
    // google-services.json declares both app.getjunto and app.getjunto.preview
    // (Firebase project junto-5e1e3, preview app added 2026-10-22) so the dev
    // variant gets FCM push too — its FCM V1 key is set in EAS credentials.
    googleServicesFile: process.env.GOOGLE_SERVICES_JSON ?? './google-services.json',
    softwareKeyboardLayoutMode: 'resize',
    adaptiveIcon: {
      // Mark-only on transparent + solid green background → uniform green icon,
      // no inner square / dark corners (Scott 2026-07-08).
      foregroundImage: './assets/askandgo_icon_fg.png',
      backgroundColor: '#3F7A56',
    },
    edgeToEdgeEnabled: true,
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        // Every path on every host: askandgo.io (primary) and getjunto.app (kept so
        // links shared before the rename still open the app). /pro covers both
        // /pro/{id} and /pro/offering/{id} (prefix match); /u/{id} is the
        // contact-share QR/link.
        data: WEB_HOSTS.flatMap((host) =>
          ['/activity', '/invite', '/pro', '/u'].map((pathPrefix) => ({ scheme: 'https', host, pathPrefix })),
        ),
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
  // Native permission texts per language (iOS shows them in its dialogs;
  // Android's dialogs are fixed by the system — the in-app card explains).
  locales: {
    fr: './locales/ios/fr.json',
    en: './locales/ios/en.json',
    it: './locales/ios/it.json',
    es: './locales/ios/es.json',
    de: './locales/ios/de.json',
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: IS_PREVIEW ? 'app.getjunto.preview' : 'app.getjunto',
    associatedDomains: WEB_HOSTS.map((host) => `applinks:${host}`),
    infoPlist: {
      // Required strings for "Always" location permission so background
      // geofencing can fire when the app is closed.
      // English base; locales/ios/<lang>.json translate them (and the camera
      // one) into every app language (Scott 2026-10-24).
      NSLocationWhenInUseUsageDescription: 'Your location centres the map on you, finds the outings and discussions around, and confirms your presence on the day of an outing. It is never shown to others.',
      NSLocationAlwaysAndWhenInUseUsageDescription: 'In the background, askandgo only looks at your location in the 24 hours before an outing you joined, to confirm your arrival without you opening the app.',
      UIBackgroundModes: ['location', 'fetch'],
    },
  },
  runtimeVersion: {
    policy: 'appVersion',
  },
  updates: {
    url: 'https://u.expo.dev/dea60861-73c9-476f-a824-59bf9cd5b340',
  },
  plugins: [
    'expo-router',
    'expo-web-browser',
    'expo-localization',
    'expo-secure-store',
    '@react-native-community/datetimepicker',
    // Download token comes from the RNMAPBOX_MAPS_DOWNLOAD_TOKEN env var
    // (EAS secret + local .env) — the plugin prop form is deprecated.
    '@rnmapbox/maps',
    [
      'expo-notifications',
      {
        // Android draws the notification icon as a white silhouette: mark only.
        icon: './assets/askandgo_notification.png',
        color: '#3F7A56',
      },
    ],
    [
      'expo-camera',
      {
        cameraPermission: 'The camera is only used to scan QR codes (presence, contacts). No photo is taken.',
      },
    ],
    [
      'expo-location',
      {
        locationAlwaysAndWhenInUsePermission: 'In the background, askandgo only looks at your location in the 24 hours before an outing you joined, to confirm your arrival without you opening the app.',
        isAndroidBackgroundLocationEnabled: true,
        isIosBackgroundLocationEnabled: true,
      },
    ],
    'expo-task-manager',
  ],
  extra: {
    router: {},
    eas: {
      projectId: 'dea60861-73c9-476f-a824-59bf9cd5b340',
    },
  },
  owner: 'torof05',
});
