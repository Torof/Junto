import { View, Text, TextInput, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { useCreateStore } from '@/store/create-store';
import { LEVELS } from '@/types/activity-form';

export default function CreateStep1() {
  const { t } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();

  const { data: sports } = useQuery({
    queryKey: ['sports'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sports')
        .select('id, key, display_order')
        .order('display_order');
      if (error) throw error;
      return data;
    },
  });

  const isValid = form.sport_id && form.title.length >= 3 && form.level && form.max_participants >= 2;

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 1, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step1Title')}</Text>

      <Text style={styles.label}>{t('create.sport')}</Text>
      <View style={styles.chipRow}>
        {(sports ?? []).map((sport) => (
          <Pressable
            key={sport.id}
            style={[styles.chip, form.sport_id === sport.id && styles.chipActive]}
            onPress={() => updateForm({ sport_id: sport.id })}
          >
            <Text style={[styles.chipText, form.sport_id === sport.id && styles.chipTextActive]}>
              {t(`sports.${sport.key}`, sport.key)}
            </Text>
          </Pressable>
        ))}
      </View>

      <Text style={styles.label}>{t('create.title')}</Text>
      <TextInput
        style={styles.input}
        placeholder={t('create.titlePlaceholder')}
        placeholderTextColor={colors.textSecondary}
        value={form.title}
        onChangeText={(text) => updateForm({ title: text })}
        maxLength={100}
      />

      <Text style={styles.label}>{t('create.description')}</Text>
      <TextInput
        style={[styles.input, styles.textArea]}
        placeholder={t('create.descriptionPlaceholder')}
        placeholderTextColor={colors.textSecondary}
        value={form.description}
        onChangeText={(text) => updateForm({ description: text })}
        multiline
        maxLength={2000}
      />

      <Text style={styles.label}>{t('create.level')}</Text>
      <View style={styles.chipRow}>
        {LEVELS.map((level) => (
          <Pressable
            key={level}
            style={[styles.chip, form.level === level && styles.chipActive]}
            onPress={() => updateForm({ level })}
          >
            <Text style={[styles.chipText, form.level === level && styles.chipTextActive]}>
              {level}
            </Text>
          </Pressable>
        ))}
      </View>

      <Text style={styles.label}>{t('create.maxParticipants')}</Text>
      <View style={styles.counterRow}>
        <Pressable
          style={styles.counterButton}
          onPress={() => updateForm({ max_participants: Math.max(2, form.max_participants - 1) })}
        >
          <Text style={styles.counterText}>-</Text>
        </Pressable>
        <Text style={styles.counterValue}>{form.max_participants}</Text>
        <Pressable
          style={styles.counterButton}
          onPress={() => updateForm({ max_participants: Math.min(50, form.max_participants + 1) })}
        >
          <Text style={styles.counterText}>+</Text>
        </Pressable>
      </View>

      <Pressable
        style={[styles.nextButton, !isValid && styles.buttonDisabled]}
        onPress={() => isValid && router.push('/(auth)/create/step2')}
        disabled={!isValid}
      >
        <Text style={styles.nextText}>{t('create.next')}</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
  label: { color: colors.textPrimary, fontSize: fontSizes.sm, marginBottom: spacing.sm, marginTop: spacing.md },
  input: {
    backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.md, fontSize: fontSizes.md,
  },
  textArea: { minHeight: 80, textAlignVertical: 'top' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  chip: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  counterRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  counterButton: { backgroundColor: colors.surface, borderRadius: radius.full, width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  counterText: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  counterValue: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', minWidth: 40, textAlign: 'center' },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  nextText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
