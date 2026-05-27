import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { MapPin, Calendar, User } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type ProOffering } from '@/services/pro-offering-service';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ProOfferingCardProps {
  offering: ProOffering;
  onPress: () => void;
  distanceKm?: number;
}

// Compact card variant for the bottom-sheet drawer + the pro's
// Catalogue tab. Mirrors ActivityCard's left-bar + middle column +
// right slot rhythm so mixed lists read as one list, not two grafted
// surfaces. Differences from ActivityCard:
//   - Left bar always shows the sport-category accent (no time-status
//     concept — offerings are atemporal).
//   - Schedule_text replaces the date row when set.
//   - Right slot shows a small "PRO" pill instead of the participants
//     counter (offerings have no participants).
export function ProOfferingCard({ offering, onPress, distanceKm }: ProOfferingCardProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const accent = sportCategoryColor(offering.sport_category, colors.cta);

  return (
    <Pressable style={styles.row} onPress={onPress}>
      <View style={[styles.accentBar, { backgroundColor: accent }]} />

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
    alignItems: 'stretch',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    marginBottom: spacing.sm,
    overflow: 'hidden',
  },
  accentBar: { width: 4 },
  middleCol: { flex: 1, padding: spacing.sm, gap: 4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  sportRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  sportPill: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 2,
  },
  sport: { fontSize: fontSizes.xs, fontWeight: '700' },
  levelSep: { fontSize: fontSizes.xs },
  level: { fontSize: fontSizes.xs, fontWeight: '600' },
  metaRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginTop: 2 },
  metaItem: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  metaText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  proPill: {
    alignSelf: 'center',
    marginRight: spacing.sm,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 2,
    borderWidth: 1.5,
    borderRadius: radius.sm,
  },
  proPillText: { fontSize: fontSizes.xs - 1, fontWeight: '800', letterSpacing: 1 },
});
