import expoConfig from 'eslint-config-expo/flat.js';
import prettierConfig from 'eslint-config-prettier';

export default [
  ...expoConfig,
  prettierConfig,
  {
    rules: {
      'import/no-named-as-default-member': 'off',
      // App française : apostrophes/guillemets typographiques dans le JSX.
      'react/no-unescaped-entities': 'off',
      // Text goes through <AppText>/<AppTextInput> so the user's font family
      // (and its width normalisation) reaches every string.
      'no-restricted-imports': ['error', { paths: [{ name: 'react-native', importNames: ['Text'], message: 'Use AppText from @/components/app-text.' }] }],
    },
  },
  {
    files: ['src/components/app-text.tsx'],
    rules: { 'no-restricted-imports': 'off' },
  },
  {
    ignores: [
      'node_modules/',
      'dist/',
      '.expo/',
      'web-build/',
      'web/',
      'claude_design/',
      '.nyc_output/',
      'supabase/functions/',
    ],
  },
];
