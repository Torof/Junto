import { supabase } from './supabase';

export interface ProProfile {
  user_id: string;
  display_name: string;
  tagline: string | null;
  description: string | null;
  website: string | null;
  email: string | null;
  phone: string | null;
  instagram: string | null;
  facebook: string | null;
  primary_lng: number;
  primary_lat: number;
  primary_location_name: string;
  pin_image_url: string | null;
  status: 'pending' | 'approved' | 'rejected';
  rejection_reason: string | null;
  last_location_change_at: string;
  created_at: string;
  updated_at: string;
}

export interface RegisterAsProInput {
  display_name: string;
  company_name: string;
  real_name: string;
  primary_lng: number;
  primary_lat: number;
  primary_location_name: string;
  tagline?: string | null;
  description?: string | null;
  website?: string | null;
  email?: string | null;
  phone?: string | null;
  instagram?: string | null;
  facebook?: string | null;
}

export type UpdateProProfileInput = Partial<RegisterAsProInput>;

export interface PendingProApplication {
  user_id: string;
  display_name: string;
  company_name: string | null;
  real_name: string | null;
  email: string | null;
  phone: string | null;
  website: string | null;
  primary_location_name: string;
  created_at: string;
}

// Lightweight shape returned by getNearby — just what the pin + tooltip
// need. Tap on the pin loads the full ProProfile via getById.
// description is included so the pin-anchored tooltip can show a short
// "à propos" line without a second roundtrip; cost is ~1KB per pro in
// the viewport which is acceptable at expected densities.
export interface NearbyPro {
  user_id: string;
  display_name: string;
  primary_lng: number;
  primary_lat: number;
  pin_image_url: string | null;
  description: string | null;
}

export const proService = {
  // Fetch a pro's profile. Returns null when the user isn't a pro or
  // is suspended (the RLS policy hides those rows; the missing row
  // surfaces as null here).
  getById: async (userId: string): Promise<ProProfile | null> => {
    const { data, error } = await supabase
      .from('pro_profiles')
      .select(
        'user_id, display_name, tagline, description, website, email, phone, instagram, facebook, primary_lng, primary_lat, primary_location_name, pin_image_url, status, rejection_reason, last_location_change_at, created_at, updated_at',
      )
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw error;
    return (data ?? null) as ProProfile | null;
  },

  // Fetch the current user's own pro profile (or null if they're not
  // a pro yet). Same query as getById but explicit so callers don't
  // pass auth.uid around.
  getMine: async (): Promise<ProProfile | null> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return null;
    return proService.getById(userId);
  },

  register: async (input: RegisterAsProInput): Promise<void> => {
    const { error } = await supabase.rpc('register_as_pro', {
      p_display_name: input.display_name,
      p_company_name: input.company_name,
      p_real_name: input.real_name,
      p_tagline: input.tagline ?? undefined,
      p_description: input.description ?? undefined,
      p_website: input.website ?? undefined,
      p_email: input.email ?? undefined,
      p_phone: input.phone ?? undefined,
      p_instagram: input.instagram ?? undefined,
      p_facebook: input.facebook ?? undefined,
      p_primary_lng: input.primary_lng,
      p_primary_lat: input.primary_lat,
      p_primary_location_name: input.primary_location_name,
    });
    if (error) throw error;
  },

  update: async (input: UpdateProProfileInput): Promise<void> => {
    const { error } = await supabase.rpc('update_pro_profile', {
      p_display_name: input.display_name ?? undefined,
      p_tagline: input.tagline ?? undefined,
      p_description: input.description ?? undefined,
      p_website: input.website ?? undefined,
      p_email: input.email ?? undefined,
      p_phone: input.phone ?? undefined,
      p_instagram: input.instagram ?? undefined,
      p_facebook: input.facebook ?? undefined,
      p_primary_lng: input.primary_lng ?? undefined,
      p_primary_lat: input.primary_lat ?? undefined,
      p_primary_location_name: input.primary_location_name ?? undefined,
    });
    if (error) throw error;
  },

  unregister: async (): Promise<void> => {
    const { error } = await supabase.rpc('unregister_as_pro');
    if (error) throw error;
  },

  // Re-submit a rejected application (back to pending for admin re-review).
  resubmit: async (): Promise<void> => {
    const { error } = await supabase.rpc('resubmit_pro_application');
    if (error) throw error;
  },

  // --- Admin review (RLS lets admins read non-approved rows) ---
  getPendingApplications: async (): Promise<PendingProApplication[]> => {
    const { data, error } = await supabase
      .from('pro_profiles')
      .select('user_id, display_name, company_name, real_name, email, phone, website, primary_location_name, created_at')
      .eq('status', 'pending')
      .order('created_at', { ascending: true });
    if (error) throw error;
    return (data ?? []) as PendingProApplication[];
  },

  approve: async (userId: string): Promise<void> => {
    const { error } = await supabase.rpc('approve_pro', { p_user_id: userId });
    if (error) throw error;
  },

  reject: async (userId: string, reason?: string): Promise<void> => {
    const { error } = await supabase.rpc('reject_pro', { p_user_id: userId, p_reason: reason ?? undefined });
    if (error) throw error;
  },

  setPinImage: async (pinImageUrl: string | null): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_pin_image', {
      p_pin_image_url: pinImageUrl ?? undefined,
    });
    if (error) throw error;
  },

  // Pros within the map viewport. Returns the minimal fields needed to
  // place the pin; the full profile is fetched on tap.
  getNearby: async (bounds?: {
    swLng: number;
    swLat: number;
    neLng: number;
    neLat: number;
  }): Promise<NearbyPro[]> => {
    let query = supabase
      .from('pro_profiles')
      .select('user_id, display_name, primary_lng, primary_lat, pin_image_url, description');

    if (bounds) {
      query = query
        .gte('primary_lng', bounds.swLng)
        .lte('primary_lng', bounds.neLng)
        .gte('primary_lat', bounds.swLat)
        .lte('primary_lat', bounds.neLat);
    }

    const { data, error } = await query;
    if (error) throw error;
    return data ?? [];
  },
};
