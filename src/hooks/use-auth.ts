import { useEffect, useState } from 'react';
import { type Session } from '@supabase/supabase-js';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';

interface AuthState {
  session: Session | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  needsOnboarding: boolean;
  isSuspended: boolean;
}

export function useAuth(): AuthState {
  const [session, setSession] = useState<Session | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);
  const [isSuspended, setIsSuspended] = useState(false);

  useEffect(() => {
    authService.getSession().then(async (s) => {
      setSession(s);
      if (s) {
        await checkUserStatus(s.user.id);
      }
      setIsLoading(false);
    });

    const { data: { subscription } } = authService.onAuthStateChange(async (_event, s) => {
      if (s) {
        await checkUserStatus(s.user.id);
        setSession(s);
      } else {
        setNeedsOnboarding(false);
        setIsSuspended(false);
        setSession(null);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  async function checkUserStatus(userId: string) {
    const { data } = await supabase
      .from('users')
      .select('date_of_birth, accepted_tos_at, suspended_at')
      .eq('id', userId)
      .single();

    setNeedsOnboarding(!data?.date_of_birth || !data?.accepted_tos_at);
    setIsSuspended(!!data?.suspended_at);
  }

  return {
    session,
    isLoading,
    isAuthenticated: !!session,
    needsOnboarding,
    isSuspended,
  };
}
