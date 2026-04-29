import { supabase } from './supabase';

// Reputation badges — Phase 4 taxonomy. Server-side whitelist in mig 00154.
// 4 positives + 3 negatives. Presence is covered by the reliability score
// in the hero, level honesty by the per-sport 3-way vote in the popover.
export const POSITIVE_BADGES = [
  { key: 'punctual', icon: '⏱️', threshold: 5 },
  { key: 'prepared', icon: '🎒', threshold: 5 },
  { key: 'conciliant', icon: '🤝', threshold: 5 },
  { key: 'prudent', icon: '🛡️', threshold: 5 },
] as const;

export const NEGATIVE_BADGES = [
  { key: 'unprepared', icon: '🎲', threshold: 5 },
  { key: 'aggressive', icon: '😠', threshold: 5 },
  { key: 'reckless', icon: '💥', threshold: 5 },
] as const;

// Per-sport level vote — 3-way mutually exclusive per (voter, voted, activity).
// Lives in the sport popover only, not in the global vouched / warning rows.
export const LEVEL_VOTE_KEYS = ['level_over', 'level_right', 'level_under'] as const;
export type LevelVoteKey = typeof LEVEL_VOTE_KEYS[number];

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
  /** Most recent vote timestamp for this badge — drives the popover meta. */
  last_at: string | null;
}

// Peer badge tier — three positives + one negative + locked.
// Derived from vote_count via peerTierFor() / peerNegativeTier().
export type PeerTier = 'bronze' | 'silver' | 'gold' | 'negative' | 'locked';

export const PEER_TIER_BANDS: Record<Exclude<PeerTier, 'negative' | 'locked'>, { min: number; max: number }> = {
  bronze: { min: 1, max: 9 },
  silver: { min: 10, max: 49 },
  gold: { min: 50, max: Infinity },
};

/** Tier for a positive peer badge given total vote count. */
export function peerPositiveTier(count: number): PeerTier {
  if (count <= 0) return 'locked';
  if (count < 10) return 'bronze';
  if (count < 50) return 'silver';
  return 'gold';
}

/** Negatives have a single 'negative' tier (red). Visible threshold = 5 active. */
export const NEGATIVE_VISIBILITY_THRESHOLD = 5;

/** Progression to the next tier — used by the popover progression bar.
 * Returns null when already gold. */
export function peerProgressToNext(count: number): { pct: number; nextThreshold: number; nextTier: PeerTier } | null {
  if (count < 10) {
    return { pct: (count / 10) * 100, nextThreshold: 10, nextTier: 'silver' };
  }
  if (count < 50) {
    return { pct: ((count - 10) / 40) * 100, nextThreshold: 50, nextTier: 'gold' };
  }
  return null;
}

export interface Trophy {
  category: TrophyCategory;
  sport_key: string | null;
  count: number;
}

export interface SportLevel {
  sport_key: string;
  dots: number;
}

export interface SportLevelVotes {
  sport_key: string;
  level_over: number;
  level_right: number;
  level_under: number;
}

// Aggregates fed into the data-driven Junto award definitions on the client.
// Server returns one JSONB blob; client decides which awards earn which tier.
export interface AwardAggregates {
  joined: number;
  created: number;
  distinct_sports: number;
  multi_day_count: number;
  by_category: Record<string, { outings: number; distinct_sports: number }>;
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

  getUserSportLevels: async (userId: string): Promise<SportLevel[]> => {
    const { data, error } = await supabase.rpc('get_user_sport_levels' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as SportLevel[]) ?? [];
  },

  getUserSportLevelVotes: async (userId: string): Promise<SportLevelVotes[]> => {
    const { data, error } = await supabase.rpc('get_user_sport_level_votes' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as SportLevelVotes[]) ?? [];
  },

  getUserAwardAggregates: async (userId: string): Promise<AwardAggregates> => {
    const empty: AwardAggregates = {
      joined: 0,
      created: 0,
      distinct_sports: 0,
      multi_day_count: 0,
      by_category: {},
    };
    const { data, error } = await supabase.rpc('get_user_award_aggregates' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error || !data) return empty;
    return data as unknown as AwardAggregates;
  },
};
