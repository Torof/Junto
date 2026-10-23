import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { ChevronLeft, ChevronRight } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, shadows, radius } from '@/constants/theme';
import { sportCategoryColor } from '@/utils/sport-category-color';
import type { BookingPeriod } from '@/services/booking-service';

// Per-slot decoration computed by the parent. Sport category drives the fill
// color of booked/pending half-days (maquette 2026-09-28 : « teinte = sport »).
export interface SlotState {
  available: boolean;
  accepted?: number;
  pending?: number;
  // Initials (or +N) shown on the half-day, pro agenda only.
  label?: string | null;
  sportCategory?: string | null;
}

interface Props {
  // 'view'  → pro agenda default: tap a DAY opens its sheet (onDayPress).
  // 'edit'  → pro dispo mode: tap a half-day toggles availability (onToggle);
  //           half-days holding bookings are NOT togglable here.
  // 'pick'  → client: only available slots are tappable (onPick), one selected.
  mode: 'view' | 'edit' | 'pick';
  slotState: (day: string, period: BookingPeriod) => SlotState;
  onToggle?: (day: string, period: BookingPeriod, nextAvailable: boolean) => void;
  onPick?: (day: string, period: BookingPeriod) => void;
  onDayPress?: (day: string) => void;
  selected?: { day: string; period: BookingPeriod } | null;
  selectedDay?: string | null;
  // Month navigation is internal; parent learns the visible month to fetch data.
  onMonthChange?: (monthStartIso: string) => void;
  maxMonthsAhead?: number; // default 6 (DB bound)
}

const PERIODS: BookingPeriod[] = ['am', 'pm'];

