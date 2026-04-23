import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  description: string | null | undefined;
}

export function ActivityDescription({ description }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  if (!description) return null;

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{t('activity.description')}</Text>
      <View style={styles.divider} />
      <Text style={styles.body}>{description}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { marginBottom: spacing.lg },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
    textAlign: 'center',
  },
  divider: {
    alignSelf: 'center',
    width: 48,
    height: 1,
    backgroundColor: colors.line,
    marginTop: spacing.xs,
    marginBottom: spacing.sm,
  },
  body: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    lineHeight: 22,
  },
});
