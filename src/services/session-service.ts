import { supabase } from './supabase';
import type { BookingPeriod } from './booking-service';

// Fixed dates (00575): the pro posts a date for one of their outings — a
// half-day, a day or up to 14 days — and clients sign up straight away. A
// sign-up is a booking (session_id set, day/period = the start half-day).

export interface SessionWindow {
  start_day: string; // 'YYYY-MM-DD'
  start_period: BookingPeriod;
  end_day: string;
  end_period: BookingPeriod;
}

// The pro's own dates (agenda).
export interface MySession extends SessionWindow {
  id: string;
  offering_id: string;
  offering_title: string;
  sport_key: string | null;
  sport_category: string | null;
  max_participants: number;
  min_participants: number | null;
  meeting_point: string | null;
  taken: number;
  // 00577: minimum reached or maintained by the pro.
  confirmed: boolean;
}

// An upcoming date as a client sees it on the outing page.
export interface OfferingSession extends SessionWindow {
  id: string;
  max_participants: number;
  min_participants: number | null;
  meeting_point: string | null;
  taken: number;
  my_booking_id: string | null;
}

// Pending « sur demande » requests that posting a date would decline.
export interface SessionConflict {
  booking_id: string;
  day: string;
  period: BookingPeriod;
  client_name: string | null;
  offering_title: string | null;
  party_size: number;
}

export interface SessionInput extends SessionWindow {
  max_participants: number;
  min_participants: number | null;
  meeting_point: string | null;
}

export const sessionService = {
  getConflicts: async (w: SessionWindow): Promise<SessionConflict[]> => {
    const { data, error } = await supabase.rpc('get_session_conflicts', {
      p_start_day: w.start_day, p_start_period: w.start_period,
      p_end_day: w.end_day, p_end_period: w.end_period,
    });
    if (error) throw error;
    return (data ?? []) as SessionConflict[];
  },

  create: async (offeringId: string, s: SessionInput): Promise<string> => {
    const { data, error } = await supabase.rpc('create_pro_session', {
      p_offering_id: offeringId,
      p_start_day: s.start_day, p_start_period: s.start_period,
      p_end_day: s.end_day, p_end_period: s.end_period,
      p_max_participants: s.max_participants,
      p_min_participants: s.min_participants ?? undefined,
      p_meeting_point: s.meeting_point ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },

  update: async (sessionId: string, s: SessionInput): Promise<void> => {
    const { error } = await supabase.rpc('update_pro_session', {
      p_session_id: sessionId,
      p_start_day: s.start_day, p_start_period: s.start_period,
      p_end_day: s.end_day, p_end_period: s.end_period,
      p_max_participants: s.max_participants,
      p_min_participants: s.min_participants ?? undefined,
      p_meeting_point: s.meeting_point ?? undefined,
    });
    if (error) throw error;
  },

  // The optional reason lands in each client's thread. Returns the sign-ups closed.
  cancel: async (sessionId: string, reason?: string): Promise<number> => {
    const { data, error } = await supabase.rpc('cancel_pro_session', {
      p_session_id: sessionId, p_reason: reason,
    });
    if (error) throw error;
    return data ?? 0;
  },

  getMine: async (from: string, to: string): Promise<MySession[]> => {
    const { data, error } = await supabase.rpc('get_my_sessions', { p_from: from, p_to: to });
    if (error) throw error;
    return (data ?? []) as MySession[];
  },

  getForOffering: async (offeringId: string): Promise<OfferingSession[]> => {
    const { data, error } = await supabase.rpc('get_offering_sessions', { p_offering_id: offeringId });
    if (error) throw error;
    return (data ?? []) as OfferingSession[];
  },

  // Returns the booking id (the group form is sent with it afterwards).
  join: async (sessionId: string, partySize: number, message?: string): Promise<string> => {
    const { data, error } = await supabase.rpc('join_pro_session', {
      p_session_id: sessionId, p_party_size: partySize, p_message: message ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },
};
