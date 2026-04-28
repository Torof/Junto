import { supabase } from './supabase';

// Reputation badges
export const POSITIVE_BADGES = [
  { key: 'trustworthy', icon: '🤝', threshold: 5 },
  { key: 'great_leader', icon: '⭐', threshold: 5 },
  { key: 'good_vibes', icon: '😊', threshold: 5 },
  { key: 'punctual', icon: '⏱️', threshold: 5 },
] as const;

export const NEGATIVE_BADGES = [
  { key: 'level_overestimated', icon: '⚠️', threshold: 15 },
  { key: 'difficult_attitude', icon: '😤', threshold: 15 },
  { key: 'unreliable_field', icon: '🎭', threshold: 15 },
  { key: 'aggressive', icon: '😠', threshold: 15 },
] as const;

// Tier ladder shared across joined / created / per-sport categories.
// Mirror of SQL badge_tier_for() in migration 00135.
export const TIERS = [
  { key: 't1', min: 5,  max: 9 },
  { key: 't2', min: 10, max: 19 },
  { key: 't3', min: 20, max: 49 },
  { key: 't4', min: 50, max: 74 },
  { key: 't5', min: 75, max: Infinity },
] as const;

export type TierKey = typeof TIERS[number]['key'];
export type TrophyCategory = 'joined' | 'created' | 'sport';

export function tierFor(count: number): TierKey | null {
  if (count >= 75) return 't5';
  if (count >= 50) return 't4';
  if (count >= 20) return 't3';
  if (count >= 10) return 't2';
  if (count >= 5)  return 't1';
  return null;
}

export interface ReputationBadge {
  badge_key: string;
  vote_count: number;
}

export interface Trophy {
  category: TrophyCategory;
  sport_key: string | null;
  count: number;
}

export interface PeerReviewParticipant {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  confirmed_present: boolean | null;
  peer_validation_count: number;
  i_voted_presence: boolean;
  my_badge_votes: string[];
}

export const badgeService = {
  giveReputationBadge: async (votedId: string, activityId: string, badgeKey: string): Promise<void> => {
    const { error } = await supabase.rpc('give_reputation_badge' as 'join_activity', {
      p_voted_id: votedId,
      p_activity_id: activityId,
      p_badge_key: badgeKey,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  revokeReputationBadge: async (votedId: string, activityId: string, badgeKey: string): Promise<void> => {
    const { error } = await supabase.rpc('revoke_reputation_badge' as 'join_activity', {
      p_voted_id: votedId,
      p_activity_id: activityId,
      p_badge_key: badgeKey,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  peerValidatePresence: async (votedId: string, activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('peer_validate_presence' as 'join_activity', {
      p_voted_id: votedId,
      p_activity_id: activityId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getPeerReviewState: async (activityId: string): Promise<PeerReviewParticipant[]> => {
    const { data, error } = await supabase.rpc('get_activity_peer_review_state' as 'join_activity', {
      p_activity_id: activityId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    // Migration 00138 returns a jsonb array directly — supabase-js gives us
    // the parsed value, which is already a list of records.
    return (data as unknown as PeerReviewParticipant[] | null) ?? [];
  },

  getUserReputation: async (userId: string): Promise<ReputationBadge[]> => {
    const { data, error } = await supabase.rpc('get_user_reputation' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as ReputationBadge[]) ?? [];
  },

  getUserTrophies: async (userId: string): Promise<Trophy[]> => {
    const { data, error } = await supabase.rpc('get_user_trophies' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as Trophy[]) ?? [];
  },
};
