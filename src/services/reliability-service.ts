import { supabase } from './supabase';

export const reliabilityService = {
  confirmPresence: async (activityId: string, presentUserIds: string[]): Promise<void> => {
    const { error } = await supabase.rpc('confirm_presence' as 'join_activity', {
      p_activity_id: activityId,
      p_present_user_ids: presentUserIds,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getReliabilityEmoji: (score: number | null): string => {
    if (score === null) return '⚪'; // Not enough data
    if (score >= 90) return '🟢';
    if (score >= 70) return '🟡';
    return '🔴';
  },

  getReliabilityLabel: (score: number | null): string => {
    if (score === null) return '—';
    return `${score}%`;
  },
};
