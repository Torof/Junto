import { useCallback, useEffect, useState } from 'react';
import { type Session } from '@supabase/supabase-js';
import { useQueryClient } from '@tanstack/react-query';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';
import { useAuthStore } from '@/store/auth-store';
import { setSentryUser } from '@/lib/sentry';

interface AuthState {
  session: Session | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  needsOnboarding: boolean;
  isSuspended: boolean;
  refreshUser: () => Promise<void>;
}

export function useAuth(): AuthState {
  const queryClient = useQueryClient();
  const [session, setSession] = useState<Session | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [isSuspended, setIsSuspended] = useState(false);

  const checkUserStatus = useCallback(async (userId: string) => {
    // Self-heal: ensure public.users row exists (guards against trigger failures)
    await supabase.rpc('ensure_user_row' as 'accept_tos');

    const { data } = await supabase
      .from('users')
      .select('age_confirmed_at, accepted_tos_at, suspended_at')
      .eq('id', userId)
      .single();

    setNeedsOnboarding(!data?.age_confirmed_at || !data?.accepted_tos_at);
    setIsSuspended(!!data?.suspended_at);
  }, []);

  const refreshUser = useCallback(async () => {
    const s = await authService.getSession();
    if (s) await checkUserStatus(s.user.id);
  }, [checkUserStatus]);

  const refreshTick = useAuthStore((s) => s.refreshTick);

  useEffect(() => {
    // Safety timeout — if something hangs (slow network, failed RPC), unblock
    // the app after 8s so it doesn't stay on the loading screen forever.
    const timeout = setTimeout(() => setIsLoading(false), 8000);

    (async () => {
      try {
        const s = await authService.getSession();
        setSession(s);
        if (s) {
          setSentryUser(s.user.id);
          // Block initial render on the status check so AuthGate never
          // routes the user into an authenticated screen before we know
          // whether they're suspended or unfinished. AUDIT_SECURITY_2 M3.
          // Errors are swallowed — the 8s safety timeout above unblocks
          // the app if the RPC hangs.
          await checkUserStatus(s.user.id).catch(() => {});
        }
      } catch {
        // Swallow — render the visitor screen
      } finally {
        clearTimeout(timeout);
        setIsLoading(false);
      }
    })();

    const { data: { subscription } } = authService.onAuthStateChange(async (event, s) => {
      // A real logout is ONLY the explicit SIGNED_OUT event (user tapped
      // sign-out, refresh token revoked, account deleted). A null session from
      // any OTHER event — most importantly a token refresh that failed because
      // the device is offline — is transient and must NOT log the user out:
      // the refresh token is still valid, we just can't reach the server.
      //
      // The server (RLS + SECURITY DEFINER functions) gates every operation
      // regardless of client state, so keeping a stale session through a
      // connectivity blip is safe and keeps the UI usable offline — essential
      // for outdoor use (mountains, canyons) where signal drops constantly.
      if (event === 'SIGNED_OUT') {
        // Wipe the query cache so the next user on this device never sees the
        // previous user's cached data. AUDIT_SECURITY_2 C1. (Sign-out always
        // precedes a different-user sign-in, so this is the only place the
        // cross-user wipe is needed.)
        queryClient.clear();
        setNeedsOnboarding(false);
        setIsSuspended(false);
        setSession(null);
        setSentryUser(null);
        return;
      }

      // Account data may have changed — refresh the cache but keep the session.
      if (event === 'USER_UPDATED') {
        queryClient.clear();
      }

      if (s) {
        // Propagate the session synchronously so AuthGate re-renders + routes
        // immediately. Status check runs in the background and may flip
        // needsOnboarding/isSuspended, triggering another route evaluation.
        setSession(s);
        setSentryUser(s.user.id);
        checkUserStatus(s.user.id).catch(() => {});
      }
      // else: transient null session (e.g. offline refresh failure) — keep the
      // current session and do nothing. Supabase retries the refresh on
      // reconnect, which will deliver a fresh session.
    });

    return () => {
      clearTimeout(timeout);
      subscription.unsubscribe();
    };
  }, [checkUserStatus, queryClient]);

  useEffect(() => {
    if (refreshTick === 0) return;
    authService.getSession().then(async (s) => {
      if (s) await checkUserStatus(s.user.id);
    });
  }, [refreshTick, checkUserStatus]);

  return {
    session,
    isLoading,
    isAuthenticated: !!session,
    needsOnboarding,
    isSuspended,
    refreshUser,
  };
}
