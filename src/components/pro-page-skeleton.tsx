import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { X } from 'lucide-react-native';
import { Bone } from '@/components/skeleton-bone';
import { useColors } from '@/hooks/use-theme';
import { spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

// The pro page's shape while it loads (ProPage): cover with the left-aligned
// identity block at its foot, contact chips, two outing cards and the banner. The
// close button is real, so a slow load can always be left.

const COVER_H = 292;

export function ProPageSkeleton() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  return (
    <View style={styles.container}>
      <View style={styles.cover}>
        <CloseButton top={Math.max(10, insets.top - 14)} styles={styles} colors={colors} />
        <View style={[styles.coverFoot, { bottom: 14, gap: 8 }]}>
          <Bone width="62%" height={22} style={styles.onCover} />
          <Bone width="44%" height={13} style={styles.onCover} />
          <Bone width="30%" height={13} style={styles.onCover} />
          <View style={styles.row}>
            {[78, 86, 72].map((w, i) => <Bone key={i} width={w} height={22} style={[styles.onCover, { borderRadius: radius.full }]} />)}
          </View>
          <Bone width={80} height={13} style={styles.onCover} />
        </View>
      </View>
      <View style={[styles.row, styles.chips]}>
        {[92, 76, 96, 92].map((w, i) => <Bone key={i} width={w} height={36} style={{ borderRadius: radius.full }} />)}
      </View>
      <Bone width={170} height={18} style={styles.heading} />
      <Bone width="auto" height={116} style={styles.card} />
      <Bone width="auto" height={116} style={styles.card} />
      <Bone width="auto" height={46} style={[styles.card, { borderRadius: radius.full }]} />
    </View>
  );
}

export function CloseButton({ top, styles, colors }: { top: number; styles: ReturnType<typeof createStyles>; colors: AppColors }) {
  const router = useRouter();
  const { t } = useTranslation();
  return (
    <Pressable style={[styles.close, { top }]} onPress={() => router.back()} hitSlop={6} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
      <X size={18} color={colors.textPrimary} strokeWidth={2.6} />
    </Pressable>
  );
}

export const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  cover: { height: COVER_H, backgroundColor: colors.surfaceAlt },
  // Bones on the grey cover read one step darker.
  onCover: { backgroundColor: colors.borderMuted },
  coverFoot: { position: 'absolute', left: 18, right: 18 },
  close: { position: 'absolute', right: 12, width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.92)', alignItems: 'center', justifyContent: 'center', zIndex: 2 },
  row: { flexDirection: 'row', gap: 6 },
  chips: { gap: 8, paddingHorizontal: spacing.md, paddingTop: spacing.sm + 4, overflow: 'hidden' },
  heading: { marginHorizontal: spacing.md + 2, marginTop: spacing.lg + 2, marginBottom: spacing.sm + 2 },
  card: { marginHorizontal: spacing.md, marginBottom: spacing.sm + 2, borderRadius: 18 },
});
