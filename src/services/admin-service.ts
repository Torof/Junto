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

  // Take down public/reviewable content (activity, wall_message, pro_review,
  // offering_review). Never DMs or users (server rejects those types).
  removeContent: async (targetType: string, targetId: string, reason: string): Promise<void> => {
    const { error } = await supabase.rpc('admin_remove_content' as 'join_activity', {
      p_target_type: targetType,
      p_target_id: targetId,
      p_reason: reason,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  // Demo mode (admin-only). demo_content_visible() returns, for an admin, the
  // current flag state (flag ON && caller is admin) — reused as the read.
  getDemoMode: async (): Promise<boolean> => {
    const { data, error } = await supabase.rpc('demo_content_visible' as 'join_activity',
      {} as unknown as { p_activity_id: string });
    if (error) throw error;
    return (data as unknown) === true;
  },

  setDemoMode: async (on: boolean): Promise<void> => {
    const { error } = await supabase.rpc('admin_set_demo_mode' as 'join_activity', {
      p_on: on,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
