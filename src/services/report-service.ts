import { supabase } from './supabase';

export interface Report {
  id: string;
  reporter_id: string;
  target_type: 'user' | 'activity' | 'wall_message' | 'private_message';
  target_id: string;
  reason: string;
  status: 'pending' | 'dismissed' | 'actioned';
  admin_note: string | null;
  created_at: string;
  resolved_at: string | null;
}

export const reportService = {
  create: async (targetType: string, targetId: string, reason: string): Promise<string> => {
    const { data, error } = await supabase.rpc('create_report' as 'join_activity', {
      p_target_type: targetType,
      p_target_id: targetId,
      p_reason: reason,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  getAll: async (): Promise<Report[]> => {
    const { data, error } = await supabase
      .from('reports' as 'users')
      .select('id, reporter_id, target_type, target_id, reason, status, admin_note, created_at, resolved_at')
      .order('created_at', { ascending: false }) as unknown as { data: Report[] | null; error: Error | null };
    if (error) throw error;
    return data ?? [];
  },

  moderate: async (reportId: string, action: 'dismissed' | 'actioned', adminNote?: string, suspendUserId?: string): Promise<void> => {
    const { error } = await supabase.rpc('moderate_report' as 'join_activity', {
      p_report_id: reportId,
      p_action: action,
      p_admin_note: adminNote ?? null,
      p_suspend_user_id: suspendUserId ?? null,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
