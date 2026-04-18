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

  requestSeat: async (activityId: string, driverId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('request_seat' as 'join_activity', {
      p_activity_id: activityId,
      p_driver_id: driverId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  acceptSeatRequest: async (requestId: string): Promise<void> => {
    const { error } = await supabase.rpc('accept_seat_request' as 'join_activity', {
      p_request_id: requestId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  declineSeatRequest: async (requestId: string): Promise<void> => {
    const { error } = await supabase.rpc('decline_seat_request' as 'join_activity', {
      p_request_id: requestId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getPendingSeatRequests: async (activityId: string): Promise<{ id: string; requester_id: string; driver_id: string; status: string }[]> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return [];
    const { data, error } = await supabase
      .from('seat_requests' as 'participations')
      .select('id, requester_id, driver_id, status')
      .eq('activity_id', activityId)
      .eq('status' as 'user_id', 'pending') as unknown as { data: { id: string; requester_id: string; driver_id: string; status: string }[] | null; error: Error | null };
    if (error) return [];
    return data ?? [];
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
