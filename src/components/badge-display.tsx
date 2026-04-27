import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import {
  Check, ShieldCheck, Smile, Star, Clock, Trophy, Lock, Sprout,
  Sparkles, Users, AlertTriangle, Frown, ShieldOff, AlertOctagon,
  Mountain, Flag, Zap,
  type LucideIcon,
} from 'lucide-react-native';
import { spacing } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import {
  badgeService,
  POSITIVE_BADGES,
  NEGATIVE_BADGES,
  tierFor,
  type ReputationBadge,
  type Trophy as ReputationTrophy,
  type TierKey,
} from '@/services/badge-service';

interface BadgeDisplayProps {
  reputation: ReputationBadge[];
  trophies: ReputationTrophy[];
  completedCount?: number;
  createdCount?: number;
  showLocked?: boolean;
}

interface UIBadge {
  id: string;
  label: string;
  Icon: LucideIcon;
  color: string;          // main accent (auto badges: varied; peer: green/red)
  kind: 'auto' | 'peer-positive' | 'peer-negative';
  got: boolean;
  count?: number;         // vote count (peer) — shown as ×N
  progress?: string;      // for locked: "3/5"
}

// Positive peer badges: per-trait color + icon (distinguishes qualities)
const PEER_POSITIVE_VISUAL: Record<string, { Icon: LucideIcon; color: string }> = {
  trustworthy:  { Icon: ShieldCheck, color: '#7EC8A3' },
  great_leader: { Icon: Star,        color: '#F26B2E' },
  good_vibes:   { Icon: Smile,       color: '#F4A373' },
  punctual:     { Icon: Clock,       color: '#9B6BD6' },
  level_accurate: { Icon: Star, color: '#7EC8A3' }, // legacy, hidden
};

// Negative peer badges: uniform red (strong warning signal)
const PEER_NEGATIVE_ICON: Record<string, LucideIcon> = {
  level_overestimated: AlertTriangle,
  difficult_attitude:  Frown,
  unreliable_field:    ShieldOff,
  aggressive:          AlertOctagon,
};

// level_accurate is deprecated — replaced by per-sport endorsements.
// Hidden from display; backend data may still exist from before the switch.
const DEPRECATED_PEER_KEYS = new Set(['level_accurate']);

// Per-tier accent colors — same hue family across categories so users can
// quickly read the *level* visually, with category icons distinguishing the
// kind of badge.
const TIER_COLOR: Record<TierKey, string> = {
  t1: '#7EC8A3',
  t2: '#4B7CB8',
  t3: '#F26B2E',
  t4: '#9B6BD6',
  t5: '#F4A373',
};

const JOINED_ICON: Record<TierKey, LucideIcon> = {
  t1: Check, t2: Star, t3: Zap, t4: Mountain, t5: Trophy,
};

const CREATED_ICON: Record<TierKey, LucideIcon> = {
  t1: Flag, t2: Flag, t3: Star, t4: Trophy, t5: Trophy,
};

