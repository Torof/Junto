import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, MapPin, User, Users, Lock } from 'lucide-react-native';
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
  // When provided and the viewer created this activity, the creator meta
  // becomes an "Organisateur" tag instead of their own name.
  currentUserId?: string | null;
  // When true, renders a CTA-color outline to mark the link between
  // this card and the highlighted pin on the map. Tap-to-peek pattern:
  // first tap → highlight + fly to pin; second tap → open detail page.
  isHighlighted?: boolean;
}

const ATTENTION_STATES: ReadonlySet<ActivityTimeStatus> = new Set(['in_progress', 'soon', 'cancelled']);

export function ActivityCard({ activity, onPress, distanceKm, showCreator = true, currentUserId, isHighlighted = false }: ActivityCardProps) {
  const isMine = !!currentUserId && activity.creator_id === currentUserId;
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
    <Pressable
      style={[
        styles.row,
        isFull && styles.rowFull,
        isHighlighted && { backgroundColor: colors.cta + '1F' },
      ]}
      onPress={onPress}
    >
      <View style={[styles.statusBar, !showStatusBar && styles.statusBarHidden, showStatusBar && { backgroundColor: statusColor }]} />

      <View style={styles.middleCol}>
        <View style={styles.titleRow}>
          {/* Private outing — same padlock vocabulary as the map pin
              (00315): only members ever see these rows/pins. */}
          {(activity.visibility === 'private_link' || activity.visibility === 'private_link_approval') && (
            <Lock size={13} color={colors.textSecondary} strokeWidth={2.6} />
          )}
          <Text style={styles.title} numberOfLines={1}>{activity.title}</Text>
        </View>
        <View style={styles.sportRow}>
          <View style={[styles.sportPill, { borderColor: sportAccent }]}>
            <Text style={[styles.sport, { color: sportAccent }]} numberOfLines={1}>
              {t(`sports.${activity.sport_key}`, activity.sport_key)}
            </Text>
            {(() => {
              const signal = formatDifficultySignal(activity.sport_key, activity.level, activity.distance_km, activity.elevation_gain_m, activity.level_max);
              if (!signal) return null;
              return (
                <>
                  <Text style={[styles.levelSep, { color: sportAccent }]}> · </Text>
                  <Text style={[styles.level, { color: sportAccent }]} numberOfLines={1}>{signal}</Text>
                </>
              );
            })()}
          </View>
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
              <User size={11} color={isMine ? colors.cta : colors.textSecondary} strokeWidth={2.4} />
              {isMine ? (
                <Text style={styles.organizerTag} numberOfLines={1}>
                  {t('myActivities.organizer', { defaultValue: 'Organisateur' })}
                </Text>
              ) : (
                <Text style={styles.metaText} numberOfLines={1}>
                  {t('activity.by', { defaultValue: 'par' })} {activity.creator_name}
                </Text>
              )}
            </View>
          )}
        </View>
      </View>

      <View style={styles.countPill}>
        <Users size={14} color={colors.textPrimary} strokeWidth={2.4} />
        <Text style={styles.countValue}>
          {joined}{activity.max_participants !== null && (<Text style={styles.countMax}>/{activity.max_participants}</Text>)}
        </Text>
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm + 2,
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
    gap: 4,
    minWidth: 0,
  },
  // Title — fontWeight 700 in the default font; less shouty than
  // Montserrat-title, reads cleaner in a dense list.
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
    flexShrink: 1,
  },
  // Sport row — outlined pill (border only, no fill) with category-
  // colored border + text. Carries the pre-attentive 'what sport'
  // signal as a self-contained badge.
  sportRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flexWrap: 'nowrap',
  },
  sportPill: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 1,
    backgroundColor: 'transparent',
    alignSelf: 'flex-start',
    flexShrink: 1,
    minWidth: 0,
  },
  sport: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    flexShrink: 0,
  },
  levelSep: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  level: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
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
    marginTop: 2,
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
  organizerTag: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '800',
  },
  // Participant count pill — outlined rectangle with a Users icon
  // and the X/Y count inline. Replaces the previous two-line
  // 'value + partants' column.
  countPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 3,
    backgroundColor: 'transparent',
  },
  countValue: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
  countMax: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
});
