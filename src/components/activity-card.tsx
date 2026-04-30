import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, MapPin, User } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { getSportIcon } from '@/constants/sport-icons';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ActivityCardProps {
  activity: NearbyActivity;
  onPress: () => void;
  distanceKm?: number;
  showCreator?: boolean;
}

export function ActivityCard({ activity, onPress, distanceKm, showCreator = true }: ActivityCardProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const joined = activity.participant_count;
  const isFull = remaining <= 0;
  const sportAccent = sportCategoryColor(activity.sport_category, colors.cta);

  const datePart = dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm');

  return (
    <Pressable style={[styles.card, isFull && styles.cardFull]} onPress={onPress}>
      {/* Left: sport emoji in circle, status dot half on the border */}
      <View style={styles.avatarWrap}>
        <View style={styles.avatarCircle}>
          <Text style={styles.emoji}>{getSportIcon(activity.sport_key)}</Text>
        </View>
        <View style={[styles.statusDot, { backgroundColor: statusColor }]} />
      </View>

      {/* Middle: sport + level, title, meta */}
      <View style={styles.middleCol}>
        <View style={styles.sportRow}>
          <Text style={[styles.sport, { color: sportAccent }]} numberOfLines={1}>
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
        <View style={styles.metaRow}>
          <View style={styles.metaItem}>
            <Calendar size={11} color={colors.cta} strokeWidth={2.4} />
            <Text style={styles.metaDate} numberOfLines={1}>{datePart}</Text>
          </View>
          {distanceKm !== undefined && (
            <View style={styles.metaItem}>
              <MapPin size={11} color={colors.pinMeeting} strokeWidth={2.4} />
              <Text style={styles.metaSecondary} numberOfLines={1}>{distanceKm.toFixed(1)} km</Text>
            </View>
          )}
          {showCreator && (
            <View style={[styles.metaItem, { flexShrink: 1 }]}>
              <User size={11} color={colors.pinStart} strokeWidth={2.4} />
              <Text style={styles.metaSecondary} numberOfLines={1}>{activity.creator_name}</Text>
            </View>
          )}
        </View>
      </View>

      {/* Right: partants count */}
      <View style={styles.countCol}>
        <Text style={styles.countValue}>
          {joined}{activity.max_participants !== null && (<Text style={styles.countMax}>/{activity.max_participants}</Text>)}
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
    borderWidth: 1,
    borderColor: colors.line,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md + 4,
    marginBottom: spacing.sm,
    gap: spacing.md,
  },
  cardFull: {
    opacity: 0.6,
  },
  avatarWrap: {
    width: 44,
    height: 44,
    position: 'relative',
  },
  avatarCircle: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.surfaceAlt,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emoji: {
    fontSize: 22,
  },
  statusDot: {
    position: 'absolute',
    bottom: -1,
    right: -1,
    width: 14,
    height: 14,
    borderRadius: 7,
    borderWidth: 2,
    borderColor: colors.surface,
  },
  middleCol: {
    flex: 1,
    justifyContent: 'center',
    gap: 5,
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
    fontSize: fontSizes.lg,
    fontWeight: '800',
    letterSpacing: -0.3,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'nowrap',
    gap: spacing.sm,
    marginTop: 2,
  },
  metaItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    flexShrink: 0,
  },
  metaDate: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  metaSecondary: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
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