export function BadgeDisplay({ reputation, trophies, completedCount, createdCount, showLocked = true }: BadgeDisplayProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [selected, setSelected] = useState<UIBadge | null>(null);

  const { auto, peer, locked, totalGot } = useMemo(() => {
    const autoList: UIBadge[] = [];
    const peerList: UIBadge[] = [];
    const lockedList: UIBadge[] = [];

    const joinedTrophy = trophies.find((tr) => tr.category === 'joined');
    const createdTrophy = trophies.find((tr) => tr.category === 'created');
    const sportTrophies = trophies.filter((tr) => tr.category === 'sport');
    const totalCompleted = (joinedTrophy?.count ?? 0) + (createdTrophy?.count ?? 0);

    // AUTO — Newcomer (only when no completed activity at all)
    if (totalCompleted === 0) {
      autoList.push({
        id: 'newcomer',
        label: t('badges.newcomer'),
        Icon: Sprout,
        color: '#7EC8A3',
        kind: 'auto',
        got: true,
      });
    }

    // AUTO — Joiner tier
    const joinedTier = tierFor(joinedTrophy?.count ?? 0);
    if (joinedTier) {
      autoList.push({
        id: `joined_${joinedTier}`,
        label: t(`badges.joined.${joinedTier}`),
        Icon: JOINED_ICON[joinedTier],
        color: TIER_COLOR[joinedTier],
        kind: 'auto',
        got: true,
        count: joinedTrophy?.count,
      });
    }

    // AUTO — Organizer tier
    const createdTier = tierFor(createdTrophy?.count ?? 0);
    if (createdTier) {
      autoList.push({
        id: `created_${createdTier}`,
        label: t(`badges.created.${createdTier}`),
        Icon: CREATED_ICON[createdTier],
        color: TIER_COLOR[createdTier],
        kind: 'auto',
        got: true,
        count: createdTrophy?.count,
      });
    }

    // AUTO — Per-sport tiers (one per sport that crossed T1)
    sportTrophies.forEach((tr) => {
      const tier = tierFor(tr.count);
      if (!tier || !tr.sport_key) return;
      const sportEmoji = getSportIcon(tr.sport_key);
      const sportLabel = t(`sports.${tr.sport_key}`, { defaultValue: tr.sport_key });
      autoList.push({
        id: `sport_${tr.sport_key}_${tier}`,
        label: `${sportEmoji} ${t(`badges.sport.${tier}`)} · ${sportLabel}`,
        Icon: Trophy,
        color: TIER_COLOR[tier],
        kind: 'auto',
        got: true,
        count: tr.count,
      });
    });

    // Suppress unused-prop warning for createdCount (kept for backwards compat)
    void createdCount;

    // PEER — Positive (per-trait color)
    POSITIVE_BADGES.forEach((def) => {
      if (DEPRECATED_PEER_KEYS.has(def.key)) return;
      const rep = reputation.find((r) => r.badge_key === def.key);
      const votes = rep?.vote_count ?? 0;
      const visual = PEER_POSITIVE_VISUAL[def.key] ?? { Icon: Check, color: '#7EC8A3' };
      if (votes >= def.threshold) {
        peerList.push({
          id: `peer_pos_${def.key}`,
          label: t(`badges.${def.key}`),
          Icon: visual.Icon,
          color: visual.color,
          kind: 'peer-positive',
          got: true,
          count: votes,
        });
      } else {
        lockedList.push({
          id: `peer_pos_${def.key}_locked`,
          label: t(`badges.${def.key}`),
          Icon: visual.Icon,
          color: visual.color,
          kind: 'peer-positive',
          got: false,
          progress: `${votes}/${def.threshold}`,
        });
      }
    });

    // PEER — Negative (red)
    NEGATIVE_BADGES.forEach((def) => {
      const rep = reputation.find((r) => r.badge_key === def.key);
      const votes = rep?.vote_count ?? 0;
      if (votes < def.threshold) return;
      const Icon = PEER_NEGATIVE_ICON[def.key] ?? AlertTriangle;
      peerList.push({
        id: `peer_neg_${def.key}`,
        label: t(`badges.${def.key}`),
        Icon,
        color: '#E5524E',
        kind: 'peer-negative',
        got: true,
        count: votes,
      });
    });

    return {
      auto: autoList,
      peer: peerList,
      locked: lockedList,
      totalGot: autoList.length + peerList.length,
    };
  }, [reputation, trophies, createdCount, t]);

  if (auto.length === 0 && peer.length === 0 && (!showLocked || locked.length === 0)) return null;

  return (
    <View style={styles.card}>
      <View style={styles.headerRow}>
        <Text style={styles.title}>
          {t('profil.badgesSection').toUpperCase()} · {totalGot}
        </Text>
      </View>
      <View style={styles.headerDivider} />

      {peer.length > 0 && (
        <Section
          icon={Users}
          label={t('profil.badgeSectionPeer')}
          badges={peer}
          styles={styles}
          colors={colors}
          onBadgePress={setSelected}
        />
      )}

      {auto.length > 0 && (
        <Section
          icon={Sparkles}
          label={t('profil.badgeSectionAuto')}
          badges={auto}
          styles={styles}
          colors={colors}
          onBadgePress={setSelected}
        />
      )}

      {showLocked && locked.length > 0 && (
        <Section
          icon={Lock}
          label={`${t('profil.badgeSectionLocked')} · ${locked.length}`}
          badges={locked}
          styles={styles}
          colors={colors}
          lastSection
          onBadgePress={setSelected}
        />
      )}

      <BadgeDetailSheet
        badge={selected}
        visible={selected !== null}
        onClose={() => setSelected(null)}
        styles={styles}
        colors={colors}
        t={t}
      />
    </View>
  );
}

