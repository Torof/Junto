// Edge function: the pro's private iCal feed (mig 00568). Google / Apple /
// Outlook subscribe to  …/functions/v1/calendar-feed?token=<64 hex>  and get
// the pro's confirmed bookings and pending requests (-1 month → +6 months).
// Deployment: supabase functions deploy calendar-feed --no-verify-jwt
//
// Auth: the token IS the secret (256 bits, regenerable from the app). It is
// checked in the DB (calendar_feed_bookings, service_role only), which also
// requires an approved, non-suspended pro. Unknown token → 404, no detail.
// Event UIDs end with @askandgo.io: the calendar import skips them, so a pro
// who imports the calendar holding this feed never blocks their own bookings.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { HALF_DAYS, parisToUtc } from '../_shared/paris-time.ts';

type Row = {
  id: string; day: string; period: 'am' | 'pm'; status: string; offering_title: string | null;
  party_size: number; client_name: string | null; is_manual: boolean; hide_names: boolean;
  // 00575: one row per fixed date (whole span, places taken / max).
  kind: 'booking' | 'session'; end_day: string; end_period: 'am' | 'pm'; max_participants: number | null;
};

const stamp = (d: Date) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

// RFC 5545 text escaping + control characters out.
const text = (v: string) =>
  v.replace(/[\u0000-\u001f]/g, ' ').replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,');

// Fold lines at 74 chars (continuation lines start with a space).
function fold(line: string): string {
  const out: string[] = [];
  let rest = line;
  while (rest.length > 74) { out.push(rest.slice(0, 74)); rest = ' ' + rest.slice(74); }
  out.push(rest);
  return out.join('\r\n');
}

Deno.serve(async (req) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return new Response('Method not allowed', { status: 405 });
  const token = new URL(req.url).searchParams.get('token') ?? '';
  if (!/^[0-9a-f]{64}$/.test(token)) return new Response('Not found', { status: 404 });

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  // Unknown / regenerated token → 404: the subscribed calendar shows the link
  // is dead instead of silently going empty.
  const { data: valid, error: vErr } = await supabase.rpc('calendar_feed_valid', { p_token: token });
  if (vErr) return new Response('Unavailable', { status: 503 });
  if (!valid) return new Response('Not found', { status: 404 });
  const { data, error } = await supabase.rpc('calendar_feed_bookings', { p_token: token });
  if (error) return new Response('Unavailable', { status: 503 });
  const rows = (data ?? []) as Row[];

  const now = stamp(new Date());
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//askandgo//agenda pro//FR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:askandgo — réservations',
    'X-PUBLISHED-TTL:PT1H',
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
  ];
  for (const r of rows) {
    const [h0] = HALF_DAYS[r.period];
    const [, h1] = HALF_DAYS[r.end_period ?? r.period];
    const end = r.end_day ?? r.day;
    if (r.kind === 'session') {
      const summary = `${r.offering_title ?? 'Sortie'} · date fixe · ${r.party_size}/${r.max_participants ?? '?'} inscrits`;
      lines.push(
        'BEGIN:VEVENT',
        `UID:session-${r.id}@askandgo.io`,
        `DTSTAMP:${now}`,
        `DTSTART:${stamp(parisToUtc(r.day, h0))}`,
        `DTEND:${stamp(parisToUtc(end, h1))}`,
        fold(`SUMMARY:${text(summary)}`),
        fold(`DESCRIPTION:${text('Date fixe publiée dans askandgo.')}`),
        'STATUS:CONFIRMED',
        'TRANSP:OPAQUE',
        'END:VEVENT',
      );
      continue;
    }
    const who = r.hide_names
      ? 'Réservation'
      : (r.client_name ?? 'Client') + (r.is_manual ? ' (manuelle)' : '');
    const pending = r.status === 'pending';
    const summary = `${pending ? '(demande) ' : ''}${r.offering_title ?? 'Sortie'} · ${who} · ${r.party_size} pers.`;
    lines.push(
      'BEGIN:VEVENT',
      `UID:booking-${r.id}@askandgo.io`,
      `DTSTAMP:${now}`,
      `DTSTART:${stamp(parisToUtc(r.day, h0))}`,
      `DTEND:${stamp(parisToUtc(end, h1))}`,
      fold(`SUMMARY:${text(summary)}`),
      fold(`DESCRIPTION:${text(pending ? 'Demande en attente — à accepter dans askandgo.' : 'Réservation confirmée dans askandgo.')}`),
      `STATUS:${pending ? 'TENTATIVE' : 'CONFIRMED'}`,
      'TRANSP:OPAQUE',
      'END:VEVENT',
    );
  }
  lines.push('END:VCALENDAR');

  return new Response(lines.join('\r\n') + '\r\n', {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'inline; filename="askandgo.ics"',
      'Cache-Control': 'private, max-age=300',
    },
  });
});
