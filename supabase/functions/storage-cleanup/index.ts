// Edge function: deletes community photo files no photo row points to any more
// (mig 00580, public.community_photo_orphans): removed by the contributor, the
// pro or an admin, abandoned drafts, refused additions. Since 00578 no client
// can delete a community file itself (no swapping), so this is the only way
// such a file leaves the public bucket. pg_cron (private.trigger_storage_cleanup)
// calls it every hour, only when there is something to delete.
// Deployment: supabase functions deploy storage-cleanup --no-verify-jwt
//
// Auth: shared secret header `x-junto-push-secret` (same as send-push).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET');

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const provided = req.headers.get('x-junto-push-secret') ?? '';
  if (!SECRET || !constantTimeEqual(provided, SECRET)) return new Response('Forbidden', { status: 403 });

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data, error } = await supabase.rpc('community_photo_orphans', { p_limit: 100 });
  if (error) return new Response('Unavailable', { status: 503 });
  const names = ((data ?? []) as string[]).filter((n) => typeof n === 'string' && n.split('/')[1] === 'community');
  if (names.length === 0) return new Response(JSON.stringify({ deleted: 0 }), { headers: { 'Content-Type': 'application/json' } });

  const { data: removed, error: rmError } = await supabase.storage.from('pro-photos').remove(names);
  if (rmError) return new Response('Unavailable', { status: 503 });
  return new Response(JSON.stringify({ deleted: removed?.length ?? 0 }), { headers: { 'Content-Type': 'application/json' } });
});
