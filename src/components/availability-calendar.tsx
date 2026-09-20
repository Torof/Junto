import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { ChevronLeft, ChevronRight } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing } from '@/constants/theme';
import type { BookingPeriod } from '@/services/booking-service';

// Per-slot decoration computed by the parent: whether the half-day is open,
// and optional booking counts to badge (pro agenda only).
export interface SlotState {
  available: boolean;
  accepted?: number;
  pending?: number;
}

interface Props {
  // 'edit'  → pro agenda: tap toggles availability (onToggle).
  // 'pick'  → client: only available slots are tappable (onPick), one selected.
  mode: 'edit' | 'pick';
  slotState: (day: string, period: BookingPeriod) => SlotState;
  onToggle?: (day: string, period: BookingPeriod, nextAvailable: boolean) => void;
  onPick?: (day: string, period: BookingPeriod) => void;
  selected?: { day: string; period: BookingPeriod } | null;
  // Month navigation is internal; parent learns the visible month to fetch data.
  onMonthChange?: (monthStartIso: string) => void;
  maxMonthsAhead?: number; // default 6 (DB bound)
}

const PERIODS: BookingPeriod[] = ['am', 'pm'];

export function AvailabilityCalendar({
  mode, slotState, onToggle, onPick, selected, onMonthChange, maxMonthsAhead = 6,
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

    let bg = 'transparent';
    if (isSelected) bg = colors.cta;
    else if (bookedCount > 0) bg = colors.cta + 'CC';
    else if (pendingCount > 0) bg = colors.warning + '66';
    else if (st.available) bg = colors.cta + '2E';

    const disabled = isPast || (mode === 'pick' && !st.available);
    const onPress = () => {
      if (disabled) return;
      if (mode === 'edit') onToggle?.(iso, period, !st.available);
      else onPick?.(iso, period);
    };

    return (
      <Pressable
        key={period}
        disabled={disabled}
        onPress={onPress}
        style={[styles.half, period === 'am' ? styles.halfTop : styles.halfBottom, { backgroundColor: bg }]}
      >
        {(bookedCount > 0 || pendingCount > 0) && mode === 'edit' ? (
          <Text style={styles.slotCount}>{bookedCount + pendingCount}</Text>
        ) : null}
      </Pressable>
    );
  };

  return (
    <View style={styles.card}>
      <View style={styles.head}>
        <Pressable onPress={() => goMonth(-1)} hitSlop={10}>
          <ChevronLeft size={20} color={colors.textSecondary} strokeWidth={2.2} />
        </Pressable>
        <Text style={styles.monthLabel}>{month.locale('fr').format('MMMM YYYY')}</Text>
        <Pressable onPress={() => goMonth(1)} hitSlop={10}>
          <ChevronRight size={20} color={colors.textSecondary} strokeWidth={2.2} />
        </Pressable>
      </View>

      <View style={styles.dowRow}>
        {dow.map((d, i) => <Text key={i} style={styles.dow}>{d}</Text>)}
      </View>

      <View style={styles.grid}>
        {cells.map((day, i) => {
          if (!day) return <View key={`x${i}`} style={styles.cellEmpty} />;
          const isPast = day.isBefore(today);
          const isToday = day.isSame(today, 'day');
          return (
            <View key={day.format('YYYY-MM-DD')} style={[styles.cell, isPast && styles.cellPast, isToday && styles.cellToday]}>
              <Text style={styles.dayNum}>{day.date()}</Text>
              {PERIODS.map((p) => renderHalf(day, p, isPast))}
            </View>
          );
        })}
      </View>

      <View style={styles.legend}>
        <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.cta + '2E' }]} /><Text style={styles.legendText}>{t('booking.legendAvailable', { defaultValue: 'Dispo' })}</Text></View>
        {mode === 'edit' && (
          <>
            <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.cta }]} /><Text style={styles.legendText}>{t('booking.legendBooked', { defaultValue: 'Réservé' })}</Text></View>
            <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.warning + '66' }]} /><Text style={styles.legendText}>{t('booking.legendPending', { defaultValue: 'Demande' })}</Text></View>
          </>
        )}
        <View style={styles.legendItem}><View style={[styles.legendDot, { backgroundColor: colors.surfaceAlt }]} /><Text style={styles.legendText}>{t('booking.legendOff', { defaultValue: 'Indispo' })}</Text></View>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: { backgroundColor: colors.surface, borderRadius: 18, padding: spacing.md },
  head: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  monthLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', textTransform: 'capitalize' },
  dowRow: { flexDirection: 'row', marginBottom: 4 },
  dow: { flex: 1, textAlign: 'center', color: colors.textMuted, fontSize: fontSizes.xs - 1, fontWeight: '700' },
  grid: { flexDirection: 'row', flexWrap: 'wrap' },
  cellEmpty: { width: `${100 / 7}%`, height: 48 },
  cell: {
    width: `${100 / 7}%`, height: 48, borderRadius: 8, backgroundColor: colors.surfaceAlt,
    padding: 1.5, gap: 1.5, borderWidth: 1.5, borderColor: colors.background,
  },
  cellPast: { opacity: 0.35 },
  cellToday: { borderColor: colors.cta },
  dayNum: {
    position: 'absolute', top: 2, left: 4, zIndex: 2,
    color: colors.textPrimary, fontSize: 9, fontWeight: '700', opacity: 0.75,
  },
  half: { flex: 1 },
  halfTop: { borderTopLeftRadius: 6, borderTopRightRadius: 6 },
  halfBottom: { borderBottomLeftRadius: 6, borderBottomRightRadius: 6 },
  slotCount: {
    position: 'absolute', right: 2, top: '50%', marginTop: -7,
    minWidth: 14, height: 14, borderRadius: 7, backgroundColor: '#00000044',
    color: '#FFFFFF', fontSize: 9, fontWeight: '800', textAlign: 'center', lineHeight: 14, paddingHorizontal: 2,
    overflow: 'hidden',
  },
  legend: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm + 2, marginTop: spacing.sm + 2 },
  legendItem: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  legendDot: { width: 12, height: 12, borderRadius: 4 },
  legendText: { color: colors.textSecondary, fontSize: fontSizes.xs },
});
