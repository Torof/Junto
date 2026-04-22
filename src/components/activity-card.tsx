import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { getSportIcon } from '@/constants/sport-icons';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';

interface ActivityCardProps {
  activity: NearbyActivity;
  onPress: () => void;
  distanceKm?: number;
}

export function ActivityCard({ activity, onPress, distanceKm }: ActivityCardProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const joined = activity.participant_count;
  const isFull = remaining <= 0;

  const datePart = dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · HH:mm');
  const metaLine = [
    datePart,
    distanceKm !== undefined ? `${distanceKm.toFixed(1)} km` : null,
    activity.creator_name,
  ].filter(Boolean).join(' · ');

  return (
    <Pressable style={[styles.card, isFull && styles.cardFull]} onPress={onPress}>
      {/* Left: sport emoji */}
      <View style={styles.emojiCol}>
        <Text style={styles.emoji}>{getSportIcon(activity.sport_key)}</Text>
        <View style={[styles.statusDot, { backgroundColor: statusColor }]} />
      </View>

      {/* Middle: sport + level, title, meta */}
      <View style={styles.middleCol}>
        <View style={styles.sportRow}>
          <Text style={styles.sport} numberOfLines={1}>
            {t(`sports.${activity.sport_key}`, activity.sport_key)}
          </Text>
          {(() => {
            const signal = formatDifficultySignal(activity.sport_key, activity.level, activity.distance_km, activity.elevation_gain_m);
            if (!signal) return null;
            return (
              <>
                <Text style={styles.levelSep}> · </Text>
                <Text style={styles.level} numberOfLines={1}>{signal}</Text>
              </>
            );
          })()}
          {isFull && (
            <View style={styles.fullPill}>
              <Text style={styles.fullPillText}>{t('activity.full')}</Text>
            </View>
          )}
        </View>
        <Text style={styles.title} numberOfLines={1}>{activity.title}</Text>
        <Text style={styles.meta} numberOfLines={1}>{metaLine}</Text>
      </View>

      {/* Right: partants count */}
      <View style={styles.countCol}>
        <Text style={styles.countValue}>
          {joined}<Text style={styles.countMax}>/{activity.max_participants}</Text>
        </Text>
        <Text style={styles.countLabel}>{t('activity.partants')}</Text>
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
    gap: spacing.md,
  },
  cardFull: {
    opacity: 0.6,
  },
  emojiCol: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
  },
  emoji: {
    fontSize: 32,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  middleCol: {
    flex: 1,
    justifyContent: 'center',
    gap: 2,
  },
  sportRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    flexWrap: 'nowrap',
  },
  sport: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
    textTransform: 'capitalize',
    flexShrink: 0,
  },
  levelSep: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  level: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    flexShrink: 1,
  },
  fullPill: {
    backgroundColor: colors.error,
    borderRadius: radius.full,
    paddingHorizontal: spacing.xs,
    paddingVertical: 2,
    marginLeft: spacing.xs,
  },
  fullPillText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs - 2,
    fontWeight: 'bold',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
  meta: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  countCol: {
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 44,
  },
  countValue: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
  },
  countMax: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  countLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 1,
    textTransform: 'lowercase',
    marginTop: 1,
  },
});
