import { useState, useMemo } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { activityService } from '@/services/activity-service';
import { supabase } from '@/services/supabase';
import { LEVELS } from '@/types/activity-form';
import { getFriendlyError } from '@/utils/friendly-error';

const VISIBILITIES = ['public', 'approval', 'private_link', 'private_link_approval'] as const;

export default function EditActivityScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: activity, isLoading: activityLoading } = useQuery({
    queryKey: ['activity', id],
    queryFn: () => activityService.getById(id ?? ''),
    enabled: !!id,
  });

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

  // Check if fields are locked (participants besides creator exist)
  const hasParticipants = (activity?.participant_count ?? 1) > 1;

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [level, setLevel] = useState('');
  const [maxParticipants, setMaxParticipants] = useState<number | null>(4);
  const [startsAt, setStartsAt] = useState<Date | null>(null);
  const [durationHours, setDurationHours] = useState(2);
  const [durationMinutes, setDurationMinutes] = useState(0);
  const [visibility, setVisibility] = useState('public');
  const [initialized, setInitialized] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);

  // Initialize form with activity data once loaded
  if (activity && !initialized) {
    setTitle(activity.title);
    setDescription(activity.description ?? '');
    setLevel(activity.level);
    setMaxParticipants(activity.max_participants);
    setStartsAt(new Date(activity.starts_at));
    setVisibility(activity.visibility);
    // Parse duration string (e.g. "04:00:00" or "2 hours")
    const dMatch = activity.duration.match(/(\d+):(\d+)/);
    if (dMatch?.[1] && dMatch[2]) {
      setDurationHours(parseInt(dMatch[1], 10));
      setDurationMinutes(parseInt(dMatch[2], 10));
    }
    setInitialized(true);
  }

  const handleSave = async () => {
    if (!activity || !id) return;
    setIsSaving(true);
    try {
      const durationStr = `${durationHours} hours ${durationMinutes} minutes`;
      await activityService.update(id, {
        title,
        description,
        level,
        max_participants: maxParticipants,
        starts_at: startsAt?.toISOString(),
        duration: durationStr,
        visibility,
      });
      await queryClient.invalidateQueries({ queryKey: ['activity', id] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      Burnt.toast({ title: t('toast.activityUpdated'), preset: 'done' });
      router.back();
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'updateActivity'));
    } finally {
      setIsSaving(false);
    }
  };

  if (activityLoading || !activity) {
    return (
      <View style={styles.center}>
        <Text style={styles.loadingText}>...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.pageTitle}>{t('edit.title')}</Text>

      <Text style={styles.label}>{t('create.title')}</Text>
      <TextInput
        style={styles.input}
        value={title}
        onChangeText={setTitle}
        maxLength={100}
      />

      <Text style={styles.label}>{t('create.description')}</Text>
      <TextInput
        style={[styles.input, styles.textArea]}
        value={description}
        onChangeText={setDescription}
        multiline
        maxLength={2000}
      />

      <Text style={styles.label}>{t('create.level')}</Text>
      <View style={[styles.chipRow, hasParticipants && styles.locked]}>
        {LEVELS.map((l) => (
          <Pressable
            key={l}
            style={[styles.chip, level === l && styles.chipActive]}
            onPress={() => !hasParticipants && setLevel(l)}
            disabled={hasParticipants}
          >
            <Text style={[styles.chipText, level === l && styles.chipTextActive]}>{l}</Text>
          </Pressable>
        ))}
      </View>
      {hasParticipants && <Text style={styles.lockedHint}>{t('edit.lockedHint')}</Text>}

      <Text style={styles.label}>{t('create.maxParticipants')}</Text>
      <Pressable
        style={[styles.openToggle, hasParticipants && styles.locked]}
        onPress={() => !hasParticipants && setMaxParticipants(maxParticipants === null ? 4 : null)}
        disabled={hasParticipants}
      >
        <View style={[styles.openCheckbox, maxParticipants === null && styles.openCheckboxOn]}>
          {maxParticipants === null && <Text style={styles.openCheckboxMark}>✓</Text>}
        </View>
        <Text style={styles.openLabel}>{t('create.openActivity')}</Text>
      </Pressable>
      {maxParticipants !== null && (
        <View style={[styles.counterRow, hasParticipants && styles.locked]}>
          <Pressable
            style={styles.counterButton}
            onPress={() => !hasParticipants && setMaxParticipants(Math.max(2, (maxParticipants ?? 4) - 1))}
            disabled={hasParticipants}
          >
            <Text style={styles.counterText}>-</Text>
          </Pressable>
          <Text style={styles.counterValue}>{maxParticipants}</Text>
          <Pressable
            style={styles.counterButton}
            onPress={() => !hasParticipants && setMaxParticipants(Math.min(50, (maxParticipants ?? 4) + 1))}
            disabled={hasParticipants}
          >
            <Text style={styles.counterText}>+</Text>
          </Pressable>
        </View>
      )}

      <Text style={styles.label}>{t('create.dateTime')}</Text>
      <Pressable
        style={[styles.dateButton, hasParticipants && styles.locked]}
        onPress={() => !hasParticipants && setShowDatePicker(true)}
        disabled={hasParticipants}
      >
        <Text style={styles.dateValue}>
          {startsAt ? dayjs(startsAt).format('ddd D MMM · H[h]mm') : '-'}
        </Text>
      </Pressable>

      {showDatePicker && (
        <DateTimePicker
          value={startsAt ?? new Date()}
          mode="date"
          minimumDate={new Date()}
          onChange={(_e, date) => {
            setShowDatePicker(false);
            if (date) {
              const current = startsAt ?? new Date();
              date.setHours(current.getHours(), current.getMinutes());
              setStartsAt(date);
              setShowTimePicker(true);
            }
          }}
        />
      )}

      {showTimePicker && (
        <DateTimePicker
          value={startsAt ?? new Date()}
          mode="time"
          onChange={(_e, date) => {
            setShowTimePicker(false);
            if (date) setStartsAt(date);
          }}
        />
      )}

      <Text style={styles.label}>{t('create.duration')}</Text>
      <View style={styles.durationRow}>
        <Pressable style={styles.counterButton} onPress={() => setDurationHours(Math.max(0, durationHours - 1))}>
          <Text style={styles.counterText}>-</Text>
        </Pressable>
        <Text style={styles.counterValue}>{durationHours}h{durationMinutes > 0 ? durationMinutes : ''}</Text>
        <Pressable style={styles.counterButton} onPress={() => setDurationHours(Math.min(24, durationHours + 1))}>
          <Text style={styles.counterText}>+</Text>
        </Pressable>
      </View>

      <Text style={styles.label}>{t('create.step3Title')}</Text>
      <View style={[styles.chipRow, hasParticipants && styles.locked]}>
        {VISIBILITIES.map((v) => (
          <Pressable
            key={v}
            style={[styles.chip, visibility === v && styles.chipActive]}
            onPress={() => !hasParticipants && setVisibility(v)}
            disabled={hasParticipants}
          >
            <Text style={[styles.chipText, visibility === v && styles.chipTextActive]}>
              {t(`create.visibility.${v}`)}
            </Text>
          </Pressable>
        ))}
      </View>

      <Pressable
        style={[styles.saveButton, isSaving && styles.buttonDisabled]}
        onPress={handleSave}
        disabled={isSaving}
      >
        <Text style={styles.saveText}>{isSaving ? '...' : t('edit.save')}</Text>
      </Pressable>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  pageTitle: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
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
  counterRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg, marginTop: spacing.sm },
  openToggle: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xs },
  openCheckbox: { width: 22, height: 22, borderRadius: 6, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center' },
  openCheckboxOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  openCheckboxMark: { color: colors.textPrimary, fontSize: 14, fontWeight: 'bold' },
  openLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  counterButton: { backgroundColor: colors.surface, borderRadius: radius.full, width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  counterText: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  counterValue: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', minWidth: 40, textAlign: 'center' },
  durationRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  dateButton: { backgroundColor: colors.surface, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md },
  dateValue: { color: colors.textPrimary, fontSize: fontSizes.md },
  locked: { opacity: 0.4 },
  lockedHint: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.xs, fontStyle: 'italic' },
  saveButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  saveText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
