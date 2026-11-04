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

// An on-request booking (00577) as a window: a half-day, or start morning →
// last day afternoon when the offering is asked for by the day / over days.
export function requestWindow(day: string, period: 'am' | 'pm', days: number | null): SessionWindow {
  if (days == null) return { start_day: day, start_period: period, end_day: day, end_period: period };
  return { start_day: day, start_period: 'am', end_day: dayjs(day).add(days - 1, 'day').format('YYYY-MM-DD'), end_period: 'pm' };
}

// The start days of an offering asked for by the day / over days (00577): a
// morning whose whole range is open, with the fewest places left over it.
export function requestStarts(
  slots: { day: string; period: 'am' | 'pm'; taken: number }[],
  days: number,
  max: number | null,
): Map<string, { taken: number; free: number | null }> {
  const open = new Map(slots.map((s) => [`${s.day}|${s.period}`, s.taken]));
  const out = new Map<string, { taken: number; free: number | null }>();
  for (const s of slots) {
    if (s.period !== 'am') continue;
    let ok = true;
    let taken = 0;
    for (const [d, p] of sessionHalfDays(requestWindow(s.day, 'am', days))) {
      const t = open.get(`${d}|${p}`);
      if (t === undefined) { ok = false; break; }
      taken = Math.max(taken, t);
    }
    if (ok) out.set(s.day, { taken, free: max != null ? Math.max(0, max - taken) : null });
  }
  return out;
}

// The pro's request window (Espace pro + agenda « Demandes »): 14 days back —
// a multi-day outing begun earlier is still today's — to 6 months ahead, the
// furthest a client can ask (create_booking, 00580). get_pro_agenda allows 12.
export function requestsWindow(): { from: string; to: string } {
  return {
    from: dayjs().subtract(14, 'day').format('YYYY-MM-DD'),
    to: dayjs().add(6, 'month').format('YYYY-MM-DD'),
  };
}
