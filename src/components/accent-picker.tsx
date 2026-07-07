import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Check } from 'lucide-react-native';
import { spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useThemeStore } from '@/store/theme-store';
import { ACCENTS, DEFAULT_ACCENT_HEX } from '@/constants/accents';

// A row of accent swatches. Tapping one overrides the app's `cta` token live
// (persisted). The active swatch (the current override, or the default when
// none is set) carries a white check. Names are surfaced to screen readers.
export function AccentPicker() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const accent = useThemeStore((s) => s.accent);
  const setAccent = useThemeStore((s) => s.setAccent);

  const effective = (accent ?? DEFAULT_ACCENT_HEX).toLowerCase();

  return (
    <View style={styles.row}>
      {ACCENTS.map((a) => {
        const active = a.hex.toLowerCase() === effective;
        return (
          <Pressable
            key={a.key}
            onPress={() => setAccent(a.hex)}
            hitSlop={6}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            accessibilityLabel={t(`drawer.accentOption.${a.key}`)}
            style={[styles.swatch, { backgroundColor: a.hex }, active && styles.swatchActive]}
          >
            {active && <Check size={16} color="#FFFFFF" strokeWidth={3} />}
          </Pressable>
        );
      })}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  row: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    paddingLeft: spacing.lg,
    paddingTop: spacing.xs,
    paddingBottom: spacing.sm,
  },
  swatch: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.borderMuted,
  },
  swatchActive: {
    borderColor: colors.textPrimary,
    borderWidth: 3,
  },
});
