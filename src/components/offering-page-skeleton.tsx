import { useMemo } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Bone } from '@/components/skeleton-bone';
import { CloseButton, createStyles } from '@/components/pro-page-skeleton';
import { useColors } from '@/hooks/use-theme';
import { spacing, radius } from '@/constants/theme';

// The outing page's shape while it loads (OfferingPage): cover with the sport
// chip, title and price, the « par » strip, the 2 × 2 facts and « À propos ».

const COVER_H = 250;

export function OfferingPageSkeleton() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  const top = Math.max(10, insets.top - 14);
  return (
    <View style={styles.container}>
      <View style={[styles.cover, { height: COVER_H }]}>
        <Bone width={96} height={26} style={[styles.onCover, { position: 'absolute', left: 12, top: top + 4, borderRadius: radius.full }]} />
        <CloseButton top={top} styles={styles} colors={colors} />
        <View style={{ position: 'absolute', left: 18, right: 18, bottom: 14, flexDirection: 'row', alignItems: 'flex-end', gap: 12 }}>
          <View style={{ flex: 1, gap: 8 }}>
            <Bone width="85%" height={22} style={styles.onCover} />
            <Bone width="55%" height={22} style={styles.onCover} />
          </View>
          <View style={{ alignItems: 'flex-end', gap: 6 }}>
            <Bone width={118} height={22} style={[styles.onCover, { borderRadius: radius.full }]} />
            <Bone width={84} height={28} style={[styles.onCover, { borderRadius: radius.full }]} />
          </View>
        </View>
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginHorizontal: spacing.md, marginTop: spacing.sm + 4 }}>
        <Bone width={36} height={36} style={{ borderRadius: 18 }} />
        <View style={{ flex: 1, gap: 6 }}>
          <Bone width="50%" height={14} />
          <Bone width="70%" height={12} />
        </View>
      </View>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginHorizontal: spacing.md, marginTop: spacing.sm + 4 }}>
        {[0, 1, 2, 3].map((i) => <Bone key={i} width="48.5%" height={58} style={{ borderRadius: 14 }} />)}
      </View>
      <Bone width={120} height={18} style={styles.heading} />
      <View style={{ marginHorizontal: spacing.md + 2, gap: 8 }}>
        <Bone width="100%" height={14} />
        <Bone width="92%" height={14} />
        <Bone width="60%" height={14} />
      </View>
    </View>
  );
}
