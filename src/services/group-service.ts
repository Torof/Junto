import { supabase } from './supabase';

export interface GroupMember {
  id: string;
  display_name: string;
  avatar_url: string | null;
}

export interface GroupInfo {
  name: string;
  icon: string | null;
  created_by: string | null;
  members: GroupMember[];
}

export const groupService = {
  // create_group (00356/00364): ≥2 retained eligible members (min 3 total),
  // name 1–60, icon ≤ 8, 5/day. Returns the new conversation id.
  create: async (name: string, icon: string | null, memberIds: string[]): Promise<string> => {
    const { data, error } = await supabase.rpc('create_group', {
      p_name: name,
      // p_icon is a required arg but the DB accepts NULL (CHECK only fires when
      // NOT NULL) — cast so "no icon" sends null.
      p_icon: icon as unknown as string,
      p_member_ids: memberIds,
    });
    if (error) throw error;
    return data as string;
  },

  addMember: async (conversationId: string, userId: string): Promise<void> => {
    const { error } = await supabase.rpc('add_group_member', {
      p_conversation_id: conversationId,
      p_user_id: userId,
    });
    if (error) throw error;
  },

  leave: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('leave_group', { p_conversation_id: conversationId });
    if (error) throw error;
  },

  rename: async (conversationId: string, name: string, icon: string | null): Promise<void> => {
    const { error } = await supabase.rpc('rename_group', {
      p_conversation_id: conversationId,
      p_name: name,
      p_icon: icon as unknown as string,
    });
    if (error) throw error;
  },

  // Member-gated read (00370): group meta + members. Rows repeat the meta; we
  // aggregate. Empty array = not a group / not a member (indistinguishable).
  getInfo: async (conversationId: string): Promise<GroupInfo | null> => {
    const { data, error } = await supabase.rpc('get_group_info', { p_conversation_id: conversationId });
    if (error) throw error;
    const rows = data ?? [];
    const first = rows[0];
    if (!first) return null;
    return {
      name: first.group_name,
      icon: first.group_icon,
      created_by: first.created_by,
      members: rows.map((r) => ({ id: r.member_id, display_name: r.member_name, avatar_url: r.member_avatar })),
    };
  },
};
