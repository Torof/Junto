import { useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Check } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { spacing, radius, fontSizes } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

// A pro offering's gear as pills (Scott 2026-10-30, after the Play image 6):
// « Fourni » = accent-tinted pills with a check, « À prévoir » = neutral pills.
// Each group is a small uppercase label over wrapping pills.
export function GearPills({ provided, required }: { provided: string[]; required: string[] }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();

  return (
    <View style={styles.wrap}>
      {provided.length > 0 ? (
        <View style={styles.group}>
          <AppText style={styles.label}>{t('proOffering.equipProvidedLabel', { defaultValue: 'Fourni' })}</AppText>
          <View style={styles.pills}>
            {provided.map((g, i) => (
              <View key={`p-${i}`} style={[styles.pill, styles.pillProvided]}>
                <Check size={13} color={colors.cta} strokeWidth={3} />
                <AppText style={[styles.pillText, styles.pillTextProvided]}>{g}</AppText>
              </View>
            ))}
          </View>
        </View>
      ) : null}
      {required.length > 0 ? (
        <View style={styles.group}>
          <AppText style={styles.label}>{t('proOffering.equipRequiredLabel', { defaultValue: 'À prévoir' })}</AppText>
          <View style={styles.pills}>
            {required.map((g, i) => (
              <View key={`r-${i}`} style={styles.pill}>
                <AppText style={styles.pillText}>{g}</AppText>
              </View>
            ))}
          </View>
        </View>
      ) : null}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrap: { gap: spacing.sm + 4 },
  group: { gap: 6 },
  label: { color: colors.textSecondary, fontSize: 11, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  pills: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  pill: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 2, paddingVertical: 5,
  },
  pillProvided: { backgroundColor: colors.cta + '1A' },
  pillText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  pillTextProvided: { color: colors.cta },
});
