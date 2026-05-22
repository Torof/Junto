import { supabase } from './supabase';

export interface ProOffering {
  id: string;
  pro_id: string;
  sport_id: string;
  title: string;
  description: string;
  level: string;
  location_name: string;
  duration: string | null;
  max_participants: number | null;
  schedule_text: string | null;
  distance_km: number | null;
  elevation_gain_m: number | null;
  image_url: string | null;
  lng: number;
  lat: number;
  sport_key: string;
  sport_icon: string;
  sport_category: string;
  pro_name: string;
  created_at: string;
  updated_at: string;
}

export interface CreateProOfferingInput {
  sport_id: string;
  title: string;
  description: string;
  level: string;
  location_lng: number;
  location_lat: number;
  location_name: string;
  duration?: string | null;
  max_participants?: number | null;
  schedule_text?: string | null;
  distance_km?: number | null;
  elevation_gain_m?: number | null;
}

export interface UpdateProOfferingInput extends CreateProOfferingInput {
  offering_id: string;
}

export const proOfferingService = {
  // Single offering by id. Pulls from the view so we get sport metadata
  // and pro_name in one round-trip.
  getById: async (id: string): Promise<ProOffering | null> => {
    const { data, error } = await supabase
      .from('pro_offerings_with_coords')
      .select(
        'id, pro_id, sport_id, title, description, level, location_name, duration, max_participants, schedule_text, distance_km, elevation_gain_m, image_url, lng, lat, sport_key, sport_icon, sport_category, pro_name, created_at, updated_at',
      )
      .eq('id', id)
      .maybeSingle();
    if (error) throw error;
    return data as unknown as ProOffering | null;
  },

  // All offerings by one pro (catalog tab on the pro profile page).
  getByProId: async (proId: string): Promise<ProOffering[]> => {
    const { data, error } = await supabase
      .from('pro_offerings_with_coords')
      .select(
        'id, pro_id, sport_id, title, description, level, location_name, duration, max_participants, schedule_text, distance_km, elevation_gain_m, image_url, lng, lat, sport_key, sport_icon, sport_category, pro_name, created_at, updated_at',
      )
      .eq('pro_id', proId)
      .order('created_at', { ascending: false });
    if (error) throw error;
    return (data ?? []) as unknown as ProOffering[];
  },

  // Offerings within the map viewport. Same shape as activities/pros
  // nearby queries — bounds optional for "load everything" fallback.
  getNearby: async (bounds?: {
    swLng: number;
    swLat: number;
    neLng: number;
    neLat: number;
  }): Promise<ProOffering[]> => {
    let query = supabase
      .from('pro_offerings_with_coords')
      .select(
        'id, pro_id, sport_id, title, description, level, location_name, duration, max_participants, schedule_text, distance_km, elevation_gain_m, image_url, lng, lat, sport_key, sport_icon, sport_category, pro_name, created_at, updated_at',
      );

    if (bounds) {
      query = query
        .gte('lng', bounds.swLng)
        .lte('lng', bounds.neLng)
        .gte('lat', bounds.swLat)
        .lte('lat', bounds.neLat);
    }

    const { data, error } = await query;
    if (error) throw error;
    return (data ?? []) as unknown as ProOffering[];
  },

  create: async (input: CreateProOfferingInput): Promise<string> => {
    const { data, error } = await supabase.rpc('create_pro_offering', {
      p_sport_id: input.sport_id,
      p_title: input.title,
      p_description: input.description,
      p_level: input.level,
      p_location_lng: input.location_lng,
      p_location_lat: input.location_lat,
      p_location_name: input.location_name,
      p_duration: input.duration ?? undefined,
      p_max_participants: input.max_participants ?? undefined,
      p_schedule_text: input.schedule_text ?? undefined,
      p_distance_km: input.distance_km ?? undefined,
      p_elevation_gain_m: input.elevation_gain_m ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },

  update: async (input: UpdateProOfferingInput): Promise<void> => {
    const { error } = await supabase.rpc('update_pro_offering', {
      p_offering_id: input.offering_id,
      p_sport_id: input.sport_id,
      p_title: input.title,
      p_description: input.description,
      p_level: input.level,
      p_location_lng: input.location_lng,
      p_location_lat: input.location_lat,
      p_location_name: input.location_name,
      p_duration: input.duration ?? undefined,
      p_max_participants: input.max_participants ?? undefined,
      p_schedule_text: input.schedule_text ?? undefined,
      p_distance_km: input.distance_km ?? undefined,
      p_elevation_gain_m: input.elevation_gain_m ?? undefined,
    });
    if (error) throw error;
  },

  remove: async (offeringId: string): Promise<void> => {
    const { error } = await supabase.rpc('delete_pro_offering', {
      p_offering_id: offeringId,
    });
    if (error) throw error;
  },

  setImage: async (offeringId: string, imageUrl: string | null): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_offering_image', {
      p_offering_id: offeringId,
      p_image_url: imageUrl ?? undefined,
    });
    if (error) throw error;
  },
};
