import { supabase } from './supabase';

// Reviews — Pro storefront surfaces only (pro page + offerings).
// Google-Maps model (DECISIONS 2026-06-10): ungated, 1-5 stars +
// optional text, one review per (reviewer, target), editable, single
// pro reply per review. Reads via the suspension-filtered views;
// writes via SECURITY DEFINER RPCs (mig 00258).

export interface Review {
  id: string;
  reviewer_id: string;
  rating: number;
  body: string | null;
  pro_reply: string | null;
  pro_reply_at: string | null;
  created_at: string;
  updated_at: string;
  reviewer_name: string;
  reviewer_avatar: string | null;
}

export interface ReviewStats {
  review_count: number;
  avg_rating: number;
}

const REVIEW_COLUMNS =
  'id, reviewer_id, rating, body, pro_reply, pro_reply_at, created_at, updated_at, reviewer_name, reviewer_avatar';

export const reviewService = {
  getForPro: async (proId: string): Promise<Review[]> => {
    const { data, error } = await supabase
      .from('pro_reviews_with_profiles')
      .select(REVIEW_COLUMNS)
      .eq('pro_id', proId)
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []) as Review[];
  },

  getForOffering: async (offeringId: string): Promise<Review[]> => {
    const { data, error } = await supabase
      .from('offering_reviews_with_profiles')
      .select(REVIEW_COLUMNS)
      .eq('offering_id', offeringId)
      .order('created_at', { ascending: false })
      .limit(100);
    if (error) throw error;
    return (data ?? []) as Review[];
  },

  getProStats: async (proId: string): Promise<ReviewStats | null> => {
    const { data, error } = await supabase
      .from('pro_review_stats')
      .select('review_count, avg_rating')
      .eq('pro_id', proId)
      .maybeSingle();
    if (error) throw error;
    return data as ReviewStats | null;
  },

  getOfferingStats: async (offeringId: string): Promise<ReviewStats | null> => {
    const { data, error } = await supabase
      .from('offering_review_stats')
      .select('review_count, avg_rating')
      .eq('offering_id', offeringId)
      .maybeSingle();
    if (error) throw error;
    return data as ReviewStats | null;
  },

  createForPro: async (proId: string, rating: number, body: string | null): Promise<string> => {
    const { data, error } = await supabase.rpc('create_pro_review', {
      p_pro_id: proId,
      p_rating: rating,
      p_body: body ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },

  createForOffering: async (offeringId: string, rating: number, body: string | null): Promise<string> => {
    const { data, error } = await supabase.rpc('create_offering_review', {
      p_offering_id: offeringId,
      p_rating: rating,
      p_body: body ?? undefined,
    });
    if (error) throw error;
    return data as string;
  },

  updateForPro: async (reviewId: string, rating: number, body: string | null): Promise<void> => {
    const { error } = await supabase.rpc('update_pro_review', {
      p_review_id: reviewId,
      p_rating: rating,
      p_body: body ?? undefined,
    });
    if (error) throw error;
  },

  updateForOffering: async (reviewId: string, rating: number, body: string | null): Promise<void> => {
    const { error } = await supabase.rpc('update_offering_review', {
      p_review_id: reviewId,
      p_rating: rating,
      p_body: body ?? undefined,
    });
    if (error) throw error;
  },

  deleteForPro: async (reviewId: string): Promise<void> => {
    const { error } = await supabase.rpc('delete_pro_review', { p_review_id: reviewId });
    if (error) throw error;
  },

  deleteForOffering: async (reviewId: string): Promise<void> => {
    const { error } = await supabase.rpc('delete_offering_review', { p_review_id: reviewId });
    if (error) throw error;
  },

  // NULL / empty reply clears the slot server-side.
  replyForPro: async (reviewId: string, reply: string | null): Promise<void> => {
    const { error } = await supabase.rpc('reply_to_pro_review', {
      p_review_id: reviewId,
      p_reply: reply ?? undefined,
    });
    if (error) throw error;
  },

  replyForOffering: async (reviewId: string, reply: string | null): Promise<void> => {
    const { error } = await supabase.rpc('reply_to_offering_review', {
      p_review_id: reviewId,
      p_reply: reply ?? undefined,
    });
    if (error) throw error;
  },
};
