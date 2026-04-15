import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useCreateStore } from '@/store/create-store';
import { supabase } from '@/services/supabase';

const VISIBILITY_OPTIONS = [
  { key: 'public', requiresPremium: false },
  { key: 'approval', requiresPremium: false },
  { key: 'private_link', requiresPremium: true },
  { key: 'private_link_approval', requiresPremium: true },
] as const;

export default function CreateStep3() {
  const { t } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();

  const { data: user } = useQuery({
    queryKey: ['currentUser-tier'],
    queryFn: async () => {
      const { data } = await supabase
        .from('users')
        .select('tier')
        .single();
      return data as { tier: string } | null;
    },
  });

  const isPremium = user?.tier === 'premium' || user?.tier === 'pro';

  return (
    <View style={styles.container}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 3, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step3Title')}</Text>

      <View style={styles.options}>
        {VISIBILITY_OPTIONS.map((option) => {
          const locked = option.requiresPremium && !isPremium;
          return (
            <Pressable
              key={option.key}
              style={[
                styles.option,
                form.visibility === option.key && styles.optionActive,
                locked && styles.optionDisabled,
              ]}
              onPress={() => !locked && updateForm({ visibility: option.key })}
              disabled={locked}
            >
              <View style={styles.optionHeader}>
                <Text style={[styles.optionTitle, form.visibility === option.key && styles.optionTitleActive]}>
                  {t(`create.visibility.${option.key}`)}
                </Text>
                {option.requiresPremium && !isPremium && (
                  <Text style={styles.premiumBadge}>Premium</Text>
                )}
                {option.requiresPremium && isPremium && (
                  <Text style={styles.unlockedBadge}>✓</Text>
                )}
              </View>
              <Text style={styles.optionDesc}>
                {t(`create.visibility.${option.key}Desc`)}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {/* Presence verification toggle */}
      <Pressable
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
      </Pressable>

      <Pressable
        style={styles.nextButton}
        onPress={() => router.push('/(auth)/create/step4')}
      >
        <Text style={styles.nextText}>{t('create.next')}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background, padding: spacing.lg },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
  options: { gap: spacing.sm },
  option: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, borderWidth: 2, borderColor: 'transparent' },
  optionActive: { borderColor: colors.cta },
  optionDisabled: { opacity: 0.4 },
  optionHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xs },
  optionTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  optionTitleActive: { color: colors.cta },
  premiumBadge: { color: colors.warning, fontSize: fontSizes.xs, fontWeight: 'bold' },
  unlockedBadge: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold' },
  optionDesc: { color: colors.textSecondary, fontSize: fontSizes.sm },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl },
  nextText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  toggleRow: {
    flexDirection: 'row', alignItems: 'center', marginTop: spacing.xl,
    backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md,
  },
  toggleTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold', marginBottom: 2 },
  toggleDesc: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16 },
  toggleSwitch: {
    width: 44, height: 26, borderRadius: 13,
    backgroundColor: colors.background, padding: 3, justifyContent: 'center',
  },
  toggleSwitchOn: { backgroundColor: colors.cta },
  toggleKnob: {
    width: 20, height: 20, borderRadius: 10, backgroundColor: colors.textSecondary,
  },
  toggleKnobOn: { backgroundColor: '#fff', alignSelf: 'flex-end' },
});
