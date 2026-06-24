import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter, type Href } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { CalendarX2 } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  /** Where the CTA lands — the map for signed-in users, the visitor home otherwise. */
  fallbackHref: Href;
}

/**
 * Shown when an activity can't be loaded — finished, deleted, or no longer
 * accessible (e.g. a notification deep-link to an outing that has since ended).
 * Replaces the perpetual skeleton that otherwise read as a blank page.
 */
export function ActivityUnavailable({ fallbackHref }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const router = useRouter();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const goHome = () => {
    if (router.canGoBack()) router.back();
    else router.replace(fallbackHref);
  };

  return (
    <View style={styles.container}>
      <View style={styles.iconWrap}>
        <CalendarX2 size={40} color={colors.textSecondary} strokeWidth={1.8} />
      </View>
      <Text style={styles.title}>{t('activity.notFound')}</Text>
      <Text style={styles.body}>{t('activity.notFoundBody')}</Text>
      <Pressable style={styles.cta} onPress={goHome}>
        <Text style={styles.ctaText}>{t('activity.notFoundCta')}</Text>
      </Pressable>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.xl,
    gap: spacing.sm,
  },
  iconWrap: {
    width: 88, height: 88, borderRadius: 44,
    backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.borderMuted,
    alignItems: 'center', justifyContent: 'center',
    marginBottom: spacing.sm,
  },
  title: {
    color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '700',
    textAlign: 'center',
  },
  body: {
    color: colors.textSecondary, fontSize: fontSizes.sm,
    textAlign: 'center', lineHeight: 20,
  },
  cta: {
    marginTop: spacing.lg,
    backgroundColor: colors.cta, borderRadius: radius.sm,
    paddingHorizontal: spacing.xl, paddingVertical: spacing.sm + 2,
  },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});
