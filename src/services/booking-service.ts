import { supabase } from './supabase';

export type BookingPeriod = 'am' | 'pm';
export type BookingStatus = 'pending' | 'accepted' | 'declined' | 'cancelled' | 'cancelled_pro' | 'expired';

export interface ProAvailabilitySlot {
  day: string; // 'YYYY-MM-DD'
  period: BookingPeriod;
}

export interface AgendaItem {
  kind: 'availability' | 'booking';
  id: string;
  day: string;
  period: BookingPeriod;
  status: BookingStatus | null;
  offering_id: string | null;
  offering_title: string | null;
  party_size: number | null;
  client_id: string | null;
  client_name: string | null;
  manual_phone: string | null;
  message: string | null;
  is_manual: boolean | null;
}

export interface MyBooking {
  id: string;
  offering_id: string;
  offering_title: string;
  pro_id: string;
  pro_name: string | null;
  day: string;
  period: BookingPeriod;
  party_size: number;
  status: BookingStatus;
  conversation_id: string | null;
  created_at: string;
}

export const bookingService = {
  setAvailability: async (day: string, period: BookingPeriod, available: boolean): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_availability', {
      p_day: day, p_period: period, p_available: available,
    });
    if (error) throw error;
  },

  getProAvailability: async (proId: string): Promise<ProAvailabilitySlot[]> => {
    const { data, error } = await supabase.rpc('get_pro_availability', { p_pro_id: proId });
    if (error) throw error;
    return (data ?? []) as ProAvailabilitySlot[];
  },

  getAgenda: async (from: string, to: string): Promise<AgendaItem[]> => {
    const { data, error } = await supabase.rpc('get_pro_agenda', { p_from: from, p_to: to });
    if (error) throw error;
    return (data ?? []) as AgendaItem[];
  },

  createBooking: async (
    offeringId: string, day: string, period: BookingPeriod, partySize: number, message?: string,
  ): Promise<string> => {
    const { data, error } = await supabase.rpc('create_booking', {
      p_offering_id: offeringId, p_day: day, p_period: period,
      p_party_size: partySize, p_message: message ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },

  createManualBooking: async (
    offeringId: string, day: string, period: BookingPeriod, partySize: number,
    name: string, phone?: string,
  ): Promise<string> => {
    const { data, error } = await supabase.rpc('create_manual_booking', {
      p_offering_id: offeringId, p_day: day, p_period: period,
      p_party_size: partySize, p_name: name, p_phone: phone ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },

  accept: async (bookingId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('accept_booking', { p_booking_id: bookingId });
    if (error) throw error;
    return data as string; // conversation_id
  },

  decline: async (bookingId: string): Promise<void> => {
    const { error } = await supabase.rpc('decline_booking', { p_booking_id: bookingId });
    if (error) throw error;
  },

  cancelAsClient: async (bookingId: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_booking', { p_booking_id: bookingId });
    if (error) throw error;
  },

  cancelAsPro: async (bookingId: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_booking_pro', { p_booking_id: bookingId });
    if (error) throw error;
  },

  getMyBookings: async (): Promise<MyBooking[]> => {
    const { data, error } = await supabase.rpc('get_my_bookings');
    if (error) throw error;
    return (data ?? []) as MyBooking[];
  },
};
