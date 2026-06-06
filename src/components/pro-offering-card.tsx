import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { MapPin, Calendar, User } from 'lucide-react-native';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type ProOffering } from '@/services/pro-offering-service';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ProOfferingCardProps {
  offering: ProOffering;
  onPress: () => void;
  distanceKm?: number;
}

// Mirrors ActivityCard's row anatomy so mixed drawer lists read as one
// surface: borderBottom row (no card surface), thin left status bar,
// middle column with title (Montserrat) + sport pill (uppercase) +
// meta row, outlined pill in the right slot. Differences from activity:
//   - Status bar always renders with the sport accent (offerings have
//     no time-status states, so the bar carries the sport identity
//     full-time instead of staying hidden).
//   - Right slot shows a "PRO" pill instead of the X/Y participants
//     counter (offerings have no participants concept).
export function ProOfferingCard({ offering, onPress, distanceKm }: ProOfferingCardProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const accent = sportCategoryColor(offering.sport_category, colors.cta);

  return (
    <Pressable style={styles.row} onPress={onPress}>
      <View style={[styles.statusBar, { backgroundColor: accent }]} />

      <View style={styles.middleCol}>
        <Text style={styles.title} numberOfLines={1}>{offering.title}</Text>
        <View style={styles.sportRow}>
          <View style={[styles.sportPill, { borderColor: accent }]}>
            <Text style={[styles.sport, { color: accent }]} numberOfLines={1}>
              {t(`sports.${offering.sport_key}`, offering.sport_key)}
            </Text>
            <Text style={[styles.levelSep, { color: accent }]}> · </Text>
            <Text style={[styles.level, { color: accent }]} numberOfLines={1}>{offering.level}</Text>
          </View>
        </View>
        <View style={styles.metaRow}>
          <View style={styles.metaItem}>
            <MapPin size={11} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.metaText} numberOfLines={1}>{offering.location_name}</Text>
          </View>
          {offering.schedule_text && (
            <View style={styles.metaItem}>
              <Calendar size={11} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.metaText} numberOfLines={1}>{offering.schedule_text}</Text>
            </View>
          )}
          {distanceKm !== undefined && (
            <View style={styles.metaItem}>
              <Text style={styles.metaText} numberOfLines={1}>· {distanceKm.toFixed(1)} km</Text>
            </View>
          )}
          {!offering.schedule_text && distanceKm === undefined && (
            <View style={[styles.metaItem, { flexShrink: 1 }]}>
              <User size={11} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.metaText} numberOfLines={1}>{offering.pro_name}</Text>
            </View>
          )}
        </View>
      </View>

      <View style={[styles.proPill, { borderColor: accent }]}>
        <Text style={[styles.proPillText, { color: accent }]}>PRO</Text>
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
  statusBar: {
    width: 3,
    alignSelf: 'stretch',
    marginRight: spacing.sm,
  },
  middleCol: {
    flex: 1,
    justifyContent: 'center',
    gap: 2,
    minWidth: 0,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontFamily: fonts.title,
    letterSpacing: -0.2,
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
    fontSize: fontSizes.xs - 1,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    flexShrink: 0,
  },
  levelSep: {
    fontSize: fontSizes.xs - 1,
  },
  level: {
    fontSize: fontSizes.xs - 1,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.4,
    flexShrink: 1,
  },
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
  proPill: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 3,
    backgroundColor: 'transparent',
  },
  proPillText: {
    fontSize: fontSizes.xs - 1,
    fontWeight: '800',
    letterSpacing: 1,
  },
});
