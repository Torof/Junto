import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useMemo } from 'react';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing } from '@/constants/theme';

// Placeholder — the register / edit form lands in Phase 1.5.
// Existing pros land here when they tap the pencil on their own page.
// New pros will land here from the settings drawer's "Register as pro"
// entry once that's wired.
export default function ProEditScreen() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <View style={styles.center}>
      <Text style={styles.placeholder}>
        {t('pro.editComingSoon', { defaultValue: 'Édition de la page pro — bientôt.' })}
      </Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
    paddingHorizontal: spacing.lg,
  },
  placeholder: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    fontStyle: 'italic',
    textAlign: 'center',
  },
});
