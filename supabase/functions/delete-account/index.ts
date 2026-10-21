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

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Step 1: cascade public-schema deletion. Since mig 00519 the deletion RPC
  // is not callable by app accounts: the service role runs it for the user
  // whose JWT was just verified (delete_account_as), so a deletion always
  // goes through here — auth row and files included.
  const { error: rpcErr } = await adminClient.rpc('delete_account_as', { p_user_id: userId });
  if (rpcErr) {
    console.warn(`[delete-account] rpc failed for user ${userId}: ${rpcErr.message}`);
    return new Response(
      JSON.stringify({ stage: 'rpc', error: 'Operation not permitted' }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  // Step 2: purge the user's storage objects (RGPD Art. 17 — prod
  // audit B2, 2026-06-11: avatars and pro photos survived account
  // deletion). Both buckets prefix paths with the user id. Best-effort:
  // a storage failure must not strand the user in a half-deleted state
  // where public-schema data is gone but the auth row survives, so we
  // log and continue rather than abort.
  // channel-photos added in the re-secure pass (audit ID-7): the user's
  // discussions are closed by delete_own_account, their photos go too.
  for (const bucket of ['avatars', 'pro-photos', 'channel-photos']) {
    try {
      const paths: string[] = [];
      // list() is per-folder; walk the user's folder tree (depth is
      // bounded: avatars/<uid>/file, pro-photos/<uid>/<surface>/<id>/gallery/file,
      // channel-photos/<uid>/channels/file).
      const walk = async (prefix: string) => {
        const { data: entries, error } = await adminClient.storage.from(bucket).list(prefix, { limit: 1000 });
        if (error || !entries) return;
        for (const entry of entries) {
          const full = prefix ? `${prefix}/${entry.name}` : entry.name;
          // Files carry an id; folders come back with id null.
          if (entry.id) paths.push(full);
          else await walk(full);
        }
      };
      await walk(userId);
      if (paths.length > 0) {
        const { error: rmErr } = await adminClient.storage.from(bucket).remove(paths);
        if (rmErr) console.warn(`[delete-account] storage purge failed for ${bucket} (${paths.length} objects), user ${userId}`);
      }
    } catch (_e) {
      console.warn(`[delete-account] storage walk threw for ${bucket}, user ${userId}`);
    }
  }

  // Step 3: delete auth.users with service_role. Anything that goes
  // wrong here leaves the public-schema deletion intact (irreversible),
  // so we report it explicitly — operator must clean up by hand.
  const { error: deleteErr } = await adminClient.auth.admin.deleteUser(userId);
  if (deleteErr) {
    // Don't echo user_id back — caller knows their own ID, and reflecting
    // it in an error response is a habit worth avoiding. Operator log
    // below carries it for debugging.
    console.warn(`[delete-account] auth-delete failed for user ${userId}`);
    return new Response(
      JSON.stringify({ stage: 'auth-delete', error: 'Operation not permitted' }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
});
