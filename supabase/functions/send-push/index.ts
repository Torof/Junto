// Edge function: send push notification via Expo Push API
// Called by DB trigger on notifications INSERT.
// Deployment: supabase functions deploy send-push --no-verify-jwt

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

interface Payload {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const { user_id, title, body, data }: Payload = await req.json();
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
