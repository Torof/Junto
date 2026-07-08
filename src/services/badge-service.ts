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

// Per-sport level vote — mutually exclusive per (voter, voted, activity).
// Exactly two votes: juste (level_right, ▲) / surestimé (level_over, ▼). The
// old level_under ("sous-estimé") vote was dropped everywhere in mig 00300;
// the sport popover computes net = right - over.
export const LEVEL_VOTE_KEYS = ['level_over', 'level_right'] as const;
export type LevelVoteKey = typeof LEVEL_VOTE_KEYS[number];

export type TrophyCategory = 'joined' | 'created' | 'sport';

export interface ReputationBadge {
  badge_key: string;
  vote_count: number;
  /** Most recent vote timestamp for this badge — drives the popover meta. */
  last_at: string | null;
}

/** One voter for a (target user, badge) pair. Used by the Vouched popup
 *  avatar stack. Display-only; popup never offers click-through. */
export interface BadgeVoter {
  voter_id: string;
  display_name: string | null;
  avatar_url: string | null;
  voted_at: string | null;
}

export interface Trophy {
  category: TrophyCategory;
  sport_key: string | null;
  count: number;
}

export interface SportLevel {
  sport_key: string;
  dots: number;
  last_at: string | null;
  first_at: string | null;
}

export interface SportLevelVotes {
  sport_key: string;
  level_over: number;
  level_right: number;
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
  // The target's self-declared level for the activity's sport, or null if none.
  // When null, the level-vote section is hidden (you can't judge an undeclared
  // level — mirrors the 00293 server guard).
  declared_level: string | null;
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

  getVotersForBadge: async (
    userId: string,
    badgeKey: string,
  ): Promise<BadgeVoter[]> => {
    const { data, error } = await supabase.rpc('get_voters_for_badge' as 'join_activity', {
      p_user_id: userId,
      p_badge_key: badgeKey,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as BadgeVoter[]) ?? [];
  },

  // Batch fetch — top positive peer-vouch (above 5-vote threshold) per
  // user. Used by the GroupCard to render an inline vouch chip next to
  // each driver's name. Returns one row per user; users with no vouched
  // positive trait above threshold simply don't appear in the result.
  getTopVouchedBadges: async (
    userIds: string[],
  ): Promise<{ user_id: string; badge_key: string; vote_count: number }[]> => {
    if (userIds.length === 0) return [];
    const { data, error } = await supabase.rpc('get_top_vouched_badges' as 'join_activity', {
      p_user_ids: userIds,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as { user_id: string; badge_key: string; vote_count: number }[]) ?? [];
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
