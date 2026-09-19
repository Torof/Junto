import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, glow, shadows } from '@/constants/theme';
import { PressableScale } from '@/components/pressable-scale';
import type { AppColors } from '@/constants/colors';
import { useCreateStore } from '@/store/create-store';

// All four visibilities open to everyone (Scott 2026-07-10): all tiers
// free at launch, private-link premium gate removed (migration 00316).
const VISIBILITY_OPTIONS = [
  { key: 'public' },
  { key: 'approval' },
  { key: 'private_link' },
  { key: 'private_link_approval' },
] as const;

export default function CreateStep3() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { form, updateForm } = useCreateStore();

  return (
    <View style={[styles.container, { paddingTop: insets.top + spacing.md }]}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 3, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step3Title')}</Text>

      <View style={styles.options}>
        {VISIBILITY_OPTIONS.map((option) => (
          <PressableScale
            key={option.key}
            style={[
              styles.option,
              form.visibility === option.key && styles.optionActive,
            ]}
            onPress={() => updateForm({ visibility: option.key })}
          >
            <View style={styles.optionHeader}>
              <Text style={[styles.optionTitle, form.visibility === option.key && styles.optionTitleActive]}>
                {t(`create.visibility.${option.key}`)}
              </Text>
            </View>
            <Text style={styles.optionDesc}>
              {t(`create.visibility.${option.key}Desc`)}
            </Text>
          </PressableScale>
        ))}
      </View>

      {/* Presence verification toggle */}
      <PressableScale
        style={[styles.toggleRow]}
        onPress={() => updateForm({ requires_presence: !(form.requires_presence ?? true) })}
      >
        <View style={{ flex: 1, marginRight: spacing.md }}>
          <Text style={styles.toggleTitle}>{t('create.presenceTitle')}</Text>
          <Text style={styles.toggleDesc}>{t('create.presenceDesc')}</Text>
        </View>
        <View style={[styles.toggleSwitch, (form.requires_presence ?? true) && styles.toggleSwitchOn]}>
          <View style={[styles.toggleKnob, (form.requires_presence ?? true) && styles.toggleKnobOn]} />
        </View>
      </PressableScale>

      <PressableScale
        style={[styles.nextButton, glow(colors.cta)]}
        onPress={() => router.push('/(auth)/create/step4')}
      >
        <Text style={styles.nextText}>{t('create.next')}</Text>
      </PressableScale>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background, padding: spacing.md },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '800', letterSpacing: -0.3, marginBottom: spacing.lg },
  options: { gap: spacing.sm },
  option: {
    backgroundColor: colors.surface,
    borderRadius: radius.card,
    padding: spacing.md,
    borderWidth: 1.5, borderColor: 'transparent',
    ...shadows.card,
  },
  optionActive: { borderColor: colors.cta, backgroundColor: colors.cta + '14' },
  optionHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xs },
  optionTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  optionTitleActive: { color: colors.cta },
  optionDesc: { color: colors.textSecondary, fontSize: fontSizes.sm },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 4, alignItems: 'center', marginTop: spacing.xl },
  nextText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  toggleRow: {
    flexDirection: 'row', alignItems: 'center', marginTop: spacing.xl,
    backgroundColor: colors.surface,
    borderRadius: radius.card,
    padding: spacing.md,
    ...shadows.card,
  },
  toggleTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', marginBottom: 2 },
  toggleDesc: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16 },
  toggleSwitch: {
    width: 44, height: 26, borderRadius: radius.full,
    backgroundColor: colors.borderMuted, padding: 3, justifyContent: 'center',
  },
  toggleSwitchOn: { backgroundColor: colors.cta },
  toggleKnob: {
    width: 20, height: 20, borderRadius: radius.full, backgroundColor: colors.textSecondary,
  },
  toggleKnobOn: { backgroundColor: colors.onCta, alignSelf: 'flex-end' },
});
