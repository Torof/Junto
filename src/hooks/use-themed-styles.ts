import { useMemo } from 'react';
import { StyleSheet } from 'react-native';
import { useColors } from './use-theme';
import type { AppColors } from '@/constants/colors';

export function useThemedStyles<T extends StyleSheet.NamedStyles<T>>(
  factory: (colors: AppColors) => T,
): T {
  const colors = useColors();
  return useMemo(() => StyleSheet.create(factory(colors)), [colors]);
}
