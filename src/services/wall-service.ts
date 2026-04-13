import { supabase } from './supabase';

export interface WallMessage {
  id: string;
  activity_id: string;
  user_id: string | null;
  content: string;
  edited_at: string | null;
  deleted_at: string | null;
  created_at: string;
}

export interface WallMessageWithProfile extends WallMessage {
  display_name: string | null;
  avatar_url: string | null;
}

export const wallService = {
  getMessages: async (activityId: string): Promise<WallMessageWithProfile[]> => {
    const { data: messages, error } = await supabase
      .from('wall_messages')
      .select('id, activity_id, user_id, content, edited_at, deleted_at, created_at')
      .eq('activity_id', activityId)
      .is('deleted_at', null)
      .order('created_at', { ascending: true });
    if (error) throw error;

    // Resolve display names from public_profiles
    const userIds = [...new Set((messages ?? []).map((m) => m.user_id).filter(Boolean))] as string[];
    let profileMap: Record<string, string> = {};

    if (userIds.length > 0) {
      const { data: profiles } = await supabase
        .from('public_profiles')
        .select('id, display_name, avatar_url')
        .in('id', userIds);
      profileMap = Object.fromEntries((profiles ?? []).map((p) => [p.id, { display_name: p.display_name, avatar_url: p.avatar_url }]));
    }

    return (messages ?? []).map((m) => {
      const profile = m.user_id ? (profileMap[m.user_id] as { display_name: string; avatar_url: string | null } | undefined) : undefined;
      return {
        ...m,
        display_name: profile?.display_name ?? null,
        avatar_url: profile?.avatar_url ?? null,
      };
    });
  },

  send: async (activityId: string, content: string): Promise<string> => {
    const { data, error } = await supabase.rpc('send_wall_message' as 'join_activity', {
      p_activity_id: activityId,
      p_content: content,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },
};
