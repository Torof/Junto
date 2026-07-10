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
import { useSports } from '@/hooks/use-sports';
import { getLevelScale, OPEN_LEVEL, formatLevelRange } from '@/constants/sport-levels';
import { getFriendlyError } from '@/utils/friendly-error';
import { LogoSpinner } from '@/components/logo-spinner';
import { ActivityUnavailable } from '@/components/activity-unavailable';

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

  const { data: sports } = useSports();

  // Check if fields are locked (participants besides creator exist)
  const hasParticipants = (activity?.participant_count ?? 1) > 1;

  // Mirrors create/step3: private-link visibilities are premium-gated. The
  // DB gate (00308) only fires on SWITCHING to a private value, so the
  // activity's stored visibility stays selectable for a lapsed tier.
  const { data: tierData } = useQuery({
    queryKey: ['currentUser-tier'],
    queryFn: async () => {
      const { data } = await supabase
        .from('users')
        .select('tier')
        .single();
      return data as { tier: string } | null;
    },
  });
  const isPremium = tierData?.tier === 'premium' || tierData?.tier === 'pro';

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [level, setLevel] = useState('');
  const [levelMax, setLevelMax] = useState<string | null>(null);
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
    setLevelMax(activity.level_max);
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

  // Level range picker — mirrors create/step1. Locked when participants exist.
  const levelScale = useMemo(() => getLevelScale(activity?.sport_key ?? ''), [activity?.sport_key]);
  const lowIdx = levelScale.findIndex((o) => o.label === level);
  const highIdx = levelMax ? levelScale.findIndex((o) => o.label === levelMax) : lowIdx;
  const rangeLabel = formatLevelRange(level, levelMax);

  const handleLevelTap = (label: string, idx: number) => {
    if (hasParticipants) return;
    if (label === OPEN_LEVEL) { setLevel(OPEN_LEVEL); setLevelMax(null); return; }
    if (lowIdx === -1 || level === OPEN_LEVEL || levelMax) { setLevel(label); setLevelMax(null); return; }
    if (idx === lowIdx) return;
    const lowOpt = levelScale[Math.min(idx, lowIdx)];
    const highOpt = levelScale[Math.max(idx, lowIdx)];
    if (lowOpt && highOpt) { setLevel(lowOpt.label); setLevelMax(highOpt.label); }
  };

  const handleSave = async () => {
    if (!activity || !id) return;
    setIsSaving(true);
    try {
      const durationStr = `${durationHours} hours ${durationMinutes} minutes`;
      await activityService.update(id, {
        title,
        description,
        level,
        level_max: levelMax,
        // 0 = explicit "open activity" sentinel (NULL means "unchanged"
        // server-side, so it can't express open — see migration 00310).
        max_participants: maxParticipants === null ? 0 : maxParticipants,
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

  if (activityLoading) {
    return (
      <View style={styles.center}>
        <LogoSpinner size={48} />
      </View>
    );
  }
  if (!activity) {
    return <ActivityUnavailable fallbackHref="/(auth)/(tabs)/carte" />;
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
        {levelScale.map((opt, idx) => {
          const active = lowIdx !== -1 && idx >= lowIdx && idx <= highIdx;
          return (
            <Pressable
              key={opt.label}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => handleLevelTap(opt.label, idx)}
              disabled={hasParticipants}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>{opt.label}</Text>
            </Pressable>
          );
        })}
      </View>
      {hasParticipants
        ? <Text style={styles.lockedHint}>{t('edit.lockedHint')}</Text>
        : <Text style={styles.rangeHint}>{rangeLabel || t('create.levelRangeHint')}</Text>}

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
          onChange={(_e, time) => {
            setShowTimePicker(false);
            if (time) {
              // Preserve the date portion of startsAt; only overwrite
              // hours/minutes. mode='time' on Android returns a Date
              // with today's date, which would reset any future date
              // the user previously picked.
              const next = new Date(startsAt ?? new Date());
              next.setHours(time.getHours(), time.getMinutes(), 0, 0);
              setStartsAt(next);
            }
          }}
        />
      )}

      <Text style={styles.label}>{t('create.duration')}</Text>
      <View style={styles.durationRow}>
        <Pressable
          style={styles.counterButton}
          onPress={() =>
            // Floor mirrors the DB CHECK (duration >= 15min) and create/step2:
            // hours can only reach 0 when the preserved minutes carry >= 15.
            setDurationHours(Math.max(durationMinutes >= 15 ? 0 : 1, durationHours - 1))
          }
        >
          <Text style={styles.counterText}>-</Text>
        </Pressable>
        <Text style={styles.counterValue}>{durationHours}h{durationMinutes > 0 ? durationMinutes : ''}</Text>
        <Pressable style={styles.counterButton} onPress={() => setDurationHours(Math.min(24, durationHours + 1))}>
          <Text style={styles.counterText}>+</Text>
        </Pressable>
      </View>

      <Text style={styles.label}>{t('create.step3Title')}</Text>
      <View style={[styles.chipRow, hasParticipants && styles.locked]}>
        {VISIBILITIES.map((v) => {
          const premiumLocked =
            (v === 'private_link' || v === 'private_link_approval') &&
            !isPremium &&
            v !== activity.visibility;
          return (
            <Pressable
              key={v}
              style={[styles.chip, visibility === v && styles.chipActive, premiumLocked && styles.chipLocked]}
              onPress={() => {
                if (hasParticipants) return;
                if (premiumLocked) {
                  // Explicit feedback, not a silently dead chip — the badge
                  // alone doesn't say why the tap did nothing.
                  Alert.alert(t('account.tier.premium'), t('errors.code.premium_required'));
                  return;
                }
                setVisibility(v);
              }}
              disabled={hasParticipants}
            >
              <Text style={[styles.chipText, visibility === v && styles.chipTextActive]}>
                {t(`create.visibility.${v}`)}
              </Text>
              {premiumLocked && <Text style={styles.premiumBadge}>{t('account.tier.premium')}</Text>}
            </Pressable>
          );
        })}
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
  content: { padding: spacing.md, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  pageTitle: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.lg },
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
    backgroundColor: 'transparent',
  },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  chipTextActive: { color: '#FFFFFF', fontWeight: '700' },
  chipLocked: { opacity: 0.4 },
  premiumBadge: { color: colors.warning, fontSize: fontSizes.xs, fontWeight: 'bold', marginLeft: spacing.xs },
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
  durationRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  dateButton: {
    backgroundColor: 'transparent',
    borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm + 2,
  },
  dateValue: { color: colors.textPrimary, fontSize: fontSizes.md },
  locked: { opacity: 0.4 },
  lockedHint: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.xs, fontStyle: 'italic' },
  rangeHint: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600', marginTop: spacing.sm },
  saveButton: { backgroundColor: colors.cta, borderRadius: radius.sm, paddingVertical: spacing.sm + 2, alignItems: 'center', marginTop: spacing.xl },
  buttonDisabled: { opacity: 0.4 },
  saveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});
