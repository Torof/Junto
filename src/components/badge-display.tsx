import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import {
  badgeService,
  POSITIVE_BADGES,
  NEGATIVE_BADGES,
  SPORT_TROPHY_THRESHOLD,
  type ReputationBadge,
  type Trophy,
} from '@/services/badge-service';

interface BadgeDisplayProps {
  reputation: ReputationBadge[];
  trophies: Trophy[];
}

export function BadgeDisplay({ reputation, trophies }: BadgeDisplayProps) {
  const { t } = useTranslation();

  // Progression trophy
  const progressionTrophy = trophies.find((tr) => tr.trophy_key === 'progression');
  const progressionLevel = badgeService.getProgressionTrophy(progressionTrophy?.trophy_count ?? 0);

  // Sport trophies (>= 20 in a sport)
  const sportTrophies = trophies.filter(
    (tr) => tr.trophy_key !== 'progression' && tr.trophy_count >= SPORT_TROPHY_THRESHOLD,
  );

  // Unlocked reputation badges (positive >= 5, negative >= 15)
  const unlockedPositive = reputation.filter((r) => {
    const badge = POSITIVE_BADGES.find((b) => b.key === r.badge_key);
    return badge && r.vote_count >= badge.threshold;
  });

  const unlockedNegative = reputation.filter((r) => {
    const badge = NEGATIVE_BADGES.find((b) => b.key === r.badge_key);
    return badge && r.vote_count >= badge.threshold;
  });

  const hasAnything = progressionLevel || sportTrophies.length > 0 || unlockedPositive.length > 0 || unlockedNegative.length > 0;

  if (!hasAnything) return null;

  return (
    <View style={styles.container}>
      {/* Progression */}
      {progressionLevel && (
        <View style={styles.row}>
          <Text style={styles.badge}>
            {progressionLevel.icon} {t(`badges.${progressionLevel.key}`)}
          </Text>
        </View>
      )}

      {/* Sport trophies */}
      {sportTrophies.length > 0 && (
        <View style={styles.row}>
          {sportTrophies.map((tr) => (
            <Text key={tr.trophy_key} style={styles.badge}>
              🏆 {t(`sports.${tr.trophy_key}`, tr.trophy_key)} ({tr.trophy_count})
            </Text>
          ))}
        </View>
      )}

      {/* Positive reputation */}
      {unlockedPositive.length > 0 && (
        <View style={styles.row}>
          {unlockedPositive.map((r) => {
            const info = badgeService.getBadgeInfo(r.badge_key);
            return (
              <Text key={r.badge_key} style={styles.badgePositive}>
                {info?.icon} {t(`badges.${r.badge_key}`)}
              </Text>
            );
          })}
        </View>
      )}

      {/* Negative reputation (discreet) */}
      {unlockedNegative.length > 0 && (
        <View style={styles.row}>
          {unlockedNegative.map((r) => {
            const info = badgeService.getBadgeInfo(r.badge_key);
            return (
              <Text key={r.badge_key} style={styles.badgeNegative}>
                {info?.icon} {t(`badges.${r.badge_key}`)}
              </Text>
            );
          })}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginBottom: spacing.lg },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs, marginBottom: spacing.xs },
  badge: {
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    color: colors.textPrimary, fontSize: fontSizes.xs,
  },
  badgePositive: {
    backgroundColor: colors.success + '20', borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    color: colors.success, fontSize: fontSizes.xs,
  },
  badgeNegative: {
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    color: colors.textSecondary, fontSize: fontSizes.xs,
    opacity: 0.7,
  },
});
