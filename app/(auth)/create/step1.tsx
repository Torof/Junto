import { useMemo } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet } from 'react-native';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useSports } from '@/hooks/use-sports';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useCreateStore } from '@/store/create-store';
import { SportDropdown } from '@/components/sport-dropdown';
import { getLevelScale, sportHasDistance, sportHasElevation, OPEN_LEVEL, formatLevelRange } from '@/constants/sport-levels';

export default function CreateStep1() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();

  const { data: sports } = useSports();

  const selectedSportKey = sports?.find((s) => s.id === form.sport_id)?.key ?? '';
  const levelScale = useMemo(() => getLevelScale(selectedSportKey), [selectedSportKey]);
  const showDistance = sportHasDistance(selectedSportKey);
  const showElevation = sportHasElevation(selectedSportKey);
  const isValid = form.sport_id && form.title.length >= 3 && form.level && (form.max_participants === null || form.max_participants >= 2);

  // Range picker — tap a level to set the low end, tap a second to span the
  // two. "Tous niveaux" is a one-tap open selection (no high end).
  const lowIdx = levelScale.findIndex((o) => o.label === form.level);
  const highIdx = form.level_max ? levelScale.findIndex((o) => o.label === form.level_max) : lowIdx;
  const rangeLabel = formatLevelRange(form.level, form.level_max);

  const handleLevelTap = (label: string, idx: number) => {
    if (label === OPEN_LEVEL) {
      updateForm({ level: OPEN_LEVEL, level_max: null });
      return;
    }
    // Fresh start: nothing chosen, "Tous niveaux" was selected, or a full
    // range already exists → this tap becomes the new single low end.
    if (lowIdx === -1 || form.level === OPEN_LEVEL || form.level_max) {
      updateForm({ level: label, level_max: null });
      return;
    }
    if (idx === lowIdx) return; // re-tapping the single selection keeps it
    const lowOpt = levelScale[Math.min(idx, lowIdx)];
    const highOpt = levelScale[Math.max(idx, lowIdx)];
    if (lowOpt && highOpt) updateForm({ level: lowOpt.label, level_max: highOpt.label });
  };

  return (
    <KeyboardAwareScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
    >
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
        {levelScale.map((opt, idx) => {
          const active = lowIdx !== -1 && idx >= lowIdx && idx <= highIdx;
          return (
            <Pressable
              key={opt.label}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => handleLevelTap(opt.label, idx)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {opt.label}
              </Text>
              {opt.description && (
                <Text style={[styles.chipHint, active && styles.chipHintActive]}>
                  {opt.description}
                </Text>
              )}
            </Pressable>
          );
        })}
      </View>
      <Text style={styles.rangeHint}>
        {rangeLabel || t('create.levelRangeHint', { defaultValue: 'Touchez un niveau — ou deux pour définir une plage' })}
      </Text>

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
    </KeyboardAwareScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.xs },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
  label: { color: colors.textPrimary, fontSize: fontSizes.sm, marginBottom: spacing.sm, marginTop: spacing.md },
  input: {
    backgroundColor: colors.background, color: colors.textPrimary, borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm + 2, fontSize: fontSizes.md,
  },
  textArea: { minHeight: 80, textAlignVertical: 'top' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2 },
  chip: {
    borderWidth: 1, borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.xs + 2,
    alignItems: 'center',
    backgroundColor: 'transparent',
  },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500' },
  chipTextActive: { color: '#FFFFFF', fontWeight: '700' },
  chipHint: { color: colors.textSecondary, fontSize: fontSizes.xs - 1, marginTop: 2 },
  chipHintActive: { color: '#FFFFFF', opacity: 0.85 },
  rangeHint: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600', marginTop: spacing.sm },
  metricRow: { flexDirection: 'row', gap: spacing.md },
  metricField: { flex: 1 },
  counterRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg, marginTop: spacing.sm },
  openToggle: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xs },
  openCheckbox: {
    width: 22, height: 22, borderRadius: radius.xs,
    borderWidth: 1, borderColor: colors.borderStrong,
    backgroundColor: 'transparent', alignItems: 'center', justifyContent: 'center',
  },
  openCheckboxOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  openCheckboxMark: { color: '#FFFFFF', fontSize: 14, fontWeight: 'bold' },
  openLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  counterButton: {
    borderWidth: 1, borderColor: colors.borderStrong,
    borderRadius: radius.sm,
    width: 36, height: 36,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: 'transparent',
  },
  counterText: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  counterValue: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', minWidth: 40, textAlign: 'center' },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.sm, paddingVertical: spacing.sm + 2, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  nextText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});
