import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/services/supabase';
import { useAuth } from './use-auth';

// Current user's admin flag. Client-side gate only — every admin action is
// independently re-checked server-side (the RPCs verify is_admin). This just
// hides/guards the admin screens.
export function useIsAdmin() {
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;
  const { data, isLoading } = useQuery({
    queryKey: ['is-admin', userId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('users')
        .select('is_admin')
        .eq('id', userId as string)
        .single();
      if (error) throw error;
      return (data as { is_admin: boolean } | null)?.is_admin ?? false;
    },
    enabled: !!userId,
  });
  return { isAdmin: data ?? false, isLoading: isLoading || !userId };
}
