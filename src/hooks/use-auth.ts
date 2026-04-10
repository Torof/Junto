import { useEffect, useState } from 'react';
import { type Session } from '@supabase/supabase-js';
import { authService } from '@/services/auth-service';

export function useAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    authService.getSession().then((s) => {
      setSession(s);
      setIsLoading(false);
    });

    const { data: { subscription } } = authService.onAuthStateChange(async (_event, s) => {
      setSession(s);
    });

    return () => subscription.unsubscribe();
  }, []);

  return { session, isLoading, isAuthenticated: !!session };
}
