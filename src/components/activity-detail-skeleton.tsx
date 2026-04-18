import { useEffect, useRef } from 'react';
import { View, Animated, StyleSheet } from 'react-native';
import { colors, spacing, radius, fontSizes } from '@/constants/theme';

function Bone({ width, height, style }: { width: number | string; height: number; style?: object }) {
  const opacity = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.6, duration: 800, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.3, duration: 800, useNativeDriver: true }),
      ]),
    );
    anim.start();
    return () => anim.stop();
  }, [opacity]);

  return (
    <Animated.View
      style={[
        { width: width as number, height, borderRadius: 4, backgroundColor: colors.surface, opacity },
        style,
      ]}
    />
  );
}

export function ActivityDetailSkeleton() {
  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {/* Header: sport icon + sport name + visibility */}
        <View style={styles.headerRow}>
          <Bone width={24} height={24} style={{ borderRadius: 12 }} />
          <Bone width={90} height={14} />
          <View style={{ marginLeft: 'auto' }}>
            <Bone width={70} height={22} style={{ borderRadius: 11 }} />
          </View>
        </View>

        {/* Title */}
        <Bone width="70%" height={22} style={{ marginBottom: spacing.md }} />

        {/* Info grid: 4 rows */}
        <View style={styles.infoGrid}>
          {[1, 2, 3, 4].map((i) => (
            <View key={i} style={styles.infoRow}>
              <Bone width={100} height={13} />
              <Bone width={80} height={13} />
            </View>
          ))}
        </View>

        {/* Description placeholder */}
        <Bone width="100%" height={12} style={{ marginTop: spacing.lg, marginBottom: 6 }} />
        <Bone width="85%" height={12} style={{ marginBottom: 6 }} />
        <Bone width="60%" height={12} />

        {/* Creator row */}
        <View style={styles.creatorRow}>
          <Bone width={36} height={36} style={{ borderRadius: 18 }} />
          <View style={{ gap: 4 }}>
            <Bone width={100} height={12} />
            <Bone width={60} height={10} />
          </View>
        </View>

        {/* Map placeholder */}
        <Bone width="100%" height={160} style={{ borderRadius: radius.md, marginTop: spacing.md }} />

        {/* Join button */}
        <Bone width="100%" height={44} style={{ borderRadius: radius.md, marginTop: spacing.lg }} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
    paddingBottom: spacing.xl + 32,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  infoGrid: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    gap: spacing.sm,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  creatorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginTop: spacing.lg,
  },
});