interface SectionProps {
  icon: LucideIcon;
  label: string;
  badges: UIBadge[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  lastSection?: boolean;
}

function Section({ icon: SectionIcon, label, badges, styles, colors, lastSection, onBadgePress }: SectionProps & { onBadgePress: (b: UIBadge) => void }) {
  return (
    <View style={[styles.sectionBlock, lastSection && { marginBottom: 0 }]}>
      <View style={styles.sectionHeader}>
        <SectionIcon size={11} color={colors.textMuted} strokeWidth={2.2} />
        <Text style={styles.sectionLabel}>{label}</Text>
      </View>
      <View style={styles.iconsRow}>
        {badges.map((b) => <BadgeIcon key={b.id} badge={b} styles={styles} colors={colors} onPress={() => onBadgePress(b)} />)}
      </View>
    </View>
  );
}

function BadgeIcon({ badge, styles, colors, onPress }: {
  badge: UIBadge;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: () => void;
}) {
  const { Icon } = badge;
  const isLocked = !badge.got;

  return (
    <Pressable onPress={onPress} hitSlop={6}>
      <View
        style={[
          styles.iconBadge,
          isLocked
            ? styles.iconBadgeLocked
            : { backgroundColor: badge.color, borderColor: badge.color },
        ]}
      >
        <Icon size={18} color={isLocked ? colors.textMuted : '#FFFFFF'} strokeWidth={2.2} />
      </View>
    </Pressable>
  );
}

function BadgeDetailSheet({
  badge,
  visible,
  onClose,
  styles,
  colors,
  t,
}: {
  badge: UIBadge | null;
  visible: boolean;
  onClose: () => void;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  if (!badge) return null;
  const { Icon } = badge;
  const isLocked = !badge.got;

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.detailBackdrop} onPress={onClose}>
        <Pressable style={styles.detailCard} onPress={(e) => e.stopPropagation()}>
          <View
            style={[
              styles.detailIcon,
              isLocked ? styles.iconBadgeLocked : { backgroundColor: badge.color, borderColor: badge.color },
            ]}
          >
            <Icon size={32} color={isLocked ? colors.textMuted : '#FFFFFF'} strokeWidth={2} />
          </View>
          <Text style={styles.detailLabel}>{badge.label}</Text>
          {badge.count != null && (
            <Text style={[styles.detailCount, { color: badge.color }]}>×{badge.count}</Text>
          )}
          {badge.progress && (
            <Text style={styles.detailProgress}>{badge.progress}</Text>
          )}
          <Pressable style={styles.detailClose} onPress={onClose}>
            <Text style={styles.detailCloseText}>{t('common.close', { defaultValue: 'OK' })}</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: 18,
    borderWidth: 1, borderColor: colors.line,
    padding: spacing.md - 2,
    marginBottom: spacing.md,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  title: {
    color: colors.textPrimary,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  headerDivider: {
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
    borderStyle: 'dashed',
    marginBottom: 12,
  },

  sectionBlock: {
    marginBottom: 12,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 8,
  },
  sectionLabel: {
    color: colors.textMuted,
    fontSize: 9.5,
    fontWeight: '600',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },

  pillsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  iconsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  iconBadge: {
    width: 36, height: 36, borderRadius: 18,
    borderWidth: 1.5,
    alignItems: 'center', justifyContent: 'center',
  },
  iconBadgeLocked: {
    backgroundColor: colors.surfaceAlt,
    borderStyle: 'dashed',
    borderColor: colors.textMuted,
    opacity: 0.55,
  },
  detailBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  detailCard: {
    width: '100%',
    maxWidth: 320,
    backgroundColor: colors.surface,
    borderRadius: 18,
    padding: spacing.lg,
    alignItems: 'center',
  },
  detailIcon: {
    width: 64, height: 64, borderRadius: 32,
    borderWidth: 2,
    alignItems: 'center', justifyContent: 'center',
    marginBottom: spacing.md,
  },
  detailLabel: {
    color: colors.textPrimary,
    fontSize: 17,
    fontWeight: '800',
    textAlign: 'center',
  },
  detailCount: {
    fontSize: 15,
    fontWeight: '800',
    marginTop: 4,
  },
  detailProgress: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '700',
    marginTop: 4,
  },
  detailClose: {
    marginTop: spacing.lg,
    backgroundColor: colors.cta,
    borderRadius: 999,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
  },
  detailCloseText: {
    color: colors.textPrimary,
    fontSize: 13,
    fontWeight: '700',
  },

  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderRadius: 999,
    borderWidth: 1,
    paddingLeft: 5,
    paddingRight: 12,
    paddingVertical: 5,
    position: 'relative',
  },
  pillLocked: {
    backgroundColor: colors.surfaceAlt,
    borderStyle: 'dashed',
    borderColor: colors.textMuted,
    opacity: 0.5,
  },
  pillIcon: {
    width: 24, height: 24, borderRadius: 12,
    alignItems: 'center', justifyContent: 'center',
  },
  pillIconLocked: {
    width: 22, height: 22, borderRadius: 11,
    backgroundColor: colors.background,
  },
  pillLabel: {
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: -0.01,
  },
  pillLabelLocked: {
    color: colors.textMuted,
    fontSize: 11.5,
    fontWeight: '600',
  },
  pillCount: {
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: -0.02,
    marginLeft: 2,
  },
  pillProgressLocked: {
    fontSize: 10.5,
    fontWeight: '700',
    color: colors.textMuted,
    marginLeft: 4,
  },
});
