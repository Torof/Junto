import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useCreateStore } from '@/store/create-store';

const VISIBILITY_OPTIONS = [
  { key: 'public', premium: false },
  { key: 'approval', premium: false },
  { key: 'private_link', premium: true },
  { key: 'private_link_approval', premium: true },
] as const;

export default function CreateStep3() {
  const { t } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();

  return (
    <View style={styles.container}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 3, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step3Title')}</Text>

      <View style={styles.options}>
        {VISIBILITY_OPTIONS.map((option) => (
          <Pressable
            key={option.key}
            style={[
              styles.option,
              form.visibility === option.key && styles.optionActive,
              option.premium && styles.optionDisabled,
            ]}
            onPress={() => !option.premium && updateForm({ visibility: option.key })}
            disabled={option.premium}
          >
            <View style={styles.optionHeader}>
              <Text style={[styles.optionTitle, form.visibility === option.key && styles.optionTitleActive]}>
                {t(`create.visibility.${option.key}`)}
              </Text>
              {option.premium && (
                <Text style={styles.premiumBadge}>Premium</Text>
              )}
            </View>
            <Text style={styles.optionDesc}>
              {t(`create.visibility.${option.key}Desc`)}
            </Text>
          </Pressable>
        ))}
      </View>

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
  optionDesc: { color: colors.textSecondary, fontSize: fontSizes.sm },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl },
  nextText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
