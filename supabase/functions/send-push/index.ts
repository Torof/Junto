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
  const { user_id, title, body, data } = payload;
  if (!user_id || !title || !body) {
    return new Response('Missing fields', { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: user, error } = await supabase
    .from('users')
    .select('push_token')
    .eq('id', user_id)
    .single();

  if (error || !user?.push_token) {
    return new Response('No token', { status: 204 });
  }

  const expoRes = await fetch('https://exp.host/--/api/v2/push/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      to: user.push_token,
      title,
      body,
      data: data ?? {},
      sound: 'default',
      priority: 'high',
    }),
  });

  if (!expoRes.ok) {
    const text = await expoRes.text();
    return new Response(`Expo error: ${text}`, { status: 502 });
  }

  return new Response('ok', { status: 200 });
});
