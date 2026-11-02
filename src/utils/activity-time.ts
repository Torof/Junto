import dayjs from 'dayjs';
import i18n from '@/i18n';
import { parsePgIntervalMs } from '@/utils/parse-pg-interval';

// Multi-day outings between enthusiasts (Scott 2026-11-02, up to 7 days):
// shared duration / date-range formatting so a 3-day trek reads « 2 j 4h » and
// « sam. 8 → lun. 10 nov. » everywhere instead of « 52h » and the start alone.

const HOUR = 3600 * 1000;
export const MAX_ACTIVITY_DAYS = 7; // DB: activities_duration_check

// 45 min → « 45min », 3 h 30 → « 3h30 », 52 h → « 2 j 4h ».
export function formatDurationMs(ms: number): string {
  const totalMinutes = Math.max(0, Math.round(ms / 60000));
  const hoursAll = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hoursAll >= 24) {
    const days = Math.floor(hoursAll / 24);
    const hours = hoursAll % 24;
    const d = i18n.t('durationFmt.days', { defaultValue: '{{count}} j', count: days });
    return hours > 0 ? `${d} ${hours}h` : d;
  }
  if (hoursAll === 0) return `${minutes}min`;
  if (minutes === 0) return `${hoursAll}h`;
  return `${hoursAll}h${String(minutes).padStart(2, '0')}`;
}

export const formatInterval = (raw: string | null | undefined): string | null =>
  raw ? formatDurationMs(parsePgIntervalMs(raw)) : null;

export const activityEnd = (startIso: string, rawDuration: string | null | undefined) =>
  dayjs(startIso).add(parsePgIntervalMs(rawDuration), 'millisecond');

// A long outing (>= 12 h) that ends on another calendar day.
export function isMultiDay(startIso: string, rawDuration: string | null | undefined): boolean {
  if (!rawDuration) return false;
  if (parsePgIntervalMs(rawDuration) < 12 * HOUR) return false;
  return !activityEnd(startIso, rawDuration).isSame(dayjs(startIso), 'day');
}

// « sam. 8 → lun. 10 nov. » (« sam. 31 oct. → lun. 2 nov. » across months);
// null for a single-day outing — callers keep their own format then.
export function multiDayRange(startIso: string, rawDuration: string | null | undefined): string | null {
  if (!isMultiDay(startIso, rawDuration)) return null;
  const s = dayjs(startIso).locale(i18n.language);
  const e = activityEnd(startIso, rawDuration).locale(i18n.language);
  const left = s.isSame(e, 'month') ? s.format('ddd D') : s.format('ddd D MMM');
  return `${left} → ${e.format('ddd D MMM')}`;
}

// Hours + minutes of a duration in ms, for the creation / edit forms (the
// stored interval is `N hours M minutes`, hours may exceed 24).
export const splitDuration = (ms: number) => {
  const totalMinutes = Math.round(ms / 60000);
  return { hours: Math.floor(totalMinutes / 60), minutes: totalMinutes % 60 };
};
