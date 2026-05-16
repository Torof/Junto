// Edge function: delete the caller's account.
//
// Steps, in order:
//   1. Verify the caller's JWT (anon-key client + getUser). Refuse if
//      unauthenticated or expired.
//   2. Call the SECURITY DEFINER RPC `delete_own_account` with the
//      caller's JWT — it cascades through public-schema tables
//      (activities, participations, wall_messages, etc.) per
//      docs/SECURITY.md "Stratégie de suppression par table".
//   3. With the service_role, delete the corresponding auth.users row.
//      Without this step, the auth row stays live with a working JWT
//      pointing at a now-missing public.users row — see AUDIT.md C1.
//
// Deployment: `supabase functions deploy delete-account` (default JWT
// verification ON — Supabase will reject unauthenticated callers
// before this code runs, but we double-check inside for clarity).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 });
  }

  // Validate the JWT — we need the user_id to delete the auth row,
  // and we want the RPC to run as the caller (not as service_role)
  // so suspended / RLS gates still apply at the public-schema level.
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return new Response('Unauthorized', { status: 401 });
  }
  const userId = userData.user.id;

  // Step 1: cascade public-schema deletion via the existing RPC. The
  // RPC also cancels active activities the user created and notifies
  // their participants.
  const { error: rpcErr } = await userClient.rpc('delete_own_account');
  if (rpcErr) {
    return new Response(
      JSON.stringify({ stage: 'rpc', error: rpcErr.message }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  // Step 2: delete auth.users with service_role. Anything that goes
  // wrong here leaves the public-schema deletion intact (irreversible),
  // so we report it explicitly — operator must clean up by hand.
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { error: deleteErr } = await adminClient.auth.admin.deleteUser(userId);
  if (deleteErr) {
    return new Response(
      JSON.stringify({ stage: 'auth-delete', user_id: userId, error: deleteErr.message }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
});
