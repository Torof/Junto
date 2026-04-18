import { useEffect, useRef } from 'react';
import { View, Animated, StyleSheet } from 'react-native';
import { colors, spacing, radius } from '@/constants/theme';

function Bone({ width, height, style }: { width: number | `${number}%`; height: number; style?: object }) {
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
        { width, height, borderRadius: 4, backgroundColor: colors.surface, opacity },
        style,
      ]}
    />
  );
}

export function ProfileSkeleton() {
  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {/* Hero row: avatar ring + stats card */}
        <View style={styles.heroRow}>
          {/* Circular avatar placeholder */}
          <Bone width={110} height={110} style={{ borderRadius: 55 }} />

          {/* Stats column */}
          <View style={styles.statsColumn}>
            {/* Stats card title */}
            <Bone width={70} height={10} style={{ alignSelf: 'center', marginBottom: spacing.xs }} />
            {/* Stats card */}
            <View style={styles.statsCard}>
              <View style={styles.statsRow}>
                <View style={styles.stat}>
                  <Bone width={24} height={18} style={{ marginBottom: 4 }} />
                  <Bone width={44} height={10} />
                </View>
                <View style={styles.statDivider} />
                <View style={styles.stat}>
                  <Bone width={24} height={18} style={{ marginBottom: 4 }} />
                  <Bone width={40} height={10} />
                </View>
                <View style={styles.statDivider} />
                <View style={styles.stat}>
                  <Bone width={24} height={18} style={{ marginBottom: 4 }} />
                  <Bone width={36} height={10} />
                </View>
              </View>
            </View>
            {/* Member since */}
            <Bone width={100} height={9} style={{ alignSelf: 'center', marginTop: spacing.xs }} />
          </View>
        </View>

        {/* Sport icon grid section */}
        <View style={styles.section}>
          <Bone width={80} height={10} style={{ marginBottom: spacing.sm }} />
          <View style={styles.sportGrid}>
            {[0, 1, 2, 3, 4, 5].map((i) => (
              <Bone key={i} width={48} height={48} style={{ borderRadius: radius.md }} />
            ))}
          </View>
        </View>

        {/* Badges section */}
        <View style={styles.section}>
          <Bone width={60} height={10} style={{ marginBottom: spacing.md }} />
          <View style={styles.badgeRow}>
            {[0, 1, 2].map((i) => (
              <Bone key={i} width={56} height={56} style={{ borderRadius: 28 }} />
            ))}
          </View>
        </View>
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
  heroRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    marginBottom: spacing.xl,
  },
  statsColumn: {
    flex: 1,
    justifyContent: 'center',
    gap: spacing.sm,
  },
  statsCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
  },
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  stat: { alignItems: 'center', flex: 1 },
  statDivider: { width: 1, height: 28, backgroundColor: colors.textSecondary, opacity: 0.2 },
  section: {
    marginBottom: spacing.lg,
  },
  sportGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  badgeRow: {
    flexDirection: 'row',
    gap: spacing.md,
  },
});
