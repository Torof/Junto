import dayjs from 'dayjs';
import { colors } from '@/constants/theme';

export type ActivityTimeStatus = 'in_progress' | 'soon' | 'upcoming';

export function getActivityTimeStatus(startsAt: string, status: string): ActivityTimeStatus {
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
      return colors.cta;
  }
}

export function getRemainingPlaces(maxParticipants: number, participantCount: number): number {
  return Math.max(0, maxParticipants - participantCount);
}
