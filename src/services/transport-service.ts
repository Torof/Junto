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
  transport_departs_at: string | null;
  confirmed_present?: boolean | null;
}

export interface SeatAssignment {
  id: string;
  driver_id: string;
  requester_id: string;
  display_name: string;
  avatar_url: string | null;
  pickup_from: string | null;
  requested_pickup_at: string | null;
}

export const transportService = {
  setTransport: async (
    activityId: string,
    transportType: string,
    seats?: number | null,
    fromName?: string | null,
    departsAt?: string | null,
  ): Promise<void> => {
    const { error } = await supabase.rpc('set_participation_transport', {
      p_activity_id: activityId,
      p_transport_type: transportType,
      p_transport_seats: seats ?? undefined,
      p_transport_from_name: fromName ?? undefined,
      p_transport_departs_at: departsAt ?? undefined,
    });
    if (error) throw error;
  },

  getSummary: async (activityId: string): Promise<TransportSummary[]> => {
    const { data, error } = await supabase.rpc('get_transport_summary', {
      p_activity_id: activityId,
    });
    if (error) return [];
    return (data ?? []) as TransportSummary[];
  },

  requestSeat: async (
    activityId: string,
    driverId: string,
    pickupFrom?: string,
    message?: string,
    requestedPickupAt?: string | null,
  ): Promise<string> => {
    const { data, error } = await supabase.rpc('request_seat', {
      p_activity_id: activityId,
      p_driver_id: driverId,
      p_pickup_from: pickupFrom ?? undefined,
      p_message: message ?? undefined,
      p_requested_pickup_at: requestedPickupAt ?? undefined,
    });
    if (error) throw error;
    return data;
  },

  acceptSeatRequest: async (requestId: string): Promise<void> => {
    const { error } = await supabase.rpc('accept_seat_request', { p_request_id: requestId });
    if (error) throw error;
  },

  declineSeatRequest: async (requestId: string): Promise<void> => {
    const { error } = await supabase.rpc('decline_seat_request', { p_request_id: requestId });
    if (error) throw error;
  },

  cancelAcceptedSeat: async (requestId: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_accepted_seat', { p_request_id: requestId });
    if (error) throw error;
  },

  // Cancels a still-pending request the user sent to a driver. Used by
  // MyOutingCard's pending-cancel flow so the user can back out before
  // changing transport mode. cancel_accepted_seat handles the already-
  // accepted case (which also restores seats); this one is the no-side-
  // effects status flip for pending.
  cancelPendingSeatRequest: async (requestId: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_pending_seat_request', { p_request_id: requestId });
    if (error) throw error;
  },

  // Clears the user's declared transport (type / seats / from / departs)
  // back to null, returning them to the empty / "À régler" state. The
  // RPC's generated type marks p_transport_type as required string,
  // but the SQL function (00200) accepts NULL — Postgres allows it
  // since the param has no DEFAULT NULL clause on the type column.
  // Cast scoped narrowly here rather than across every transport call.
  clearTransport: async (activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('set_participation_transport', {
      p_activity_id: activityId,
      p_transport_type: null as unknown as string,
    });
    if (error) throw error;
  },

  getPendingSeatRequests: async (activityId: string): Promise<{ id: string; requester_id: string; driver_id: string; status: string }[]> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return [];
    const { data, error } = await supabase
      .from('seat_requests')
      .select('id, requester_id, driver_id, status')
      .eq('activity_id', activityId)
      .eq('status', 'pending');
    if (error) return [];
    return data ?? [];
  },

  getForActivity: async (activityId: string): Promise<ParticipantTransport[]> => {
    const { data, error } = await supabase
      .from('public_participants')
      .select('user_id, display_name, avatar_url, transport_type, transport_seats, transport_from_name, transport_departs_at')
      .eq('activity_id', activityId)
      .not('transport_type', 'is', null)
      .order('transport_type');
    if (error) return [];
    return (data ?? []) as ParticipantTransport[];
  },

  // Routes through get_activity_seat_assignments (mig 00089, hardened
  // for blocks in 00203, extended with pickup info in 00204) so
  // third-party participants get the full "X rides with Y" picture.
  // Direct table SELECT was filtered by RLS to (requester_id =
  // auth.uid() OR driver_id = auth.uid()) and silently hid every
  // assignment from anyone not directly involved.
  getSeatAssignments: async (activityId: string): Promise<SeatAssignment[]> => {
    const { data, error } = await supabase.rpc('get_activity_seat_assignments', {
      p_activity_id: activityId,
    });
    if (error) return [];
    return (data ?? []).map((r) => ({
      id: r.id,
      driver_id: r.driver_id,
      requester_id: r.requester_id,
      display_name: r.display_name ?? '?',
      avatar_url: r.avatar_url,
      pickup_from: r.pickup_from,
      requested_pickup_at: r.requested_pickup_at,
    }));
  },
};
