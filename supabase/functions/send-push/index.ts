// Edge function: send push notification via Expo Push API
// Called by DB trigger on notifications INSERT (and direct calls from server-side functions).
// Deployment: supabase functions deploy send-push --no-verify-jwt
//
// Auth: a shared secret (`PUSH_WEBHOOK_SECRET`) must be passed in the
// `x-junto-push-secret` header. The DB trigger reads the same secret
// from a Postgres setting. Without this header the request is rejected.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface Payload {
  user_id: string;
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
  const { user_id, title, body, data, collapseId } = payload;
  if (!user_id || !title) {
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
    .select('token')
    .eq('user_id', user_id);

  let tokens = (tokenRows ?? []).map((r) => r.token).filter(Boolean);

  if (tokens.length === 0 && !error) {
    const { data: legacy } = await supabase
      .from('users')
      .select('push_token')
      .eq('id', user_id)
      .single();
    if (legacy?.push_token) tokens = [legacy.push_token];
  }

  if (tokens.length === 0) {
    return new Response('No token', { status: 204 });
  }

  // Expo Push API accepts an array of messages in a single request (up to 100).
  const messages = tokens.map((to) => {
    const msg: Record<string, unknown> = {
      to,
      title,
      body,
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

  const expoRes = await fetch('https://exp.host/--/api/v2/push/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(messages),
  });

  const expoBody = await expoRes.text();

  // Best-effort token cleanup. Expo returns one ticket per submitted message,
  // in the same order. Tickets with status=error and a permanent-dead error
  // code mean the token will never deliver again — drop the row so we stop
  // burning fan-out time and potentially hitting rate limits on bad tokens.
  if (expoRes.ok) {
    try {
      const parsed = JSON.parse(expoBody);
      const tickets: ExpoTicket[] = Array.isArray(parsed?.data) ? parsed.data : [];
      const deadTokens: string[] = [];
      tickets.forEach((ticket, i) => {
        if (
          ticket?.status === 'error' &&
          ticket.details?.error &&
          DEAD_TOKEN_ERRORS.has(ticket.details.error) &&
          tokens[i]
        ) {
          deadTokens.push(tokens[i]!);
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
      // Same — don't dump the raw Expo parse error. The shape of the
      // response is documented; if it changes we'll catch it via tests,
      // not via log spelunking.
      console.warn('[send-push] expo response parse failed');
    }
  }

  // Pass Expo's body through so per-message statuses are visible in
  // net._http_response.content (DeviceNotRegistered, MismatchSenderId, etc).
  return new Response(expoBody, {
    status: expoRes.ok ? 200 : 502,
    headers: { 'Content-Type': 'application/json' },
  });
});
