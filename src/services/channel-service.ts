import { supabase } from './supabase';

export const CHANNEL_RADII = [20, 35, 50] as const;

export interface ChannelDraft {
  sportKey: string;
  name: string;
  baseLng: number;                 // zone centre (required)
  baseLat: number;
  baseLabel: string;
  radiusKm: number;                // 20 | 35 | 50 — the zone's territory
  description: string | null;
  force?: boolean;
}

export interface CreateChannelResult {
  conversationId: string;
  duplicate: boolean;
}

export interface ChannelListItem {
  conversation_id: string;
  name: string;
  sport_key: string;
  base_label: string;
  radius_km: number;
  description: string | null;
  distance_km: number | null;
  member_count: number;
  is_member: boolean;
  is_creator: boolean;
}

export interface ChannelDetail {
  conversation_id: string;
  name: string;
  sport_key: string;
  base_lng: number;
  base_lat: number;
  base_label: string;
  radius_km: number;
  description: string | null;
  member_count: number;
  is_member: boolean;
  is_creator: boolean;
  is_closed: boolean;
}

export interface ChannelMember {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  reliability_tier: string | null;
  is_creator: boolean;
  joined_at: string;
}

export interface SearchChannelsFilters {
  query?: string | null;
  sportKey?: string | null;
  nearLng?: number | null;
  nearLat?: number | null;
}

export const channelService = {
  create: async (d: ChannelDraft): Promise<CreateChannelResult> => {
    const { data, error } = await supabase.rpc('create_channel', {
      p_sport_key: d.sportKey,
      p_name: d.name,
      p_base_lng: d.baseLng,
      p_base_lat: d.baseLat,
      p_base_label: d.baseLabel,
      p_radius_km: d.radiusKm,
      p_description: d.description as unknown as string,
      p_force: d.force ?? false,
    });
    if (error) throw error;
    const row = (data ?? [])[0] as unknown as { conversation_id: string; duplicate: boolean } | undefined;
    if (!row) throw new Error('create_channel: empty result');
    return { conversationId: row.conversation_id, duplicate: row.duplicate };
  },

  join: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('join_channel', { p_conversation_id: conversationId });
    if (error) throw error;
  },

  leave: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('leave_channel', { p_conversation_id: conversationId });
    if (error) throw error;
  },

  search: async (f: SearchChannelsFilters): Promise<ChannelListItem[]> => {
    const { data, error } = await supabase.rpc('search_channels', {
      p_query: (f.query ?? null) as unknown as string,
      p_sport_key: (f.sportKey ?? null) as unknown as string,
      p_near_lng: (f.nearLng ?? null) as unknown as number,
      p_near_lat: (f.nearLat ?? null) as unknown as number,
    });
    if (error) throw error;
    return (data ?? []) as unknown as ChannelListItem[];
  },

  get: async (conversationId: string): Promise<ChannelDetail | null> => {
    const { data, error } = await supabase.rpc('get_channel', { p_conversation_id: conversationId });
    if (error) throw error;
    return ((data ?? [])[0] ?? null) as unknown as ChannelDetail | null;
  },

  members: async (conversationId: string): Promise<ChannelMember[]> => {
    const { data, error } = await supabase.rpc('get_channel_members', { p_conversation_id: conversationId });
    if (error) throw error;
    return (data ?? []) as unknown as ChannelMember[];
  },

  rename: async (conversationId: string, name: string): Promise<void> => {
    const { error } = await supabase.rpc('rename_channel', { p_conversation_id: conversationId, p_name: name });
    if (error) throw error;
  },

  removeMember: async (conversationId: string, userId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_channel_member', { p_conversation_id: conversationId, p_user_id: userId });
    if (error) throw error;
  },

  close: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('close_channel', { p_conversation_id: conversationId });
    if (error) throw error;
  },
};
