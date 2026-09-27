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
    },
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
