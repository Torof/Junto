import { useMemo } from 'react';
import { View, ScrollView, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { MapPin, CalendarCheck, ClipboardList, MessageCircle } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { PressableScale } from '@/components/pressable-scale';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius, glow } from '@/constants/theme';

// What the pro space brings, shown before the « Devenir pro » form to someone
// who has never applied (mockup validated 2026-11-04). Same wording as the
// site's /pros page, so the pitch is the same everywhere.
export function ProIntro({ onStart }: { onStart: () => void }) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();

  const features = [
    { Icon: MapPin, title: t('proIntro.mapTitle'), body: t('proIntro.mapBody') },
    { Icon: CalendarCheck, title: t('proIntro.agendaTitle'), body: t('proIntro.agendaBody') },
    { Icon: ClipboardList, title: t('proIntro.formsTitle'), body: t('proIntro.formsBody') },
    { Icon: MessageCircle, title: t('proIntro.chatTitle'), body: t('proIntro.chatBody') },
  ];
  const steps = [
    [t('proIntro.step1Strong'), t('proIntro.step1')],
    [t('proIntro.step2Strong'), t('proIntro.step2')],
    [t('proIntro.step3Strong'), t('proIntro.step3')],
  ];

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.content}>
        <AppText style={styles.eyebrow}>{t('proIntro.eyebrow')}</AppText>
        <AppText style={styles.title}>{t('proIntro.title')}</AppText>
        <AppText style={styles.subtitle}>{t('proIntro.subtitle')}</AppText>

        <View style={styles.features}>
          {features.map(({ Icon, title, body }) => (
            <View key={title} style={styles.feature}>
              <View style={styles.featureIcon}>
                <Icon size={20} color={colors.cta} strokeWidth={2.2} />
              </View>
              <View style={styles.featureText}>
                <AppText style={styles.featureTitle}>{title}</AppText>
                <AppText style={styles.featureBody}>{body}</AppText>
              </View>
            </View>
          ))}
        </View>

        <View style={styles.how}>
          <AppText style={styles.howTitle}>{t('proIntro.howTitle')}</AppText>
          {steps.map(([strong, rest], i) => (
            <View key={strong} style={styles.step}>
              <View style={styles.stepNum}>
                <AppText style={styles.stepNumText}>{i + 1}</AppText>
              </View>
              <AppText style={styles.stepText}>
                <AppText style={styles.stepStrong}>{strong}</AppText>
                {rest}
              </AppText>
            </View>
          ))}
        </View>
      </ScrollView>

      <View style={[styles.ctaBar, { paddingBottom: Math.max(insets.bottom, spacing.sm) + spacing.sm }]}>
        <PressableScale style={[styles.cta, glow(colors.brand)]} onPress={onStart} accessibilityRole="button">
          <AppText style={styles.ctaText}>{t('proIntro.cta')}</AppText>
        </PressableScale>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.xl },
  eyebrow: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700', letterSpacing: 0.6, textTransform: 'uppercase' },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontFamily: fonts.title, lineHeight: 30, marginTop: spacing.xs, marginBottom: spacing.sm },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, marginBottom: spacing.lg },
  features: { gap: spacing.md, marginBottom: spacing.lg },
  feature: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm + 4 },
  featureIcon: { width: 40, height: 40, borderRadius: radius.full, backgroundColor: colors.cta + '1F', alignItems: 'center', justifyContent: 'center' },
  featureText: { flex: 1 },
  featureTitle: { color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '700' },
  featureBody: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, lineHeight: 18, marginTop: 1 },
  how: { backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4, padding: spacing.md - 2, gap: spacing.sm + 2 },
  howTitle: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  step: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm + 2 },
  stepNum: { width: 22, height: 22, borderRadius: radius.full, backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center' },
  stepNumText: { color: colors.onCta, fontSize: fontSizes.xs, fontWeight: '800' },
  stepText: { flex: 1, color: colors.textSecondary, fontSize: fontSizes.sm - 1, lineHeight: 18 },
  stepStrong: { color: colors.textPrimary, fontWeight: '600' },
  ctaBar: {
    paddingHorizontal: spacing.md, paddingTop: spacing.sm,
    backgroundColor: colors.background, borderTopWidth: 1, borderTopColor: colors.line,
  },
  cta: { backgroundColor: colors.brand, borderRadius: radius.full, paddingVertical: spacing.sm + 6, alignItems: 'center' },
  ctaText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
});
