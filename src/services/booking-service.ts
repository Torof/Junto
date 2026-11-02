import { supabase } from './supabase';
import type { Json } from '@/types/supabase';

export type BookingPeriod = 'am' | 'pm';

// Fiche participant (00422) : champs demandés par l'offre + réponses.
export interface ParticipantFields { std: string[]; custom: string[] }
export type ParticipantEntry = Record<string, string> & { custom?: Record<string, string> };
export type BookingStatus = 'pending' | 'accepted' | 'declined' | 'cancelled' | 'cancelled_pro' | 'expired';

export interface ProAvailabilitySlot {
  day: string; // 'YYYY-MM-DD'
  period: BookingPeriod;
  // Places déjà ACCEPTÉES sur le créneau (toutes offres du pro). Depuis 00566
  // la DB refuse une demande ou une acceptation qui dépasse le max de l'offre.
  taken: number;
}

export interface AgendaItem {
  // 'busy' = half-day busy in the pro's own calendar (iCal import, 00568).
  kind: 'availability' | 'booking' | 'busy';
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
  sport_key: string | null;
  sport_category: string | null;
  participant_fields: ParticipantFields | null;
  participant_info: ParticipantEntry[] | null;
  client_avatar_url: string | null;
  max_participants: number | null;
  // Sign-up to a fixed date (00575).
  session_id: string | null;
  // 00577: last day of an on-request booking by the day / over days (start
  // morning → end_day afternoon); its on-request outing's minimum and whether
  // it is confirmed (a fixed date's come from get_my_sessions).
  end_day: string | null;
  min_participants: number | null;
  confirmed: boolean | null;
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
  location_name: string | null;
  price_eur: number | null;
  price_unit: 'person' | 'group' | null;
  sport_key: string | null;
  sport_category: string | null;
  equipment_required: string[] | null;
  participant_fields: ParticipantFields | null;
  participant_info: ParticipantEntry[] | null;
  // Sign-up to a fixed date (00575): its end and meeting point.
  session_id: string | null;
  end_day: string | null;
  end_period: BookingPeriod | null;
  meeting_point: string | null;
  // 00577, accepted bookings only: the outing's minimum, how many are signed
  // up (a number, no names) and whether the departure is confirmed.
  min_participants: number | null;
  outing_total: number | null;
  confirmed: boolean | null;
}

export const bookingService = {
  setAvailability: async (day: string, period: BookingPeriod, available: boolean): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_availability', {
      p_day: day, p_period: period, p_available: available,
    });
    if (error) throw error;
  },

  setParticipantInfo: async (bookingId: string, info: ParticipantEntry[]): Promise<void> => {
    const { error } = await supabase.rpc('set_booking_participant_info', {
      p_booking_id: bookingId,
      p_info: info as unknown as Json,
    });
    if (error) throw error;
  },

  setAvailabilityBulk: async (
    slots: { day: string; period: BookingPeriod }[], available: boolean,
  ): Promise<void> => {
    if (slots.length === 0) return;
    const { error } = await supabase.rpc('set_pro_availability_bulk', {
      p_days: slots.map((s) => s.day),
      p_periods: slots.map((s) => s.period),
      p_available: available,
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

  // Pro → client thread from a pending or confirmed booking (00565): opens or
  // reuses the DM and returns its id.
  openConversation: async (bookingId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('open_booking_conversation', { p_booking_id: bookingId });
    if (error) throw error;
    return data as string;
  },

  // Same message to every confirmed in-app client of one outing session, each
  // in their private thread (00567). Returns how many clients got it.
  messageOutingClients: async (offeringId: string, day: string, period: BookingPeriod, content: string): Promise<number> => {
    const { data, error } = await supabase.rpc('message_outing_clients', {
      p_offering_id: offeringId, p_day: day, p_period: period, p_content: content,
    });
    if (error) throw error;
    return data ?? 0;
  },

  // Cancels a whole session (00567); the optional reason lands in each
  // client's thread. Returns how many bookings were closed.
  cancelOuting: async (offeringId: string, day: string, period: BookingPeriod, reason?: string): Promise<number> => {
    const { data, error } = await supabase.rpc('cancel_outing', {
      p_offering_id: offeringId, p_day: day, p_period: period, p_reason: reason,
    });
    if (error) throw error;
    return data ?? 0;
  },

  // « Maintenir la sortie » (00577): keeps an outing below its minimum —
  // clients are told the departure is confirmed. False if it already was.
  confirmOuting: async (offeringId: string, day: string, period: BookingPeriod): Promise<boolean> => {
    const { data, error } = await supabase.rpc('confirm_outing', {
      p_offering_id: offeringId, p_day: day, p_period: period,
    });
    if (error) throw error;
    return data ?? false;
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
