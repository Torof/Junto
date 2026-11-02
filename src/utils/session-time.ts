import dayjs from 'dayjs';
import i18n from '@/i18n';
import type { SessionWindow } from '@/services/session-service';

// Fixed dates (00575) in words: « Dim. 8 nov. · matin », « Sam. 21 nov. ·
// journée », « Ven. 13 → dim. 15 nov. ».

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export type SessionLength = 'half' | 'day' | 'multi';

export const sessionLength = (w: SessionWindow): SessionLength =>
  w.end_day > w.start_day ? 'multi' : w.start_period !== w.end_period ? 'day' : 'half';

export const sessionDays = (w: SessionWindow) => dayjs(w.end_day).diff(dayjs(w.start_day), 'day') + 1;

export function sessionRange(w: SessionWindow): string {
  const s = dayjs(w.start_day).locale(i18n.language);
  const len = sessionLength(w);
  if (len === 'multi') {
    const e = dayjs(w.end_day).locale(i18n.language);
    const left = s.isSame(e, 'month') ? s.format('ddd D') : s.format('ddd D MMM');
    return `${cap(left)} → ${e.format('ddd D MMM')}`;
  }
  const what = len === 'day'
    ? i18n.t('session.wholeDay', { defaultValue: 'journée' })
    : w.start_period === 'am'
      ? i18n.t('booking.am', { defaultValue: 'matin' })
      : i18n.t('booking.pm', { defaultValue: 'après-midi' });
  return `${cap(s.format('ddd D MMM'))} · ${what}`;
}

// Third line of the date block: « 3 jours », « journée », « matin ».
export function sessionBlockSub(w: SessionWindow): string {
  const len = sessionLength(w);
  if (len === 'multi') return i18n.t('session.daysCount', { defaultValue: '{{count}} jours', count: sessionDays(w) });
  if (len === 'day') return i18n.t('session.wholeDay', { defaultValue: 'journée' });
  return w.start_period === 'am'
    ? i18n.t('booking.halfAm', { defaultValue: 'matin' })
    : i18n.t('booking.halfPm', { defaultValue: 'a-midi' });
}

// Half-days of a date, start to end: [['2026-11-13','am'], …].
export function sessionHalfDays(w: SessionWindow): [string, 'am' | 'pm'][] {
  const out: [string, 'am' | 'pm'][] = [];
  let d = dayjs(w.start_day);
  let p: 'am' | 'pm' = w.start_period;
  for (let guard = 0; guard < 40; guard++) {
    const iso = d.format('YYYY-MM-DD');
    out.push([iso, p]);
    if (iso === w.end_day && p === w.end_period) break;
    if (p === 'am') p = 'pm'; else { p = 'am'; d = d.add(1, 'day'); }
  }
  return out;
}
