import { supabase } from './supabase';

export interface TransportSummary {
  transport_type: string;
  count: number;
  total_seats: number;
  cities: string[] | null;
}

export interface ParticipantTransport {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  transport_type: string | null;
  transport_seats: number | null;
  transport_from_name: string | null;
}

export const transportService = {
  setTransport: async (
    activityId: string,
    transportType: string,
    seats?: number | null,
    fromName?: string | null,
  ): Promise<void> => {
    const { error } = await supabase.rpc('set_participation_transport' as 'join_activity', {
      p_activity_id: activityId,
      p_transport_type: transportType,
      p_transport_seats: seats ?? null,
      p_transport_from_name: fromName ?? null,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getSummary: async (activityId: string): Promise<TransportSummary[]> => {
    const { data, error } = await supabase.rpc('get_transport_summary' as 'join_activity', {
      p_activity_id: activityId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as TransportSummary[]) ?? [];
  },

  getForActivity: async (activityId: string): Promise<ParticipantTransport[]> => {
    const { data, error } = await supabase
      .from('public_participants' as 'participations')
      .select('user_id, display_name, avatar_url, transport_type, transport_seats, transport_from_name')
      .eq('activity_id', activityId)
      .not('transport_type' as 'user_id', 'is', null)
      .order('transport_type' as 'created_at');
    if (error) return [];
    return (data ?? []) as unknown as ParticipantTransport[];
  },
};
