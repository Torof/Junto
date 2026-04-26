import { useMemo } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/services/supabase';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useCreateStore } from '@/store/create-store';
import { SportDropdown } from '@/components/sport-dropdown';
import { getLevelScale, sportHasDistance, sportHasElevation } from '@/constants/sport-levels';

export default function CreateStep1() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
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

  const selectedSportKey = sports?.find((s) => s.id === form.sport_id)?.key ?? '';
  const levelScale = useMemo(() => getLevelScale(selectedSportKey), [selectedSportKey]);
  const showDistance = sportHasDistance(selectedSportKey);
  const showElevation = sportHasElevation(selectedSportKey);
  const isValid = form.sport_id && form.title.length >= 3 && form.level && (form.max_participants === null || form.max_participants >= 2);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.stepLabel}>{t('create.step', { current: 1, total: 4 })}</Text>
      <Text style={styles.title}>{t('create.step1Title')}</Text>

      <Text style={styles.label}>{t('create.sport')}</Text>
      <SportDropdown
        selected={selectedSportKey}
        onSelect={(key) => {
          const sport = sports?.find((s) => s.key === key);
          if (sport) updateForm({ sport_id: sport.id, level: '', distance_km: null, elevation_gain_m: null });
        }}
        label={t('create.sport')}
      />

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
        {levelScale.map((opt) => (
          <Pressable
            key={opt.label}
            style={[styles.chip, form.level === opt.label && styles.chipActive]}
            onPress={() => updateForm({ level: opt.label })}
          >
            <Text style={[styles.chipText, form.level === opt.label && styles.chipTextActive]}>
              {opt.label}
            </Text>
            {opt.description && (
              <Text style={[styles.chipHint, form.level === opt.label && styles.chipHintActive]}>
                {opt.description}
              </Text>
            )}
          </Pressable>
        ))}
      </View>

      {(showDistance || showElevation) && (
        <View style={styles.metricRow}>
          {showDistance && (
            <View style={styles.metricField}>
              <Text style={styles.label}>{t('create.distance')}</Text>
              <TextInput
                style={styles.input}
                placeholder="25"
                placeholderTextColor={colors.textSecondary}
                value={form.distance_km != null ? String(form.distance_km) : ''}
                onChangeText={(text) => {
                  const cleaned = text.replace(',', '.').replace(/[^0-9.]/g, '');
                  const num = cleaned === '' ? null : Number(cleaned);
                  updateForm({ distance_km: num && !isNaN(num) && num > 0 ? num : null });
                }}
                keyboardType="decimal-pad"
                maxLength={6}
              />
            </View>
          )}
          {showElevation && (
            <View style={styles.metricField}>
              <Text style={styles.label}>{t('create.elevation')}</Text>
              <TextInput
                style={styles.input}
                placeholder="1400"
                placeholderTextColor={colors.textSecondary}
                value={form.elevation_gain_m != null ? String(form.elevation_gain_m) : ''}
                onChangeText={(text) => {
                  const cleaned = text.replace(/[^0-9]/g, '');
                  const num = cleaned === '' ? null : Number(cleaned);
                  updateForm({ elevation_gain_m: num && !isNaN(num) && num > 0 ? num : null });
                }}
                keyboardType="number-pad"
                maxLength={5}
              />
            </View>
          )}
        </View>
      )}

      <Text style={styles.label}>{t('create.maxParticipants')}</Text>
      <Pressable
        style={styles.openToggle}
        onPress={() => updateForm({ max_participants: form.max_participants === null ? 4 : null })}
      >
        <View style={[styles.openCheckbox, form.max_participants === null && styles.openCheckboxOn]}>
          {form.max_participants === null && <Text style={styles.openCheckboxMark}>✓</Text>}
        </View>
        <Text style={styles.openLabel}>{t('create.openActivity')}</Text>
      </Pressable>
      {form.max_participants !== null && (
        <View style={styles.counterRow}>
          <Pressable
            style={styles.counterButton}
            onPress={() => updateForm({ max_participants: Math.max(2, (form.max_participants ?? 4) - 1) })}
          >
            <Text style={styles.counterText}>-</Text>
          </Pressable>
          <Text style={styles.counterValue}>{form.max_participants}</Text>
          <Pressable
            style={styles.counterButton}
            onPress={() => updateForm({ max_participants: Math.min(50, (form.max_participants ?? 4) + 1) })}
          >
            <Text style={styles.counterText}>+</Text>
          </Pressable>
        </View>
      )}

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

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
  label: { color: colors.textPrimary, fontSize: fontSizes.sm, marginBottom: spacing.sm, marginTop: spacing.md },
  input: {
    backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.md, fontSize: fontSizes.md,
  },
  textArea: { minHeight: 80, textAlignVertical: 'top' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  chip: { backgroundColor: colors.surface, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, alignItems: 'center' },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  chipHint: { color: colors.textSecondary, fontSize: fontSizes.xs - 1, marginTop: 2 },
  chipHintActive: { color: colors.textPrimary, opacity: 0.85 },
  metricRow: { flexDirection: 'row', gap: spacing.md },
  metricField: { flex: 1 },
  counterRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg, marginTop: spacing.sm },
  openToggle: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xs },
  openCheckbox: { width: 22, height: 22, borderRadius: 6, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center' },
  openCheckboxOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  openCheckboxMark: { color: colors.textPrimary, fontSize: 14, fontWeight: 'bold' },
  openLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  counterButton: { backgroundColor: colors.surface, borderRadius: radius.full, width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  counterText: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  counterValue: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', minWidth: 40, textAlign: 'center' },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  nextText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
