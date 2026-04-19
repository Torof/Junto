import { supabase } from './supabase';

// Reputation badges
export const POSITIVE_BADGES = [
  { key: 'trustworthy', icon: '🤝', threshold: 5 },
  { key: 'level_accurate', icon: '🧗', threshold: 5 },
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

export const ALL_BADGES = [...POSITIVE_BADGES, ...NEGATIVE_BADGES];

// Trophy badges
const PROGRESSION_TROPHIES = [
  { key: 'newcomer', icon: '🌱', min: 0, max: 4 },
  { key: 'confirmed', icon: '✅', min: 10, max: 29 },
  { key: 'experienced', icon: '🏅', min: 30, max: 74 },
  { key: 'veteran', icon: '🦅', min: 75, max: Infinity },
] as const;

export const SPORT_TROPHY_THRESHOLD = 20;

export interface ReputationBadge {
  badge_key: string;
  vote_count: number;
}

export interface Trophy {
  trophy_key: string;
  trophy_count: number;
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

  getProgressionTrophy: (completedCount: number) => {
    return PROGRESSION_TROPHIES.find((t) => completedCount >= t.min && completedCount <= t.max) ?? PROGRESSION_TROPHIES[0];
  },

  getBadgeInfo: (key: string) => {
    return ALL_BADGES.find((b) => b.key === key);
  },

  isPositive: (key: string) => {
    return POSITIVE_BADGES.some((b) => b.key === key);
  },
};
