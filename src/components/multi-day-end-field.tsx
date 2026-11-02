import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { CalendarRange, Check } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { MAX_ACTIVITY_DAYS, formatDurationMs, splitDuration } from '@/utils/activity-time';

const HOUR = 3600 * 1000;

// Multi-day outings (Scott 2026-11-02, up to 7 days): instead of the hour
// counter, the organiser picks WHEN IT ENDS (date, then time); the duration
// stored is still `N hours M minutes`, derived from start → end.
export function MultiDayEndField({ startsAt, hours, minutes, onChange, disabled = false, style }: {
  startsAt: Date | null;
  hours: number;
  minutes: number;
  onChange: (hours: number, minutes: number) => void;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const [step, setStep] = useState<'date' | 'time' | null>(null);
  const [pendingDate, setPendingDate] = useState<Date | null>(null);

  const durationMs = (hours * 60 + minutes) * 60000;
  const end = startsAt ? new Date(startsAt.getTime() + durationMs) : null;

  const apply = (next: Date) => {
    if (!startsAt) return;
    const ms = next.getTime() - startsAt.getTime();
    if (ms < 12 * HOUR) {
      Burnt.toast({ title: t('multiDay.tooShort', { defaultValue: 'La fin doit être au moins 12 h après le départ.' }) });
      return;
    }
    if (ms > MAX_ACTIVITY_DAYS * 24 * HOUR) {
      Burnt.toast({ title: t('multiDay.tooLong', { defaultValue: '7 jours maximum.', count: MAX_ACTIVITY_DAYS }) });
      return;
    }
    const d = splitDuration(ms);
    onChange(d.hours, d.minutes);
  };

  return (
    <>
      <Pressable
        style={[styles.box, disabled && styles.locked, style]}
        onPress={() => { if (!disabled && startsAt) setStep('date'); }}
        disabled={disabled || !startsAt}
        accessibilityRole="button"
      >
        <View style={styles.head}>
          <CalendarRange size={18} color={colors.textSecondary} strokeWidth={2.2} />
          <AppText style={styles.label}>
            {t('multiDay.endLabel', { defaultValue: 'Fin' })} · {formatDurationMs(durationMs)}
          </AppText>
        </View>
        <AppText style={styles.value} numberOfLines={1}>
          {end ? dayjs(end).locale(i18n.language).format('ddd D MMM · H[h]mm') : t('multiDay.pickStartFirst', { defaultValue: 'Choisis d’abord le départ' })}
        </AppText>
      </Pressable>

      {step === 'date' && startsAt && (
        <DateTimePicker
          value={end ?? startsAt}
          mode="date"
          minimumDate={startsAt}
          maximumDate={dayjs(startsAt).add(MAX_ACTIVITY_DAYS, 'day').toDate()}
          onChange={(_e, date) => {
            setStep(null);
            if (date) { setPendingDate(date); setStep('time'); }
          }}
        />
      )}
      {step === 'time' && pendingDate && (
        <DateTimePicker
          value={end ?? pendingDate}
          mode="time"
          onChange={(_e, time) => {
            setStep(null);
            if (time) {
              // Keep the picked DATE, take only the time (Android returns today).
              const next = new Date(pendingDate);
              next.setHours(time.getHours(), time.getMinutes(), 0, 0);
              apply(next);
            }
            setPendingDate(null);
          }}
        />
      )}
    </>
  );
}

// « Sur plusieurs jours » switch shown under the duration.
export function MultiDayToggle({ value, onChange, disabled = false }: {
  value: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  return (
    <Pressable
      style={[styles.toggle, disabled && styles.locked]}
      onPress={() => !disabled && onChange(!value)}
      disabled={disabled}
      accessibilityRole="checkbox"
      accessibilityState={{ checked: value, disabled }}
      hitSlop={6}
    >
      <View style={[styles.check, value && { backgroundColor: colors.cta, borderColor: colors.cta }]}>
        {value ? <Check size={13} color={colors.onCta} strokeWidth={3} /> : null}
      </View>
      <AppText style={styles.toggleText}>{t('multiDay.toggle', { defaultValue: 'Sur plusieurs jours (bivouac, refuge…)' })}</AppText>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  box: {
    borderRadius: radius.sm, borderWidth: 1, borderColor: colors.borderMuted,
    padding: spacing.sm + 2, marginBottom: spacing.md, gap: spacing.xs,
  },
  head: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  label: { color: colors.textSecondary, fontSize: fontSizes.xs },
  value: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  locked: { opacity: 0.4 },
  toggle: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: -spacing.xs, marginBottom: spacing.md },
  check: {
    width: 20, height: 20, borderRadius: 6, borderWidth: 1.5, borderColor: colors.borderStrong,
    alignItems: 'center', justifyContent: 'center',
  },
  toggleText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
});
