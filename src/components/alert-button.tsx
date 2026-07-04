import { useMemo } from 'react';
import { Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { BellPlus } from 'lucide-react-native';
import { spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

// Direct map entry into alert creation. Alerts were buried in the filter
// sheet's Alertes tab (a discoverability hole that also broke the old
// tutorial); this surfaces them in the bottom-right FAB cluster.
export function AlertButton() {
  const router = useRouter();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Pressable
      style={styles.button}
      onPress={() => router.push('/(auth)/create-alert')}
      hitSlop={8}
      accessibilityLabel={t('alerts.title', { defaultValue: 'Alertes' })}
    >
      <BellPlus size={22} color={colors.cta} strokeWidth={2.3} />
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Bottom-right cluster: create FAB (bottom 28), this alert button above it
  // (+48+14), the contextual recenter on top (+another 48+14) so its
  // appear/disappear never leaves a hole mid-stack. Secondary surface style
  // like recenter; the cta-orange bell gives it presence without competing
  // with the primary FAB.
  button: {
    position: 'absolute',
    bottom: 28 + 48 + 14,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: 14,
    width: 48,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
});
