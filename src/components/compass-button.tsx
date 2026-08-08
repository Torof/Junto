import { useMemo } from 'react';
import { Pressable, View, StyleSheet } from 'react-native';
import { Navigation } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  heading: number; // map bearing in degrees
  onPress: () => void; // reset to north
}

// Custom compass — styled to match the recenter / create buttons (native Mapbox
// compass is black + unstylable, off against the palette). The needle rotates to
// keep pointing at true north; tapping snaps the map back to north.
export function CompassButton({ heading, onPress }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Pressable style={styles.button} onPress={onPress} hitSlop={8} accessibilityLabel={t('map.north', { defaultValue: 'Nord' })}>
      <View style={{ transform: [{ rotate: `${-heading}deg` }] }}>
        <Navigation size={20} color={colors.cta} fill={colors.cta} strokeWidth={1.5} />
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Bottom-right, just above the recenter button — same round chip as the
  // recenter / create pair so the three read as one uniform stack.
  button: {
    position: 'absolute',
    bottom: 28 + 48 + 14 + 48 + 14,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 48,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
});
