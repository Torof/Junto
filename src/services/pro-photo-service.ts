import { supabase } from './supabase';

export interface ProPhoto {
  id: string;
  pro_id: string;
  photo_url: string;
  order_index: number;
  created_at: string;
}

export interface ProOfferingPhoto {
  id: string;
  offering_id: string;
  photo_url: string;
  order_index: number;
  created_at: string;
}

// Pro page gallery — up to 25 photos per pro, owner-managed.
// All mutations go through SECURITY DEFINER RPCs; reads are public via
// RLS so the storefront renders for anon visitors when Phase 0.5 lands.
export const proPhotoService = {
  listByPro: async (proId: string): Promise<ProPhoto[]> => {
    const { data, error } = await supabase
      .from('pro_profile_photos')
      .select('id, pro_id, photo_url, order_index, created_at')
      .eq('pro_id', proId)
      .order('order_index', { ascending: true });
    if (error) throw error;
    return data ?? [];
  },

  add: async (photoUrl: string): Promise<string> => {
    const { data, error } = await supabase.rpc('add_pro_photo', {
      p_photo_url: photoUrl,
    });
    if (error) throw error;
    return data as string;
  },

  remove: async (photoId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_pro_photo', {
      p_photo_id: photoId,
    });
    if (error) throw error;
  },

  setUrl: async (photoId: string, photoUrl: string): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_photo_url', {
      p_photo_id: photoId,
      p_photo_url: photoUrl,
    });
    if (error) throw error;
  },

  reorder: async (photoIds: string[]): Promise<void> => {
    const { error } = await supabase.rpc('reorder_pro_photos', {
      p_photo_ids: photoIds,
    });
    if (error) throw error;
  },
};

// Per-offering gallery — same cap + same RPC pattern, scoped by
// offering_id since one pro can have many catalog items each with their
// own photoset.
export const proOfferingPhotoService = {
  listByOffering: async (offeringId: string): Promise<ProOfferingPhoto[]> => {
    const { data, error } = await supabase
      .from('pro_offering_photos')
      .select('id, offering_id, photo_url, order_index, created_at')
      .eq('offering_id', offeringId)
      .order('order_index', { ascending: true });
    if (error) throw error;
    return data ?? [];
  },

  add: async (offeringId: string, photoUrl: string): Promise<string> => {
    const { data, error } = await supabase.rpc('add_pro_offering_photo', {
      p_offering_id: offeringId,
      p_photo_url: photoUrl,
    });
    if (error) throw error;
    return data as string;
  },

  remove: async (photoId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_pro_offering_photo', {
      p_photo_id: photoId,
    });
    if (error) throw error;
  },

  setUrl: async (photoId: string, photoUrl: string): Promise<void> => {
    const { error } = await supabase.rpc('set_pro_offering_photo_url', {
      p_photo_id: photoId,
      p_photo_url: photoUrl,
    });
    if (error) throw error;
  },

  reorder: async (offeringId: string, photoIds: string[]): Promise<void> => {
    const { error } = await supabase.rpc('reorder_pro_offering_photos', {
      p_offering_id: offeringId,
      p_photo_ids: photoIds,
    });
    if (error) throw error;
  },
};
