import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { participationService } from '@/services/participation-service';
import { UserAvatar } from './user-avatar';

interface Props {
  activityId: string;
  creatorId: string;
  creatorName: string;
  creatorAvatar: string | null;
  maxParticipants: number | null;
  onOpenAll: () => void;
}

// Total avatars shown before collapsing into a +N badge. The organizer
// always takes the first slot, so AVATAR_STACK_SIZE - 1 others are shown.
const AVATAR_STACK_SIZE = 5;

export function OrganizerCard({ activityId, creatorId, creatorName, creatorAvatar, maxParticipants, onOpenAll }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: accepted } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId),
    staleTime: 0,
  });

  const otherParticipants = useMemo(
    () => (accepted ?? []).filter((p) => p.user_id !== creatorId),
    [accepted, creatorId],
  );
  const creatorPresent = (accepted ?? []).find((p) => p.user_id === creatorId)?.confirmed_present === true;

  const visibleOthers = otherParticipants.slice(0, AVATAR_STACK_SIZE - 1);
  const extra = Math.max(0, otherParticipants.length - visibleOthers.length);
  const totalParticipants = (accepted ?? []).length;
  const isOpen = maxParticipants === null;
  const freeSlots = isOpen ? Infinity : Math.max(0, (maxParticipants ?? 0) - totalParticipants);
  const isFull = !isOpen && freeSlots === 0;

  return (
    <Pressable onPress={onOpenAll} style={styles.row} accessibilityLabel={t('organizer.viewAll')}>
      <View style={styles.stack}>
        {/* Organizer always first, marked with the orange organizer ring. */}
        <View style={[styles.stackAvatarWrap, { marginLeft: 0, zIndex: AVATAR_STACK_SIZE + 1 }]}>
          <UserAvatar name={creatorName} avatarUrl={creatorAvatar} size={34} confirmedPresent={creatorPresent} isOrganizer />
        </View>
        {visibleOthers.map((p, i) => (
          <View key={p.user_id} style={[styles.stackAvatarWrap, { marginLeft: -10, zIndex: AVATAR_STACK_SIZE - i }]}>
            <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={34} confirmedPresent={p.confirmed_present === true} />
          </View>
        ))}
        {extra > 0 && (
          <View style={[styles.extraBadge, { marginLeft: -10 }]}>
            <Text style={styles.extraBadgeText}>+{extra}</Text>
          </View>
        )}
      </View>

      <View style={styles.countBlock}>
        <Text style={styles.participantsCountText} numberOfLines={1}>
          {t('organizer.participantsCount', { count: totalParticipants })}
        </Text>
        <Text style={[styles.freeSlotsText, isFull && styles.freeSlotsTextFull]} numberOfLines={1}>
          {isOpen
            ? t('create.openActivityValue')
            : isFull
              ? t('organizer.full')
              : t('organizer.freeSlots', { count: freeSlots })}
        </Text>
      </View>

      <View style={styles.viewAllBtn}>
        <Text style={styles.viewAllText}>{t('organizer.viewAll')}</Text>
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Flat — the parent (activity-detail info tab) provides the brutalist
  // outlined card wrapper. A single row: avatar stack · count · Voir tous.
  row: {
    backgroundColor: 'transparent',
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  stack: { flexDirection: 'row', alignItems: 'center', flexShrink: 0 },
  stackAvatarWrap: {
    borderRadius: 999, borderWidth: 2, borderColor: colors.surface,
  },
  extraBadge: {
    width: 34, height: 34, borderRadius: 17,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 2, borderColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
  },
  extraBadgeText: { color: colors.textPrimary, fontSize: 11, fontWeight: '700' },
  countBlock: { flex: 1, minWidth: 0 },
  participantsCountText: {
    color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700',
  },
  freeSlotsText: {
    color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700',
    marginTop: 1,
  },
  freeSlotsTextFull: { color: colors.error },
  viewAllBtn: {
    flexShrink: 0,
    paddingHorizontal: spacing.sm + 2, paddingVertical: 6,
    borderRadius: radius.full,
    backgroundColor: colors.textSecondary + '26',
  },
  viewAllText: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600' },
});
