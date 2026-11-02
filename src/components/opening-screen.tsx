import { Image, StyleSheet, View } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppText } from '@/components/app-text';
import { Wordmark } from '@/components/wordmark';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing } from '@/constants/theme';

const mark = require('../../assets/askandgo_icon_square.png');

// The screen that takes over from the system splash while the app starts
// (auth, route, font). Same brand-blue ground and mark as the system splash —
// which Android 12+ limits to an icon — plus the wordmark under it (Scott
// 2026-11-02, variant « B »). No fade: the screen is up for a moment only.
export function OpeningScreen() {
  const colors = useColors();
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.container, { backgroundColor: colors.brand }]} pointerEvents="auto">
      <Image source={mark} style={styles.mark} />
      <Wordmark size={34} color={colors.onCta} andColor={colors.brandGreenOnBlue} />
      <AppText style={[styles.foot, { color: colors.onCta, bottom: insets.bottom + spacing.xl }]}>
        {t('visitor.explore')}
      </AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
  },
  mark: { width: 150, height: 150, marginBottom: spacing.xs },
  foot: {
    position: 'absolute',
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    opacity: 0.8,
  },
});
