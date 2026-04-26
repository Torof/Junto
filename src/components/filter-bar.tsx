import { useEffect, useMemo, useRef } from 'react';
import { Animated, View, Pressable, StyleSheet } from 'react-native';
import { SlidersHorizontal } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore } from '@/store/map-store';
import type { AppColors } from '@/constants/colors';

interface Props {
  onPress: () => void;
  blink?: boolean;
}

export function FilterButton({ onPress, blink = false }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const { filters } = useMapStore();
  const hasActiveFilter =
    filters.sportKeys.length > 0
    || filters.dateMode !== 'all'
    || filters.levelTiers.length > 0
    || filters.visibilities.length > 0;
  const styles = useMemo(() => createStyles(colors), [colors]);
  const scale = useRef(new Animated.Value(1)).current;
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (!blink) {
      scale.setValue(1);
      opacity.setValue(1);
      return;
    }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.parallel([
          Animated.timing(scale, { toValue: 1.25, duration: 450, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 0.6, duration: 450, useNativeDriver: true }),
        ]),
        Animated.parallel([
          Animated.timing(scale, { toValue: 1, duration: 450, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 1, duration: 450, useNativeDriver: true }),
        ]),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [blink, scale, opacity]);

  return (
    <Animated.View style={[styles.wrapper, { transform: [{ scale }], opacity }]}>
      <Pressable style={styles.button} onPress={onPress} hitSlop={8} accessibilityLabel={t('map.openFilters')}>
        <SlidersHorizontal size={22} color={colors.textPrimary} strokeWidth={2.2} />
        {hasActiveFilter && <View style={styles.badge} />}
      </Pressable>
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrapper: {
    position: 'absolute',
    bottom: 120,
    right: spacing.md,
    zIndex: 10,
  },
  button: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
  },
  badge: {
    position: 'absolute',
    top: 6,
    right: 6,
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.cta,
  },
});