export function AvailabilityCalendar({
  mode, slotState, onToggle, onPick, onDayPress, selected, selectedDay, onMonthChange, maxMonthsAhead = 6,
}: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const [month, setMonth] = useState(() => dayjs().startOf('month'));

  const today = dayjs().startOf('day');
  const maxMonth = today.add(maxMonthsAhead, 'month').startOf('month');

  const goMonth = (delta: number) => {
    const next = month.add(delta, 'month');
    if (next.isBefore(today.startOf('month')) || next.isAfter(maxMonth)) return;
    setMonth(next);
    onMonthChange?.(next.format('YYYY-MM-DD'));
  };

  // Monday-first grid of the visible month.
  const cells = useMemo(() => {
    const first = month.startOf('month');
    const lead = (first.day() + 6) % 7; // 0 = Monday
    const daysInMonth = month.daysInMonth();
    const out: (dayjs.Dayjs | null)[] = [];
    for (let i = 0; i < lead; i++) out.push(null);
    for (let d = 1; d <= daysInMonth; d++) out.push(first.date(d));
    return out;
  }, [month]);

  const dow = [
    t('calendar.mon', { defaultValue: 'L' }), t('calendar.tue', { defaultValue: 'M' }),
    t('calendar.wed', { defaultValue: 'M' }), t('calendar.thu', { defaultValue: 'J' }),
    t('calendar.fri', { defaultValue: 'V' }), t('calendar.sat', { defaultValue: 'S' }),
    t('calendar.sun', { defaultValue: 'D' }),
  ];

  const renderHalf = (day: dayjs.Dayjs, period: BookingPeriod, isPast: boolean) => {
    const iso = day.format('YYYY-MM-DD');
    const st = slotState(iso, period);
    const isSelected = selected?.day === iso && selected?.period === period;
    const bookedCount = st.accepted ?? 0;
    const pendingCount = st.pending ?? 0;
    const sportColor = sportCategoryColor(st.sportCategory, colors.cta);

    let bg = 'transparent';
    let dashed = false;
    if (isSelected) bg = colors.cta;
    else if (bookedCount > 0) bg = sportColor;
    else if (pendingCount > 0) { bg = sportColor + '2E'; dashed = true; }
    else if (st.available) bg = colors.cta + '2E';

    const hasBooking = bookedCount > 0 || pendingCount > 0;
    // view → the whole day is the target; edit → booked slots untouchable;
    // pick → only open slots.
    const disabled =
      isPast
      || mode === 'view'
      || (mode === 'edit' && hasBooking)
      || (mode === 'pick' && !st.available);
    const onPress = () => {
      if (disabled) return;
      if (mode === 'edit') onToggle?.(iso, period, !st.available);
      else if (mode === 'pick') onPick?.(iso, period);
    };

    // Each half-day is a ≥ 44 pt target and says what it is (lot 2 pro,
    // 2026-10-15): the pro taps these gloves on, the old 48×26 cells
    // mis-tapped morning for afternoon.
    const periodWord = period === 'am'
      ? t('booking.halfAm', { defaultValue: 'matin' })
      : t('booking.halfPm', { defaultValue: 'a-midi' });
    const labelColor = isSelected ? colors.onCta : bookedCount > 0 ? colors.onCta : sportColor;
    return (
      <Pressable
        key={period}
        disabled={disabled}
        onPress={onPress}
        style={[
          styles.half,
          { backgroundColor: bg },
          dashed && { borderWidth: 1.5, borderStyle: 'dashed', borderColor: sportColor + 'BB' },
        ]}
        accessibilityLabel={`${periodWord} ${day.format('D MMMM')}`}
      >
        {st.label && mode !== 'pick' ? (
          <AppText style={[styles.slotLabel, { color: labelColor }]} numberOfLines={1}>
            {st.label}
          </AppText>
        ) : (
          <AppText style={[styles.slotWord, { color: isSelected ? colors.onCta : st.available ? colors.textPrimary : colors.textMuted }]} numberOfLines={1}>
            {periodWord}
          </AppText>
        )}
      </Pressable>
    );
  };

  return (
    <View style={styles.card}>
      <View style={styles.head}>
        <Pressable onPress={() => goMonth(-1)} hitSlop={10} accessibilityLabel={t('calendar.prevMonth', { defaultValue: 'Mois précédent' })}>
          <ChevronLeft size={20} color={colors.textSecondary} strokeWidth={2.2} />
        </Pressable>
        <AppText style={styles.monthLabel}>{month.format('MMMM YYYY')}</AppText>
        <Pressable onPress={() => goMonth(1)} hitSlop={10} accessibilityLabel={t('calendar.nextMonth', { defaultValue: 'Mois suivant' })}>
          <ChevronRight size={20} color={colors.textSecondary} strokeWidth={2.2} />
        </Pressable>
      </View>

      <View style={styles.dowRow}>
        {dow.map((d, i) => <AppText key={i} style={styles.dow}>{d}</AppText>)}
      </View>

      <View style={styles.grid}>
        {cells.map((day, i) => {
          if (!day) return <View key={`x${i}`} style={styles.cellEmpty} />;
          const iso = day.format('YYYY-MM-DD');
          const isPast = day.isBefore(today);
          const isToday = day.isSame(today, 'day');
          const isDaySelected = selectedDay === iso;
          const cell = (
            <View
              key={iso}
              style={[styles.cell, isPast && styles.cellPast, isToday && styles.cellToday, isDaySelected && styles.cellSelected]}
            >
              <AppText style={styles.dayNum}>{day.date()}</AppText>
              {PERIODS.map((p) => renderHalf(day, p, isPast))}
            </View>
          );
          if (mode === 'view' && !isPast) {
            return (
              <Pressable key={iso} style={styles.cellWrap} onPress={() => onDayPress?.(iso)}>
                {cell}
              </Pressable>
            );
          }
          return <View key={iso} style={styles.cellWrap}>{cell}</View>;
        })}
      </View>

      <View style={styles.legend}>
        <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.cta + '2E' }]} /><AppText style={styles.legendText}>{t('booking.legendAvailable', { defaultValue: 'Ouvert' })}</AppText></View>
        {mode !== 'pick' && (
          <>
            <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.cta }]} /><AppText style={styles.legendText}>{t('booking.legendBooked', { defaultValue: 'Réservé' })}</AppText></View>
            <View style={styles.legendItem}><View style={[styles.legendDot, styles.legendDashed, { backgroundColor: colors.cta + '2E', borderColor: colors.cta }]} /><AppText style={styles.legendText}>{t('booking.legendPending', { defaultValue: 'Demande' })}</AppText></View>
          </>
        )}
        <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.surfaceAlt }]} /><AppText style={styles.legendText}>{t('booking.legendOff', { defaultValue: 'Fermé' })}</AppText></View>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: { backgroundColor: colors.surface, borderRadius: 18, padding: spacing.md, borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card },
  head: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  monthLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', textTransform: 'capitalize' },
  dowRow: { flexDirection: 'row', marginBottom: 4 },
  dow: { flex: 1, textAlign: 'center', color: colors.textMuted, fontSize: fontSizes.xs - 1, fontWeight: '700' },
  grid: { flexDirection: 'row', flexWrap: 'wrap' },
  cellEmpty: { width: `${100 / 7}%`, height: 108 },
  cellWrap: { width: `${100 / 7}%` },
  cell: {
    height: 108, borderRadius: radius.lg, backgroundColor: colors.surfaceAlt,
    padding: 2, gap: 2, borderWidth: 1, borderColor: colors.lineStrong,
    margin: 0.5,
  },
  cellPast: { opacity: 0.35 },
  cellToday: { borderColor: colors.cta },
  cellSelected: { borderColor: colors.textPrimary },
  dayNum: {
    height: 14, lineHeight: 14, textAlign: 'center',
    color: colors.textPrimary, fontSize: fontSizes.xs - 2, fontWeight: '700', opacity: 0.8,
  },
  // 2 × 42 pt half-days + the day number — the whole half is the target.
  half: { flex: 1, minHeight: 42, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center' },
  slotLabel: { fontSize: fontSizes.xs - 2, fontWeight: '800', letterSpacing: 0.3 },
  slotWord: { fontSize: fontSizes.xs - 3, fontWeight: '700' },
  legend: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm + 2, marginTop: spacing.sm + 2 },
  legendItem: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  legendDot: { width: 12, height: 12, borderRadius: 4 },
  legendDashed: { borderWidth: 1.5, borderStyle: 'dashed' },
  legendText: { color: colors.textSecondary, fontSize: fontSizes.xs },
});
