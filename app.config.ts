import { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'Junto',
  slug: 'junto',
  version: '0.1.1',
  orientation: 'portrait',
  icon: './assets/Junto_logo.png',
  userInterfaceStyle: 'dark',
  scheme: 'junto',
  newArchEnabled: true,
  splash: {
    image: './assets/Junto_logo.png',
    resizeMode: 'contain',
    backgroundColor: '#0D1B2A',
  },
  android: {
    package: 'com.junto.app',
    versionCode: 3,
    googleServicesFile: process.env.GOOGLE_SERVICES_JSON ?? './google-services.json',
    adaptiveIcon: {
      foregroundImage: './assets/Junto_logo.png',
      backgroundColor: '#0D1B2A',
    },
    edgeToEdgeEnabled: true,
    intentFilters: [
      {
        action: 'VIEW',
        autoVerify: true,
        data: [
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'junto-nine.vercel.app', pathPrefix: '/activity' },
          { scheme: 'https', host: process.env.JUNTO_WEB_HOST ?? 'junto-nine.vercel.app', pathPrefix: '/invite' },
        ],
        category: ['BROWSABLE', 'DEFAULT'],
      },
    ],
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: 'com.junto.app',
    associatedDomains: [`applinks:${process.env.JUNTO_WEB_HOST ?? 'junto-nine.vercel.app'}`],
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
        icon: './assets/Junto_logo.png',
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
