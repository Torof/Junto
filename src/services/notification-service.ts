import { supabase } from './supabase';

export interface Notification {
  id: string;
  user_id: string;
  type: string;
  title: string;
  body: string;
  data: { activity_id?: string; conversation_id?: string; changes?: Record<string, boolean> } | null;
  read_at: string | null;
  created_at: string;
}

export const notificationService = {
  getAll: async (): Promise<Notification[]> => {
    const { data, error } = await supabase
      .from('notifications')
      .select('id, user_id, type, title, body, data, read_at, created_at')
      .order('created_at', { ascending: false })
      .limit(50);
    if (error) throw error;
    return (data ?? []) as Notification[];
  },

  getUnreadCount: async (): Promise<number> => {
    const { count, error } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .is('read_at', null);
    if (error) throw error;
    return count ?? 0;
  },

  markAsRead: async (notificationId: string): Promise<void> => {
    const { error } = await supabase
      .from('notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('id', notificationId);
    if (error) throw error;
  },

  markAllAsRead: async (): Promise<void> => {
    const { error } = await supabase
      .from('notifications')
      .update({ read_at: new Date().toISOString() })
      .is('read_at', null);
    if (error) throw error;
  },
};
