import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { MapPin, Calendar } from 'lucide-react-native';
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
        <View style={[styles.sportChip, { backgroundColor: accent + '1F' }]}>
          <Text style={[styles.sportChipText, { color: accent }]}>
            {t(`sports.${offering.sport_key}`, offering.sport_key)}
          </Text>
        </View>
        <View style={styles.proChip}>
          <Text style={styles.proChipText}>PRO</Text>
        </View>
      </View>

      <View style={styles.row}>
        <MapPin size={12} color={colors.textSecondary} strokeWidth={2} />
        <Text style={styles.value} numberOfLines={1}>{offering.location_name}</Text>
      </View>

      {offering.schedule_text && (
        <View style={styles.row}>
          <Calendar size={12} color={colors.textSecondary} strokeWidth={2} />
          <Text style={styles.value} numberOfLines={1}>{offering.schedule_text}</Text>
        </View>
      )}
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    elevation: 8,
    shadowColor: colors.background,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 6,
    borderWidth: 1,
    borderColor: colors.border,
    minWidth: 170,
    maxWidth: 240,
    gap: spacing.xs,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
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
  },
  sportChipText: {
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  proChip: {
    backgroundColor: colors.cta + '1F',
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
    flexShrink: 1,
  },
});
