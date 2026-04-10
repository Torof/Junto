import expoConfig from 'eslint-config-expo/flat.js';
import prettierConfig from 'eslint-config-prettier';

export default [
  ...expoConfig,
  prettierConfig,
  {
    rules: {
      'import/no-named-as-default-member': 'off',
    },
  },
  {
    ignores: ['node_modules/', 'dist/', '.expo/', 'web-build/'],
  },
];
