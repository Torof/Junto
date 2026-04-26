import dayjs from 'dayjs';
import { colors } from '@/constants/theme';

export type ActivityTimeStatus = 'in_progress' | 'soon' | 'upcoming' | 'completed' | 'cancelled' | 'expired';

export function getActivityTimeStatus(startsAt: string, status: string): ActivityTimeStatus {
  if (status === 'completed') return 'completed';
  if (status === 'cancelled') return 'cancelled';
  if (status === 'expired') return 'expired';
  if (status === 'in_progress') return 'in_progress';

  const now = dayjs();
  const start = dayjs(startsAt);
  const hoursUntilStart = start.diff(now, 'hour', true);

  if (hoursUntilStart <= 2 && hoursUntilStart > 0) return 'soon';
  return 'upcoming';
}

export function getStatusColor(timeStatus: ActivityTimeStatus): string {
  switch (timeStatus) {
    case 'in_progress':
      return colors.success;
    case 'soon':
      return colors.warning;
    case 'upcoming':
      return colors.pinMeeting;
    case 'completed':
      return colors.textSecondary;
    case 'cancelled':
      return colors.error;
    case 'expired':
      return colors.textSecondary;
  }
}

export function getRemainingPlaces(maxParticipants: number | null, participantCount: number): number {
  // Open activities (max=null) are "never full" from the client's POV.
  // The server enforces a hidden 50-cap to prevent abuse.
  if (maxParticipants === null) return Infinity;
  return Math.max(0, maxParticipants - participantCount);
}

export function isActivityOpen(maxParticipants: number | null): boolean {
  return maxParticipants === null;
}
