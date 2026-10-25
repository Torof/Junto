import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { MapPin, Calendar, Star } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { PRO_GOLD, PRO_GOLD_INK } from '@/constants/pin-style';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type ProOffering } from '@/services/pro-offering-service';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { SportIcon } from '@/components/sport-icon';

interface ProOfferingCardProps {
  offering: ProOffering;
  onPress: () => void;
  distanceKm?: number;
  // When true, renders a CTA-color tint to mark the link between this
  // card and the highlighted pin on the map. Tap-to-peek pattern.
  isHighlighted?: boolean;
}

// Shares the borderless-row anatomy with ActivityCard so the mixed
// drawer list reads as a single surface. Same title weight, same
// sport-pill style, same meta layout. Only the right slot differs —
// a "PRO" pill replaces the participant counter (offerings have no
// participants concept).
//
// Offerings have no time-status equivalent, so the left status bar
// stays transparent (just keeps the horizontal alignment consistent
// with activity rows).
export function ProOfferingCard({ offering, onPress, distanceKm, isHighlighted = false }: ProOfferingCardProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const accent = sportCategoryColor(offering.sport_category, colors.cta);

  return (
    <Pressable
      style={[styles.row, isHighlighted && { backgroundColor: colors.cta + '1F' }]}
      onPress={onPress}
    >
      {/* Reserved 3px left slot kept transparent so the row aligns with
          ActivityCard rows that conditionally show a status bar here. */}
      <View style={styles.statusBar} />

      <View style={styles.middleCol}>
        <AppText style={styles.title} numberOfLines={1}>{offering.title}</AppText>
        <View style={styles.sportRow}>
          <View style={[styles.sportPill, { borderColor: accent }]}>
            <SportIcon sportKey={offering.sport_key} size={12} color={accent} />
            <AppText style={[styles.sport, { color: accent }]} numberOfLines={1}>
              {t(`sports.${offering.sport_key}`, offering.sport_key)}
            </AppText>
            <AppText style={[styles.levelSep, { color: accent }]}> · </AppText>
            <AppText style={[styles.level, { color: accent }]} numberOfLines={1}>{offering.level}</AppText>
          </View>
        </View>
        {/* Meta stacked vertically — each piece on its own row so the
            often-long schedule_text ("Tous les samedis 9h-17h") never
            gets truncated. Distance, when present, inlines with the
            location since both are short. */}
        <View style={styles.metaList}>
          <View style={styles.metaItem}>
            <MapPin size={11} color={colors.textSecondary} strokeWidth={2.4} />
            <AppText style={styles.metaText} numberOfLines={1}>
              {offering.location_name}
              {distanceKm !== undefined ? ` · ${distanceKm.toFixed(1)} km` : ''}
            </AppText>
          </View>
          {offering.schedule_text && (
            <View style={styles.metaItem}>
              <Calendar size={11} color={colors.textSecondary} strokeWidth={2.4} />
              <AppText style={styles.metaText} numberOfLines={1}>{offering.schedule_text}</AppText>
            </View>
          )}
        </View>
      </View>

      <View style={styles.rightCol}>
        {offering.avg_rating != null && (offering.review_count ?? 0) > 0 ? (
          <View style={styles.ratingRow}>
            <Star size={11} color={colors.star} fill={colors.star} strokeWidth={0} />
            <AppText style={styles.ratingText}>{Number(offering.avg_rating).toFixed(1)}</AppText>
            <AppText style={styles.ratingCount}>({offering.review_count})</AppText>
          </View>
        ) : null}
        <View style={styles.proBadge}>
          <AppText style={styles.proBadgeText}>PRO</AppText>
        </View>
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
  statusBar: {
    width: 3,
    alignSelf: 'stretch',
    marginRight: spacing.sm,
    backgroundColor: 'transparent',
  },
  middleCol: {
    flex: 1,
    justifyContent: 'center',
    gap: 4,
    minWidth: 0,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
  },
  sportRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flexWrap: 'nowrap',
  },
  sportPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: 1,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 1,
    backgroundColor: 'transparent',
    alignSelf: 'flex-start',
    flexShrink: 1,
    minWidth: 0,
  },
  sport: { fontSize: fontSizes.xs, fontWeight: '700', flexShrink: 0 },
  levelSep: { fontSize: fontSizes.xs },
  level: { fontSize: fontSizes.xs, fontWeight: '600', flexShrink: 1 },
  metaList: {
    marginTop: 2,
    gap: 2,
  },
  metaItem: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  metaText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '500' },
  // One unified pro badge — gold, ink text (the pro colour, 2026-10-25), a
  // circle rather than a per-sport pill.
  rightCol: { alignSelf: 'stretch', alignItems: 'flex-end', justifyContent: 'flex-start', gap: 5, paddingTop: 2 },
  ratingRow: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  ratingText: { color: colors.textPrimary, fontSize: fontSizes.xs + 1, fontWeight: '800' },
  ratingCount: { color: colors.textMuted, fontSize: fontSizes.xs - 1, fontWeight: '600' },
  proBadge: {
    width: 34,
    height: 34,
    borderRadius: radius.full,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: PRO_GOLD,
  },
  proBadgeText: { color: PRO_GOLD_INK, fontSize: fontSizes.xs - 1, fontWeight: '800', letterSpacing: 0.5 },
});
