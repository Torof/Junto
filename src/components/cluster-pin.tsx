import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { fontSizes, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface ClusterPinProps {
  count: number;
}

export function ClusterPin({ count }: ClusterPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <View style={styles.cluster}>
      <Text style={styles.count}>{count}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  cluster: {
    width: 48,
    height: 48,
    borderRadius: radius.full,
    backgroundColor: colors.background,
    borderWidth: 2,
    borderColor: colors.pinBorder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  count: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
