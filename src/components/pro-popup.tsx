import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { ChevronRight } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyPro } from '@/services/pro-service';

interface ProPopupProps {
  pro: NearbyPro;
  onPress: () => void;
}

// Pin-anchored tooltip for the pro storefront pin. Drops the
// thumbnail (the pin itself already carries the photo) and replaces
// it with the "à propos" excerpt so the popup actually adds info
// beyond what the pin shows. Tap → opens /pro/[id].
export function ProPopup({ pro, onPress }: ProPopupProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Pressable style={styles.card} onPress={onPress}>
      <View style={styles.kickerChip}>
        <Text style={styles.kickerChipText}>PAGE PRO</Text>
      </View>
      <Text style={styles.title} numberOfLines={1}>{pro.display_name}</Text>
      {pro.description && (
        <Text style={styles.about} numberOfLines={3}>{pro.description}</Text>
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
    elevation: 8,
    shadowColor: colors.background,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 6,
    borderWidth: 1,
    borderColor: colors.border,
    minWidth: 170,
    maxWidth: 240,
    gap: 4,
  },
  kickerChip: {
    alignSelf: 'flex-start',
    backgroundColor: colors.cta + '1F',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
  },
  kickerChipText: {
    color: colors.cta,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
    marginTop: 2,
  },
  about: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    lineHeight: 16,
    marginTop: 2,
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
