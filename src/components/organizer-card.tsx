import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { participationService } from '@/services/participation-service';
import { userService } from '@/services/user-service';
import { UserAvatar } from './user-avatar';
import { ReliabilityTierChip } from './reliability-tier-chip';

interface Props {
  activityId: string;
  creatorId: string;
  creatorName: string;
  creatorAvatar: string | null;
  maxParticipants: number | null;
  onOpenAll: () => void;
}

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

  const { data: creatorStats } = useQuery({
    queryKey: ['user-public-stats', creatorId],
    queryFn: () => userService.getPublicStats(creatorId),
    staleTime: 1000 * 60 * 10,
  });

  const otherParticipants = useMemo(
    () => (accepted ?? []).filter((p) => p.user_id !== creatorId),
    [accepted, creatorId],
  );
  const creatorPresent = (accepted ?? []).find((p) => p.user_id === creatorId)?.confirmed_present === true;

  const visible = otherParticipants.slice(0, AVATAR_STACK_SIZE);
  const extra = Math.max(0, otherParticipants.length - AVATAR_STACK_SIZE);
  const totalParticipants = (accepted ?? []).length;
  const isOpen = maxParticipants === null;
  const freeSlots = isOpen ? Infinity : Math.max(0, (maxParticipants ?? 0) - totalParticipants);
  const isFull = !isOpen && freeSlots === 0;

  return (
    <Pressable onPress={onOpenAll} style={styles.card}>
      <View style={styles.topRow}>
        <UserAvatar
          name={creatorName}
          avatarUrl={creatorAvatar}
          size={48}
          confirmedPresent={creatorPresent}
          isOrganizer
        />
        <View style={{ flex: 1, minWidth: 0 }}>
          <View style={styles.nameRow}>
            <Text style={styles.name} numberOfLines={1}>{creatorName}</Text>
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{t('organizer.badge')}</Text>
            </View>
          </View>
          {creatorStats?.reliability_tier && (
            <View style={styles.metaRow}>
              <Text style={styles.reliabilityPrefix}>{t('organizer.reliability')}</Text>
              <ReliabilityTierChip tier={creatorStats.reliability_tier} size="sm" />
            </View>
          )}
          {creatorStats && creatorStats.created_activities > 0 && (
            <Text style={styles.creatorStatText}>
              {t('organizer.activitiesCreated', { count: creatorStats.created_activities })}
            </Text>
          )}
        </View>
      </View>

      {otherParticipants.length === 0 ? (
        <View style={styles.emptyRow}>
          <Text style={styles.emptyCallout}>
            {isOpen
              ? t('organizer.emptyCalloutOpen')
              : t('organizer.emptyCallout', { count: freeSlots })}
          </Text>
        </View>
      ) : (
        <View style={styles.stackRow}>
          <View style={styles.stack}>
            {visible.map((p, i) => (
              <View key={p.user_id} style={[styles.stackAvatarWrap, { marginLeft: i === 0 ? 0 : -8, zIndex: AVATAR_STACK_SIZE - i }]}>
                <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={26} confirmedPresent={p.confirmed_present === true} />
              </View>
            ))}
            {extra > 0 && (
              <View style={[styles.extraBadge, { marginLeft: -8 }]}>
                <Text style={styles.extraBadgeText}>+{extra}</Text>
              </View>
            )}
          </View>
          <View style={styles.countBlock}>
            <Text style={styles.participantsCountText}>
              {t('organizer.participantsCount', { count: totalParticipants })}
            </Text>
            <Text style={[styles.freeSlotsText, isFull && styles.freeSlotsTextFull]}>
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
        </View>
      )}
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.cta + '2E',
    borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.cta + '66',
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  topRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4 },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 2 },
  name: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  badge: {
    backgroundColor: colors.cta + '26',
    paddingHorizontal: 7, paddingVertical: 2,
    borderRadius: 4,
  },
  badgeText: {
    color: colors.cta, fontSize: 9, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    marginTop: 2,
    flexWrap: 'wrap',
  },
  reliabilityPrefix: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    fontWeight: '600',
  },
  creatorStatText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs + 1,
    marginTop: 2,
  },
  stackRow: {
    flexDirection: 'row', alignItems: 'center',
    gap: spacing.sm,
    marginTop: spacing.sm + 2,
    paddingTop: spacing.sm,
    borderTopWidth: 1, borderTopColor: colors.line,
  },
  stack: { flexDirection: 'row', alignItems: 'center', flexShrink: 0 },
  emptyRow: {
    marginTop: spacing.sm + 2,
    paddingTop: spacing.sm,
    borderTopWidth: 1, borderTopColor: colors.line,
    alignItems: 'center',
  },
  emptyCallout: {
    color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600',
    textAlign: 'center',
  },
  countBlock: { flex: 1, alignItems: 'center' },
  participantsCountText: {
    color: colors.textPrimary, fontSize: fontSizes.xs + 1, fontWeight: '700',
  },
  freeSlotsText: {
    color: colors.success, fontSize: fontSizes.xs, fontWeight: '500',
    marginTop: 1,
  },
  freeSlotsTextFull: { color: colors.error },
  viewAllBtn: {
    paddingHorizontal: spacing.sm + 2, paddingVertical: 6,
    borderRadius: radius.full,
    backgroundColor: colors.textSecondary + '26',
  },
  viewAllText: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600' },
  stackAvatarWrap: {
    borderRadius: 999, borderWidth: 2, borderColor: colors.surface,
  },
  extraBadge: {
    width: 26, height: 26, borderRadius: 13,
    backgroundColor: colors.surfaceAlt,
    borderWidth: 2, borderColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
  },
  extraBadgeText: { color: colors.textPrimary, fontSize: 10, fontWeight: '700' },
});
