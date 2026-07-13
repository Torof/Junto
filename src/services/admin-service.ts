import { supabase } from './supabase';

// Admin identity/ownership lookups + suspension, backed by the SECURITY DEFINER
// functions in migration 00321 (every call is admin-gated and audited server-side).

export interface AdminUserInfo {
  id: string;
  display_name: string;
  email: string;
  tier: string;
  is_admin: boolean;
  suspended_at: string | null;
  created_at: string;
}

export interface AdminProOwner {
  pro_id: string;
  pro_name: string;
  status: string;
  owner_display_name: string;
  owner_email: string;
}

export const adminService = {
  resolveUser: async (userId: string): Promise<AdminUserInfo | null> => {
    const { data, error } = await supabase.rpc('admin_resolve_user' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    const rows = (data ?? []) as unknown as AdminUserInfo[];
    return rows[0] ?? null;
  },

  proOwner: async (proId: string): Promise<AdminProOwner | null> => {
    const { data, error } = await supabase.rpc('admin_pro_owner' as 'join_activity', {
      p_pro_id: proId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    const rows = (data ?? []) as unknown as AdminProOwner[];
    return rows[0] ?? null;
  },

  suspendUser: async (userId: string, reason: string): Promise<void> => {
    const { error } = await supabase.rpc('admin_suspend_user' as 'join_activity', {
      p_user_id: userId,
      p_reason: reason,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  unsuspendUser: async (userId: string, reason: string): Promise<void> => {
    const { error } = await supabase.rpc('admin_unsuspend_user' as 'join_activity', {
      p_user_id: userId,
      p_reason: reason,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
