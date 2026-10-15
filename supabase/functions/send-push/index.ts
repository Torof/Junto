// Edge function: send push notification via Expo Push API
// Called by DB trigger on notifications INSERT (and direct calls from server-side functions).
// Deployment: npm run push:templates && supabase functions deploy send-push --no-verify-jwt
//
// Auth: a shared secret (`PUSH_WEBHOOK_SECRET`) must be passed in the
// `x-junto-push-secret` header. The DB trigger reads the same secret
// from a Postgres setting. Without this header the request is rejected.
//
// Language (lot 0, 2026-10-15): when the payload's `data` carries `type` and
// `params` (+ optional `variant`), the title/body are COMPOSED per recipient
// from templates.json (generated from the app's src/i18n/*.json — one source of
// truth) in that user's `users.language`. Otherwise, or when a template or a
// placeholder is missing, the French title/body sent by the DB are used as is.
// Same semantics as the app's src/utils/notification-text.ts.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import templates from './templates.json' with { type: 'json' };

interface Payload {
  user_id?: string;          // single-recipient (legacy callers)
  user_ids?: string[];       // batched fan-out (messaging trigger, ≤20 users)
  title: string;
  body: string;
  data?: Record<string, unknown>;
  collapseId?: string;
}

interface ExpoTicket {
  status: 'ok' | 'error';
  id?: string;
  message?: string;
  details?: { error?: string };
}

type Tpl = string | { [k: string]: Tpl };
interface LangBundle { notif: Record<string, Tpl>; period: { am: string; pm: string } }
const BUNDLES = (templates as { languages: Record<string, LangBundle> }).languages;
const DEFAULT_LANG = 'fr';

const SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET');

// Constant-time string equality. The naïve `===` short-circuits on
// the first differing byte, leaking prefix-match length via timing.
// For a fixed-size secret like ours, length-equality leakage is a
// non-issue (the length is well known once the secret is set), so we
// can early-return on length mismatch and only need to be constant-
// time across the byte loop itself.
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

// Expo errors that mean "this token is permanently dead" — delete the row
// so we stop targeting it. Other transient errors (e.g. MessageRateExceeded)
// are not on this list and the token stays.
const DEAD_TOKEN_ERRORS = new Set([
  'DeviceNotRegistered',
  'MismatchSenderId',
  'InvalidCredentials',
]);

// ---------- Composition in the recipient's language ----------
const PLACEHOLDER = /\{\{\s*([a-zA-Z_]+)\s*\}\}/g;

function lookup(bundle: LangBundle, path: string): string | null {
  let cur: Tpl | undefined = bundle.notif as unknown as Tpl;
  for (const part of path.split('.')) {
    if (cur === undefined || typeof cur === 'string') return null;
    cur = cur[part];
  }
  return typeof cur === 'string' ? cur : null;
}

function hasAll(template: string, vars: Record<string, string>): boolean {
  for (const m of template.matchAll(PLACEHOLDER)) {
    if (m[1] && !(m[1] in vars)) return false;
  }
  return true;
}

function fill(template: string, vars: Record<string, string>): string {
  return template.replace(PLACEHOLDER, (_, name: string) => vars[name] ?? '');
}

