import { useMemo } from 'react';
import { View, Text, Image, Pressable, StyleSheet } from 'react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyPro } from '@/services/pro-service';

interface ProPopupProps {
  pro: NearbyPro;
  onPress: () => void;
}

// Pin-anchored tooltip for the pro storefront pin. Same surface style
// + chip pattern as ActivityPopup so the three pin types speak the
// same visual language. Tap → opens /pro/[id].
export function ProPopup({ pro, onPress }: ProPopupProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const initial = (pro.display_name?.trim().charAt(0) ?? '?').toUpperCase();

  return (
    <Pressable style={styles.card} onPress={onPress}>
      <View style={styles.headerRow}>
        {pro.pin_image_url ? (
          <Image source={{ uri: pro.pin_image_url }} style={styles.thumb} />
        ) : (
          <View style={[styles.thumb, styles.thumbPlaceholder]}>
            <Text style={styles.thumbInitial}>{initial}</Text>
          </View>
        )}
        <View style={styles.headerBody}>
          <View style={styles.kickerChip}>
            <Text style={styles.kickerChipText}>PRO</Text>
          </View>
          <Text style={styles.title} numberOfLines={1}>{pro.display_name}</Text>
        </View>
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
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  thumb: {
    width: 36,
    height: 36,
    borderRadius: radius.sm,
    backgroundColor: colors.background,
  },
  thumbPlaceholder: {
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  thumbInitial: { color: '#FFFFFF', fontSize: 16, fontWeight: '800' },
  headerBody: { flex: 1, gap: 2 },
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
  },
});
