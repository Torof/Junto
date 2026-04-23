import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import type { LucideIcon } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

export interface MetaChip {
  id: string;
  icon: LucideIcon;
  accent: string;
  label: string;
  value: string;
  span?: 'full';
}

interface Props {
  chips: MetaChip[];
}

export function MetaChipsGrid({ chips }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.grid}>
      {chips.map((chip) => {
        const Icon = chip.icon;
        return (
          <View key={chip.id} style={[styles.chip, chip.span === 'full' && styles.chipFull]}>
            <View style={[styles.iconBox, { backgroundColor: chip.accent + '26' }]}>
              <Icon size={16} color={chip.accent} strokeWidth={2.4} />
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.label}>{chip.label}</Text>
              <Text style={styles.value} numberOfLines={1}>{chip.value}</Text>
            </View>
          </View>
        );
      })}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  grid: {
    flexDirection: 'row', flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  chip: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm,
    flexGrow: 1, flexBasis: '47%', minWidth: 140,
  },
  chipFull: { flexBasis: '100%' },
  iconBox: {
    width: 32, height: 32, borderRadius: 8,
    alignItems: 'center', justifyContent: 'center',
  },
  label: {
    color: colors.textMuted, fontSize: 10, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 1,
  },
  value: {
    color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600',
    marginTop: 1,
  },
});
