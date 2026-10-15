import dayjs from 'dayjs';
import i18n from '@/i18n';

// Notifications in the reader's language (DECISIONS 2026-10-14, lot 0).
//
// The server keeps writing a French title/body (the fallback) but, type by
// type (lots A→G), it also stores the VARIABLES of the sentence in
// data.params (+ an optional data.variant). This composer rebuilds the text
// from the `notif.<type>[.<variant>]` templates of the app's own translation
// files. Same semantics as the Edge Function (send-push) for the push text:
//   - template missing, or a placeholder it needs missing from params → null →
//     the caller shows the stored French text (an unmigrated type never
//     regresses);
//   - `date` (ISO day) is formatted in the current locale, `period` am/pm
//     becomes a word, `count` picks body_one / body_other.
export type NotifParams = Record<string, string | number | null | undefined>;

export interface NotifData {
  params?: NotifParams;
  variant?: string;
  type?: string;
}

const PLACEHOLDER = /\{\{\s*([a-zA-Z_]+)\s*\}\}/g;

function raw(key: string): string | null {
  const lang = i18n.language;
  const v = i18n.getResource(lang, 'translation', key) ?? i18n.getResource('en', 'translation', key);
  return typeof v === 'string' ? v : null;
}

function fill(template: string, vars: Record<string, string>): string {
  return template.replace(PLACEHOLDER, (_, name: string) => vars[name] ?? '');
}

function hasAll(template: string, vars: Record<string, string>): boolean {
  for (const m of template.matchAll(PLACEHOLDER)) {
    const name = m[1];
    if (name && !(name in vars)) return false;
  }
  return true;
}

export function renderNotification(
  type: string,
  data: NotifData | null | undefined,
): { title: string; body: string } | null {
  const params = data?.params;
  if (!params) return null;

  const base = `notif.${type}`;
  const variantKey = data?.variant ? `${base}.${data.variant}` : null;
  const key = variantKey && raw(`${variantKey}.title`) !== null ? variantKey : base;
  const title = raw(`${key}.title`);
  if (title === null) return null;

  const vars: Record<string, string> = { reason: '' };
  for (const [k, v] of Object.entries(params)) {
    if (v === null || v === undefined) continue;
    vars[k] = String(v);
  }
  if (vars.date) vars.date = dayjs(vars.date).format('ddd D MMM');
  if (vars.period === 'am' || vars.period === 'pm') {
    vars.period = i18n.t(`booking.${vars.period}`, { defaultValue: vars.period });
  }

  let body = raw(`${key}.body`);
  if (body === null) {
    const n = Number(vars.count ?? '2');
    const one = n === 1 || (i18n.language === 'fr' && n === 0);
    body = raw(`${key}.${one ? 'body_one' : 'body_other'}`) ?? raw(`${key}.body_other`);
  }
  if (body === null) return null;
  if (!hasAll(title, vars) || !hasAll(body, vars)) return null;

  return {
    title: fill(title, vars).trim(),
    body: fill(body, vars).replace(/\s+[—:]\s*$/, '').trim(),
  };
}
