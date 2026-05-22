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

export const proService = {
  // Fetch a pro's profile. Returns null when the user isn't a pro or
  // is suspended (the RLS policy hides those rows; the missing row
  // surfaces as null here).
  getById: async (userId: string): Promise<ProProfile | null> => {
    const { data, error } = await supabase
      .from('pro_profiles')
      .select(
        'user_id, display_name, tagline, description, website, email, phone, instagram, facebook, primary_lng, primary_lat, primary_location_name, last_location_change_at, created_at, updated_at',
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
};
