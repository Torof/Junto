import { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'Junto',
  slug: 'junto',
  version: '0.1.1',
  orientation: 'portrait',
  icon: './assets/junto_icon_square.png',
  userInterfaceStyle: 'dark',
  scheme: 'junto',
  newArchEnabled: true,
  splash: {
    image: './assets/junto_icon_square.png',
    resizeMode: 'contain',
    backgroundColor: '#0D1B2A',
  },
  android: {
    package: 'app.getjunto',
    versionCode: 4,
    googleServicesFile: process.env.GOOGLE_SERVICES_JSON ?? './google-services.json',
    softwareKeyboardLayoutMode: 'resize',
    adaptiveIcon: {
      foregroundImage: './assets/junto_icon_round.png',
      backgroundColor: '#0D1B2A',
    },
    edgeToEdgeEnabled: true,
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'getjunto.app', pathPrefix: '/activity' },
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'getjunto.app', pathPrefix: '/invite' },
        ],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: 'app.getjunto',
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
    [
      '@rnmapbox/maps',
      {
        RNMapboxMapsDownloadToken: process.env.MAPBOX_DOWNLOAD_TOKEN,
      },
    ],
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
