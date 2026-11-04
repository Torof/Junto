// Edge function: reads a pro's imported calendar (its secret iCal address,
// mig 00568) and turns it into busy half-days — nothing else is kept, never a
// title. pg_cron (private.trigger_calendar_import) calls it every 15 min, ONE
// call per pro (00578): a heavy or broken calendar never stops the others.
// Deployment: supabase functions deploy calendar-import --no-verify-jwt
//
// Auth: shared secret header `x-junto-push-secret` (same as send-push).
// Fetch hardening: allow-listed hosts only (re-checked here and on each
// redirect), 10 s timeout, 2 MB cap. Skipped events: TRANSP:TRANSPARENT
// (« disponible »), STATUS:CANCELLED, and our own feed (UID …@askandgo.io).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import ICAL from 'npm:ical.js@2.1.0';
import { HALF_DAYS, addDays, parisDay, parisToUtc } from '../_shared/paris-time.ts';

type IcalTime = InstanceType<typeof ICAL.Time>;
type IcalComponent = InstanceType<typeof ICAL.Component>;

const SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET');
const HOST_OK = /^https:\/\/(calendar\.google\.com|p[0-9]+-caldav\.icloud\.com|outlook\.office365\.com|outlook\.live\.com)\//;
const MAX_BYTES = 2 * 1024 * 1024;
const HORIZON_DAYS = 190;
const MAX_OCCURRENCES = 3000;   // occurrences inside the window, per event
// Work budget per calendar (00578): a small crafted file must not burn the
// worker's CPU. Over budget → 'too_large', shown to the pro, never a silent drop.
const MAX_EVENTS = 5000;
const MAX_STEPS = 25_000;          // days walked + occurrences in the window
const MAX_SKIPPED = 300_000;       // cheap steps over occurrences before the window
// 00580 (CALENDAR-8): the feed's own time zones are expanded by ical.js outside
// the budget above — only ordinary ones are kept (yearly rules from 1900, a
// handful of parts); an event in a refused zone is read without its zone.
// And a wall-clock budget, so we always fail with 'too_large' before the
// platform kills the worker (no error recorded then).
const MAX_ZONES = 50;
const MAX_ZONE_PARTS = 50;
const MAX_MS = 800;

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function fetchCalendar(url: string): Promise<string> {
  let current = url;
  for (let hop = 0; hop < 3; hop++) {
    if (!HOST_OK.test(current)) throw new Error('host');
    const res = await fetch(current, { redirect: 'manual', signal: AbortSignal.timeout(10_000) });
    if (res.status >= 300 && res.status < 400) {
      const next = res.headers.get('location');
      await res.body?.cancel();
      if (!next) throw new Error('redirect');
      current = new URL(next, current).toString();
      continue;
    }
    if (!res.ok) { await res.body?.cancel(); throw new Error(`http ${res.status}`); }
    const reader = res.body?.getReader();
    if (!reader) throw new Error('empty');
    const chunks: Uint8Array[] = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BYTES) { await reader.cancel(); throw new Error('too large'); }
      chunks.push(value);
    }
    const all = new Uint8Array(size);
    let off = 0;
    for (const c of chunks) { all.set(c, off); off += c.length; }
    return new TextDecoder().decode(all);
  }
  throw new Error('redirects');
}

type Slot = { day: string; period: 'am' | 'pm' };

function zoneOk(tz: IcalComponent): boolean {
  const parts = tz.getAllSubcomponents();
  let count = 0;
  for (const p of parts) {
    count += 1 + p.getAllProperties('rdate').length;
    if (count > MAX_ZONE_PARTS) return false;
    const start = p.getFirstPropertyValue('dtstart') as IcalTime | null;
    if (!start || start.year < 1900) return false;
    for (const rule of p.getAllProperties('rrule')) {
      const v = rule.getFirstValue() as { freq?: string } | null;
      if (!v || String(v.freq ?? '').toUpperCase() !== 'YEARLY') return false;
    }
  }
  return true;
}

