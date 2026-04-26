import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface ClusterPinProps {
  count: number;
}

const MIN_SIZE = 36;
const MAX_SIZE = 60;

function clusterSize(count: number): number {
  if (count < 2) return MIN_SIZE;
  return Math.max(MIN_SIZE, Math.min(MAX_SIZE, 36 + Math.log10(count) * 12));
}

function formatClusterCount(n: number): string {
  if (n < 1000) return String(n);
  if (n < 10000) {
    const v = (n / 1000).toFixed(1);
    return `${v.endsWith('.0') ? v.slice(0, -2) : v}k`;
  }
  return `${Math.floor(n / 1000)}k`;
}

export function ClusterPin({ count }: ClusterPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const size = clusterSize(count);
  const label = formatClusterCount(count);
  const fontSize = size <= 44 ? 13 : size <= 52 ? 15 : 17;

  return (
    <View style={[styles.cluster, { width: size, height: size, borderRadius: size / 2 }]}>
      <Text style={[styles.count, { fontSize }]}>{label}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  cluster: {
    backgroundColor: colors.background,
    borderWidth: 2,
    borderColor: colors.pinBorder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  count: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
});