function formatDay(iso: string, lang: string): string {
  const d = new Date(`${iso}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return iso;
  try {
    return new Intl.DateTimeFormat(lang, { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }).format(d);
  } catch {
    return iso;
  }
}

function compose(
  lang: string,
  data: Record<string, unknown> | undefined,
): { title: string; body: string } | null {
  const type = typeof data?.type === 'string' ? data.type : null;
  const params = data?.params;
  if (!type || !params || typeof params !== 'object') return null;
  const bundle = BUNDLES[lang] ?? BUNDLES[DEFAULT_LANG];
  if (!bundle) return null;

  const variant = typeof data?.variant === 'string' ? data.variant : null;
  const key = variant && lookup(bundle, `${type}.${variant}.title`) !== null ? `${type}.${variant}` : type;
  const title = lookup(bundle, `${key}.title`);
  if (title === null) return null;

  const vars: Record<string, string> = { reason: '' };
  for (const [k, v] of Object.entries(params as Record<string, unknown>)) {
    if (v === null || v === undefined) continue;
    vars[k] = String(v);
  }
  if (vars.date) vars.date = formatDay(vars.date, lang);
  if (vars.period === 'am' || vars.period === 'pm') vars.period = bundle.period[vars.period];

  let body = lookup(bundle, `${key}.body`);
  if (body === null) {
    const n = Number(vars.count ?? '2');
    const one = n === 1 || (lang === 'fr' && n === 0);
    body = lookup(bundle, `${key}.${one ? 'body_one' : 'body_other'}`) ?? lookup(bundle, `${key}.body_other`);
  }
  if (body === null) return null;
  if (!hasAll(title, vars) || !hasAll(body, vars)) return null;
  return {
    title: fill(title, vars).trim(),
    body: fill(body, vars).replace(/\s+[—:]\s*$/, '').trim(),
  };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Reject if the shared secret is missing or wrong.
  const provided = req.headers.get('x-junto-push-secret') ?? '';
  if (!SECRET || !constantTimeEqual(provided, SECRET)) {
    return new Response('Forbidden', { status: 403 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }
  const { user_id, user_ids, title, body, data, collapseId } = payload;
  const targets = (user_ids && user_ids.length > 0 ? user_ids : (user_id ? [user_id] : []))
    .filter((u): u is string => typeof u === 'string' && u.length > 0)
    .slice(0, 50); // hard bound — the group cap is 20, anything above is a bug
  if (targets.length === 0 || !title) {
    return new Response('Missing fields', { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Fan out to every device the user is signed into. Falls back to
  // users.push_token only if push_tokens has no rows yet (first-run / unmigrated).
  const { data: tokenRows, error } = await supabase
    .from('push_tokens')
    .select('token, user_id')
    .in('user_id', targets);

  let tokens: { token: string; user_id: string }[] = (tokenRows ?? [])
    .filter((r): r is { token: string; user_id: string } => typeof r.token === 'string' && r.token.length > 0);

  // Legacy fallback only makes sense for the single-recipient shape.
  if (tokens.length === 0 && !error && targets.length === 1) {
    const { data: legacy } = await supabase
      .from('users')
      .select('push_token')
      .eq('id', targets[0])
      .single();
    if (legacy?.push_token) tokens = [{ token: legacy.push_token, user_id: targets[0]! }];
  }

  if (tokens.length === 0) {
    return new Response('No token', { status: 204 });
  }

  // Recipient languages (users.language, 00445) — only needed when the
  // payload is composable; one query for the whole batch.
  const langByUser = new Map<string, string>();
  if (data && typeof data.type === 'string' && data.params) {
    const { data: langRows } = await supabase
      .from('users')
      .select('id, language')
      .in('id', targets);
    for (const r of langRows ?? []) {
      if (typeof r.id === 'string' && typeof r.language === 'string') langByUser.set(r.id, r.language);
    }
  }
  const textCache = new Map<string, { title: string; body: string }>();
  const textFor = (uid: string): { title: string; body: string } => {
    const lang = langByUser.get(uid) ?? DEFAULT_LANG;
    const cached = textCache.get(lang);
    if (cached) return cached;
    const composed = compose(lang, data) ?? { title, body };
    textCache.set(lang, composed);
    return composed;
  };

  // Expo Push API accepts an array of messages in a single request (up to 100).
  const messages = tokens.map(({ token, user_id: uid }) => {
    const text = textFor(uid);
    const msg: Record<string, unknown> = {
      to: token,
      title: text.title,
      body: text.body,
      data: data ?? {},
      sound: 'default',
      priority: 'high',
    };
    if (collapseId) {
      msg.collapseId = collapseId;
      msg.androidCollapseKey = collapseId;
    }
    return msg;
  });
  const flatTokens = tokens.map((t) => t.token);

  // Expo accepts up to 100 messages per request — chunk the batch (a 20-user
  // group with multiple devices each can exceed 100 tokens).
  let anyFailed = false;
  let expoBody = '';
  const allTickets: ExpoTicket[] = [];
  for (let i = 0; i < messages.length; i += 100) {
    const chunk = messages.slice(i, i + 100);
    const expoRes = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(chunk),
    });
    expoBody = await expoRes.text();
    if (!expoRes.ok) {
      anyFailed = true;
      continue;
    }
    try {
      const parsed = JSON.parse(expoBody);
      const chunkTickets: ExpoTicket[] = Array.isArray(parsed?.data) ? parsed.data : [];
      allTickets.push(...chunkTickets);
    } catch {
      console.warn('[send-push] expo response parse failed');
    }
  }

  // Best-effort token cleanup. Tickets align with the flat token order only
  // when every chunk succeeded and parsed — skip cleanup otherwise.
  if (!anyFailed && allTickets.length === flatTokens.length) {
    try {
      const deadTokens: string[] = [];
      allTickets.forEach((ticket, i) => {
        if (
          ticket?.status === 'error' &&
          ticket.details?.error &&
          DEAD_TOKEN_ERRORS.has(ticket.details.error) &&
          flatTokens[i]
        ) {
          deadTokens.push(flatTokens[i]!);
        }
      });
      if (deadTokens.length > 0) {
        const { error: delErr } = await supabase
          .from('push_tokens')
          .delete()
          .in('token', deadTokens);
        if (delErr) {
          // Don't log delErr.message — Supabase errors can carry stack
          // traces, internal paths, etc. that we don't want in function
          // logs. The count + a stable label are enough for diagnosis.
          console.warn(`[send-push] push_tokens delete failed for ${deadTokens.length} token(s)`);
        }
      }
    } catch {
      console.warn('[send-push] expo response parse failed');
    }
  }

  // Pass Expo's body through so per-message statuses are visible in
  // net._http_response.content (DeviceNotRegistered, MismatchSenderId, etc).
  return new Response(expoBody || '{}', {
    status: anyFailed ? 502 : 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