function busySlots(ics: string, today: string): Slot[] {
  const t0 = performance.now();
  const overTime = () => { if (performance.now() - t0 > MAX_MS) throw new Error('too large'); };
  // Not an iCalendar file (an HTML page, a typo'd link): say so, not « unreachable ».
  let parsed: ReturnType<typeof ICAL.parse>;
  try { parsed = ICAL.parse(ics); } catch { throw new Error('invalid'); }
  const comp = new ICAL.Component(parsed);
  // The timezone registry is global to the worker: start clean, and never let
  // a feed redefine UTC (one pro's file must not shift another's hours).
  ICAL.TimezoneService.reset();
  const zones = comp.getAllSubcomponents('vtimezone');
  if (zones.length > MAX_ZONES) throw new Error('too large');
  for (const tz of zones) {
    // Removed from the file too: ical.js would otherwise find it there.
    if (!zoneOk(tz)) { comp.removeSubcomponent(tz); continue; }
    const id = String(tz.getFirstPropertyValue('tzid') ?? '').toUpperCase();
    if (id && !['UTC', 'Z', 'GMT', 'ETC/UTC'].includes(id)) ICAL.TimezoneService.register(tz);
  }
  const last = addDays(today, HORIZON_DAYS);
  const windowStart = parisToUtc(today, 0);
  const windowEnd = parisToUtc(last, 23);
  const out = new Set<string>();
  let steps = 0;
  let skipped = 0;
  const step = () => {
    if (++steps > MAX_STEPS) throw new Error('too large');
    if ((steps & 255) === 0) overTime();
  };

  // Days walked only inside [today, last]: an event spanning a century costs
  // the window, not 36 000 iterations.
  const add = (start: IcalTime, end: IcalTime | null) => {
    if (start.isDate) {
      // All-day: [start, end) days, both half-days.
      const first = start.toString().slice(0, 10);
      const stop = end ? end.toString().slice(0, 10) : addDays(first, 1);
      for (let d = first > today ? first : today; d < stop && d <= last; d = addDays(d, 1)) {
        step();
        out.add(`${d}|am`); out.add(`${d}|pm`);
      }
      return;
    }
    const s = start.toJSDate();
    const e = end ? end.toJSDate() : new Date(s.getTime() + 60 * 60 * 1000);
    if (e <= windowStart || s >= windowEnd || e <= s) return;
    const sDay = parisDay(s);
    const eDay = parisDay(e);
    for (let d = sDay > today ? sDay : today; d <= eDay && d <= last; d = addDays(d, 1)) {
      step();
      for (const period of ['am', 'pm'] as const) {
        const [h0, h1] = HALF_DAYS[period];
        if (s < parisToUtc(d, h1) && e > parisToUtc(d, h0)) out.add(`${d}|${period}`);
      }
    }
  };

  const skip = (c: IcalComponent) =>
    String(c.getFirstPropertyValue('transp') ?? '').toUpperCase() === 'TRANSPARENT'
    || String(c.getFirstPropertyValue('status') ?? '').toUpperCase() === 'CANCELLED'
    || String(c.getFirstPropertyValue('uid') ?? '').endsWith('@askandgo.io');

  const vevents = comp.getAllSubcomponents('vevent');
  if (vevents.length > MAX_EVENTS) throw new Error('too large');
  const exceptions = new Map<string, IcalComponent[]>();
  const masters: IcalComponent[] = [];
  for (const v of vevents) {
    if (v.hasProperty('recurrence-id')) {
      const uid = String(v.getFirstPropertyValue('uid') ?? '');
      exceptions.set(uid, [...(exceptions.get(uid) ?? []), v]);
    } else masters.push(v);
  }
  const masterUids = new Set(masters.map((m) => String(m.getFirstPropertyValue('uid') ?? '')));
  // Orphan exceptions (no master in the feed) count as single events.
  for (const [uid, list] of exceptions) if (!masterUids.has(uid)) masters.push(...list);

  for (const m of masters) {
    overTime();
    if (skip(m)) continue;
    const ev = new ICAL.Event(m);
    // An event repeating every second or minute is no agenda: refused before
    // iterating (the budgets above would stop it, after burning them).
    for (const rule of m.getAllProperties('rrule')) {
      const freq = String((rule.getFirstValue() as { freq?: string } | null)?.freq ?? '').toUpperCase();
      if (freq === 'SECONDLY' || freq === 'MINUTELY') throw new Error('too large');
    }
    if (ev.isRecurring() && !m.hasProperty('recurrence-id')) {
      for (const x of exceptions.get(ev.uid) ?? []) ev.relateException(x);
      const it = ev.iterator();
      // Occurrences long before the window are skipped cheaply and do not
      // count toward the cap: a daily event started in 2015 still marks
      // today's half-days.
      const durMs = ev.duration ? ev.duration.toSeconds() * 1000 : 0;
      const skipBefore = windowStart.getTime() - durMs - 2 * 86_400_000;  // margin for moved exceptions
      let n = 0;
      for (let next = it.next(); next && n < MAX_OCCURRENCES; next = it.next()) {
        const at = next.toJSDate();
        if (at.getTime() < skipBefore) {
          if (++skipped > MAX_SKIPPED) throw new Error('too large');
          if ((skipped & 1023) === 0) overTime();
          continue;
        }
        step();
        if (at > windowEnd) break;
        const det = ev.getOccurrenceDetails(next);
        if (det.endDate.toJSDate() <= windowStart) continue;
        n++;
        if (det.item.component !== m && skip(det.item.component)) continue;
        add(det.startDate, det.endDate);
      }
    } else {
      add(ev.startDate, ev.endDate);
    }
  }
  return [...out].map((k) => { const [day, period] = k.split('|'); return { day, period: period as 'am' | 'pm' }; });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const provided = req.headers.get('x-junto-push-secret') ?? '';
  if (!SECRET || !constantTimeEqual(provided, SECRET)) return new Response('Forbidden', { status: 403 });

  // One pro per call (00578); its address is read here, never from the body.
  const body = await req.json().catch(() => ({})) as { pro_id?: unknown };
  const proId = typeof body.pro_id === 'string' ? body.pro_id : null;
  if (!proId) return new Response('Bad request', { status: 400 });

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: targets, error } = await supabase.rpc('calendar_import_targets');
  if (error) return new Response('Unavailable', { status: 503 });

  const today = parisDay(new Date());
  let ok = 0;
  let failed = 0;
  for (const t of ((targets ?? []) as { pro_id: string; import_url: string }[]).filter((x) => x.pro_id === proId)) {
    try {
      const slots = busySlots(await fetchCalendar(t.import_url), today);
      // The address read goes back with the result: if the pro changed it
      // meanwhile, the stale result is ignored.
      const { error: e } = await supabase.rpc('calendar_import_apply', { p_pro: t.pro_id, p_slots: slots, p_error: null, p_url: t.import_url });
      if (e) throw new Error('apply');
      ok++;
    } catch (e) {
      failed++;
      // Short, user-facing reason; never the URL itself.
      const msg = e instanceof Error ? e.message : 'error';
      const reason = msg.startsWith('http 404') || msg.startsWith('http 403') || msg.startsWith('http 401')
        ? 'link_invalid'
        : msg === 'too large' ? 'too_large' : msg === 'invalid' ? 'invalid_file'
        : msg === 'apply' ? 'internal' : 'unreachable';
      await supabase.rpc('calendar_import_apply', { p_pro: t.pro_id, p_slots: null, p_error: reason, p_url: t.import_url });
    }
  }
  console.log(`calendar-import: ${ok} ok, ${failed} failed`);
  return new Response(JSON.stringify({ ok, failed }), { headers: { 'Content-Type': 'application/json' } });
});
