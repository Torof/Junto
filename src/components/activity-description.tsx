import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, radius, spacing } from '@/constants/theme';
import { useColors, useResolvedTheme } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  description: string | null | undefined;
}

export function ActivityDescription({ description }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const theme = useResolvedTheme();
  const styles = useMemo(() => createStyles(colors, theme), [colors, theme]);

  if (!description) return null;

  return (
    <View style={styles.container}>
      <Text style={styles.title}>{t('activity.description')}</Text>
      <View style={styles.divider} />
      <Text style={styles.body}>{description}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors, theme: 'dark' | 'light') => StyleSheet.create({
  container: {
    backgroundColor: theme === 'dark' ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.6)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    padding: spacing.md,
    marginBottom: spacing.lg,
  },
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
