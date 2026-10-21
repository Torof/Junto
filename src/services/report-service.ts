import { supabase } from './supabase';

export interface Report {
  id: string;
  reporter_id: string;
  target_type: 'user' | 'activity' | 'pro_review' | 'offering_review' | 'message' | 'group' | 'channel';
  target_id: string;
  reason: string;
  status: 'pending' | 'dismissed' | 'actioned';
  admin_note: string | null;
  created_at: string;
  resolved_at: string | null;
}

export const reportService = {
  create: async (targetType: string, targetId: string, reason: string): Promise<string> => {
    const { data, error } = await supabase.rpc('create_report', {
      p_target_type: targetType,
      p_target_id: targetId,
      p_reason: reason,
    });
    if (error) throw error;
    return data;
  },

  getAll: async (): Promise<Report[]> => {
    const { data, error } = await supabase
      .from('reports')
      .select('id, reporter_id, target_type, target_id, reason, status, admin_note, created_at, resolved_at')
      .order('created_at', { ascending: false });
    if (error) throw error;
    return (data ?? []) as Report[];
  },

  moderate: async (reportId: string, action: 'dismissed' | 'actioned', adminNote?: string, suspendUserId?: string): Promise<void> => {
    const { error } = await supabase.rpc('moderate_report', {
      p_report_id: reportId,
      p_action: action,
      p_admin_note: (adminNote ?? null) as string,
      p_suspend_user_id: (suspendUserId ?? null) as string,
    });
    if (error) throw error;
  },
};
