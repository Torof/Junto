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

const SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET');

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Reject if the shared secret is missing or wrong (constant-time-ish compare).
  const provided = req.headers.get('x-junto-push-secret') ?? '';
  if (!SECRET || provided.length !== SECRET.length || provided !== SECRET) {
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

  // Pass Expo's body through so per-message statuses are visible in
  // net._http_response.content (DeviceNotRegistered, MismatchSenderId, etc).
  const expoBody = await expoRes.text();
  return new Response(expoBody, {
    status: expoRes.ok ? 200 : 502,
    headers: { 'Content-Type': 'application/json' },
  });
});
