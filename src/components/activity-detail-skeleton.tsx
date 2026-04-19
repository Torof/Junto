import { useEffect, useMemo, useRef } from 'react';
import { View, Animated, StyleSheet } from 'react-native';
import { spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

function Bone({ width, height, style }: { width: number | `${number}%`; height: number; style?: object }) {
  const colors = useColors();
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

export function ActivityDetailSkeleton() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {/* Header: sport emoji + sport name + visibility pill */}
        <View style={styles.header}>
          <Bone width={20} height={20} style={{ borderRadius: 10 }} />
          <Bone width={80} height={14} />
          <View style={{ flex: 1 }} />
          <Bone width={75} height={24} style={{ borderRadius: 12 }} />
        </View>

        {/* Title */}
        <Bone width="65%" height={24} style={{ marginBottom: spacing.md }} />

        {/* Info grid — surface card with 4 rows */}
        <View style={styles.infoGrid}>
          {[120, 90, 70, 110].map((labelW, i) => (
            <View key={i} style={styles.infoRow}>
              <Bone width={labelW} height={14} />
              <Bone width={i === 1 ? 130 : 80} height={14} />
            </View>
          ))}
        </View>

        {/* Description section */}
        <View style={styles.section}>
          <Bone width={100} height={10} style={{ marginBottom: spacing.sm }} />
          <Bone width="100%" height={14} style={{ marginBottom: 6 }} />
          <Bone width="90%" height={14} style={{ marginBottom: 6 }} />
          <Bone width="55%" height={14} />
        </View>

        {/* Map section */}
        <View style={styles.section}>
          <Bone width={110} height={10} style={{ marginBottom: spacing.sm }} />
          <Bone width="100%" height={200} style={{ borderRadius: radius.lg }} />
        </View>

        {/* Participants — creator row + 2 avatars */}
        <View style={styles.section}>
          <Bone width={100} height={10} style={{ marginBottom: spacing.sm }} />
          <View style={styles.participantRow}>
            <Bone width={36} height={36} style={{ borderRadius: 18 }} />
            <Bone width={110} height={14} />
            <View style={{ flex: 1 }} />
            <Bone width={50} height={20} style={{ borderRadius: 10 }} />
          </View>
          <View style={styles.participantRow}>
            <Bone width={36} height={36} style={{ borderRadius: 18 }} />
            <Bone width={90} height={14} />
          </View>
        </View>

        {/* Join button */}
        <Bone width="100%" height={48} style={{ borderRadius: radius.md, marginTop: spacing.sm }} />
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
    paddingBottom: spacing.xl + 32,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  infoGrid: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    padding: spacing.md,
    marginBottom: spacing.lg,
    gap: spacing.sm,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  section: {
    marginBottom: spacing.lg,
  },
  participantRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.xs,
  },
});
