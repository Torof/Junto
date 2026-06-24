import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { MapPin, Calendar, ChevronRight } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type ProOffering } from '@/services/pro-offering-service';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ProOfferingPopupProps {
  offering: ProOffering;
  onPress: () => void;
}

// Pin-anchored tooltip for a pro offering. Same surface style as
// ActivityPopup / ProPopup so all three pin types speak the same
// visual language. Tap → opens /pro/offering/[id].
export function ProOfferingPopup({ offering, onPress }: ProOfferingPopupProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const accent = sportCategoryColor(offering.sport_category, colors.cta);

  return (
    <Pressable style={styles.card} onPress={onPress}>
      <Text style={styles.title} numberOfLines={2}>{offering.title}</Text>

      <View style={styles.chipsRow}>
        <View style={[styles.sportChip, { backgroundColor: accent + '40', borderColor: accent }]}>
          <Text style={[styles.sportChipText, { color: accent }]}>
            {t(`sports.${offering.sport_key}`, offering.sport_key)}
          </Text>
        </View>
        <View style={styles.proChip}>
          <Text style={styles.proChipText}>SORTIE PRO</Text>
        </View>
      </View>

      <View style={styles.row}>
        <MapPin size={12} color={colors.textPrimary} strokeWidth={2} />
        <Text style={styles.value} numberOfLines={1}>{offering.location_name}</Text>
      </View>

      {offering.schedule_text && (
        <View style={styles.row}>
          <Calendar size={12} color={colors.textPrimary} strokeWidth={2} />
          <Text style={styles.value} numberOfLines={1}>{offering.schedule_text}</Text>
        </View>
      )}

      <View style={styles.seeMore}>
        <Text style={styles.seeMoreText}>{t('map.seeMore')}</Text>
        <ChevronRight size={12} color={colors.cta} strokeWidth={2.5} />
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    elevation: 10,
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.25,
    shadowRadius: 14,
    borderWidth: 1.5,
    borderColor: colors.borderStrong,
    minWidth: 170,
    maxWidth: 240,
    gap: spacing.xs,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
    marginBottom: 2,
  },
  chipsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 2,
  },
  sportChip: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
    borderWidth: 1,
  },
  sportChipText: {
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  proChip: {
    backgroundColor: colors.cta + '33',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
  },
  proChipText: {
    color: colors.cta,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  value: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    flexShrink: 1,
  },
  seeMore: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 2,
    marginTop: 2,
  },
  seeMoreText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
});
