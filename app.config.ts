import { ExpoConfig, ConfigContext } from 'expo/config';

// Dev variant: `APP_VARIANT=preview` (set on the eas.json preview profile) gives
// a distinct package + name + scheme so the dev app installs ALONGSIDE the Play
// tester build (no signature/package conflict). Same slug/projectId → same EAS
// project + OTA channels. Auth is email/password, so the different package is safe.
const IS_PREVIEW = process.env.APP_VARIANT === 'preview';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: IS_PREVIEW ? 'Junto (dev)' : 'Junto',
  slug: 'junto',
  version: '0.1.3',
  orientation: 'portrait',
  icon: './assets/junto_icon_square.png',
  userInterfaceStyle: 'light',
  scheme: IS_PREVIEW ? 'juntodev' : 'junto',
  newArchEnabled: true,
  splash: {
    image: './assets/junto_icon_square.png',
    resizeMode: 'contain',
    backgroundColor: '#3F7A56',
  },
  android: {
    package: IS_PREVIEW ? 'app.getjunto.preview' : 'app.getjunto',
    googleServicesFile: process.env.GOOGLE_SERVICES_JSON ?? './google-services.json',
    softwareKeyboardLayoutMode: 'resize',
    adaptiveIcon: {
      // Mark-only on transparent + solid green background → uniform green icon,
      // no inner square / dark corners (Scott 2026-07-08).
      foregroundImage: './assets/junto_icon_fg.png',
      backgroundColor: '#3F7A56',
    },
    edgeToEdgeEnabled: true,
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'getjunto.app', pathPrefix: '/activity' },
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'getjunto.app', pathPrefix: '/invite' },
          // /pro covers both /pro/{id} and /pro/offering/{id} (prefix match).
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'getjunto.app', pathPrefix: '/pro' },
        ],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: IS_PREVIEW ? 'app.getjunto.preview' : 'app.getjunto',
    associatedDomains: [`applinks:${process.env.JUNTO_WEB_HOST ?? 'getjunto.app'}`],
    infoPlist: {
      // Required strings for "Always" location permission so background
      // geofencing can fire when the app is closed.
      NSLocationWhenInUseUsageDescription: 'Junto uses your location to validate your presence at activities.',
      NSLocationAlwaysAndWhenInUseUsageDescription: 'Junto auto-validates your presence when you arrive at an activity, even when the app is closed.',
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
        icon: './assets/junto_icon_square.png',
        color: '#F4642A',
      },
    ],
    [
      'expo-camera',
      {
        cameraPermission: 'Junto needs camera access to scan presence QR codes.',
      },
    ],
    [
      'expo-location',
      {
        locationAlwaysAndWhenInUsePermission: 'Junto auto-validates your presence when you arrive at an activity, even when the app is closed.',
        isAndroidBackgroundLocationEnabled: true,
        isIosBackgroundLocationEnabled: true,
      },
    ],
    'expo-task-manager',
    [
      '@sentry/react-native/expo',
      {
        organization: 'junto-pn',
        project: 'react-native',
      },
    ],
  ],
  extra: {
    router: {},
    eas: {
      projectId: 'dea60861-73c9-476f-a824-59bf9cd5b340',
    },
  },
  owner: 'torof05',
});
