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
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces, type ActivityTimeStatus } from '@/utils/activity-status';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ActivityCardProps {
  activity: NearbyActivity;
  onPress: () => void;
  distanceKm?: number;
  showCreator?: boolean;
}

const ATTENTION_STATES: ReadonlySet<ActivityTimeStatus> = new Set(['in_progress', 'soon', 'cancelled']);

export function ActivityCard({ activity, onPress, distanceKm, showCreator = true }: ActivityCardProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const showStatusBar = ATTENTION_STATES.has(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const joined = activity.participant_count;
  const isFull = remaining <= 0;
  const sportAccent = sportCategoryColor(activity.sport_category, colors.cta);

  const datePart = dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm');

  return (
    <Pressable style={[styles.row, isFull && styles.rowFull]} onPress={onPress}>
      <View style={[styles.statusBar, !showStatusBar && styles.statusBarHidden, showStatusBar && { backgroundColor: statusColor }]} />

      <View style={styles.middleCol}>
        <Text style={[styles.title, { color: sportAccent }]} numberOfLines={1}>{activity.title}</Text>
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
        <View style={styles.metaRow}>
          <View style={styles.metaItem}>
            <Calendar size={11} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.metaText} numberOfLines={1}>{datePart}</Text>
          </View>
          {distanceKm !== undefined && (
            <View style={styles.metaItem}>
              <MapPin size={11} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.metaText} numberOfLines={1}>{distanceKm.toFixed(1)} km</Text>
            </View>
          )}
          {showCreator && (
            <View style={[styles.metaItem, { flexShrink: 1 }]}>
              <User size={11} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.metaText} numberOfLines={1}>{activity.creator_name}</Text>
            </View>
          )}
        </View>
      </View>

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
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    paddingRight: spacing.md,
    gap: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  rowFull: {
    opacity: 0.55,
  },
  statusBar: {
    width: 3,
    alignSelf: 'stretch',
    marginRight: spacing.sm,
  },
  statusBarHidden: {
    backgroundColor: 'transparent',
  },
  middleCol: {
    flex: 1,
    justifyContent: 'center',
    gap: 2,
    minWidth: 0,
  },
  // Title — the unique row anchor + category signal in one element.
  // Sport-category-colored, bold, single line, truncated.
  title: {
    fontSize: fontSizes.md,
    fontWeight: '700',
    letterSpacing: -0.2,
  },
  // Sport + level subtitle — quiet textSecondary now that the title
  // carries the category color. Tiny uppercase tag-row.
  sportRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    flexWrap: 'nowrap',
  },
  sport: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 1,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    flexShrink: 0,
  },
  levelSep: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 1,
  },
  level: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 1,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    flexShrink: 1,
  },
  fullPill: {
    backgroundColor: colors.error,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.xs,
    paddingVertical: 1,
    marginLeft: spacing.xs,
  },
  fullPillText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs - 2,
    fontWeight: 'bold',
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  },
  // Meta row — date / distance / creator. Quiet textSecondary so
  // the title can dominate. Icons match the text color (no longer
  // semantic-colored per-icon).
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'nowrap',
    gap: spacing.sm,
    marginTop: 1,
  },
  metaItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    flexShrink: 0,
  },
  metaText: {
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
