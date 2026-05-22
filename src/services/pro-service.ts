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
  banner_url: string | null;
  pin_image_url: string | null;
  last_location_change_at: string;
  created_at: string;
  updated_at: string;
}

export interface RegisterAsProInput {
  display_name: string;
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

// Lightweight shape returned by getNearby — just what the pin needs.
// Tap on the pin loads the full ProProfile via getById.
export interface NearbyPro {
  user_id: string;
  display_name: string;
  primary_lng: number;
  primary_lat: number;
  pin_image_url: string | null;
}

export const proService = {
  // Fetch a pro's profile. Returns null when the user isn't a pro or
  // is suspended (the RLS policy hides those rows; the missing row
  // surfaces as null here).
  getById: async (userId: string): Promise<ProProfile | null> => {
    const { data, error } = await supabase
      .from('pro_profiles')
      .select(
        'user_id, display_name, tagline, description, website, email, phone, instagram, facebook, primary_lng, primary_lat, primary_location_name, banner_url, pin_image_url, last_location_change_at, created_at, updated_at',
      )
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw error;
    return data ?? null;
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

  setBanner: async (bannerUrl: string | null): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_banner', {
      p_banner_url: bannerUrl ?? undefined,
    });
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
      .select('user_id, display_name, primary_lng, primary_lat, pin_image_url');

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
