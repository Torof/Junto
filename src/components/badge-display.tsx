import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import {
  Users, Mountain, Trophy, Award,
  AlertTriangle, OctagonAlert,
  Clock, Backpack, Handshake, ShieldCheck,
  Compass, Tent, Waves, Bike, Plane,
  type LucideIcon,
} from 'lucide-react-native';
import { spacing } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { LevelGauge } from '@/components/level-gauge';
import {
  POSITIVE_BADGES,
  NEGATIVE_BADGES,
  type ReputationBadge,
  type Trophy as ReputationTrophy,
  type SportLevel,
  type SportLevelVotes,
  type AwardAggregates,
} from '@/services/badge-service';

// Phase 1 of the profile remodel: replace the trophy/medal grid with three
// minimal sections that inherit the hero's visual language.
//   1. Vouched line — inline trait·count for positives crossing the 5-vote threshold
//   2. Warning line — only when an active negative crosses 5 (amber 5–14, red 15+)
//   3. Sport experience — emoji + count chips for sports with ≥3 completions
// Tier names, "newcomer", and the locked teaser section are gone.

interface BadgeDisplayProps {
  reputation: ReputationBadge[];
  trophies: ReputationTrophy[];
  sportLevels?: SportLevel[];
  sportLevelVotes?: SportLevelVotes[];
  awardAggregates?: AwardAggregates;
  // Kept for call-site compatibility — Phase 1+ ignores them.
  completedCount?: number;
  createdCount?: number;
  showLocked?: boolean;
}

const VOUCHED_THRESHOLD = 5;
const WARNING_THRESHOLD = 5;
const WARNING_RED_THRESHOLD = 15;
const SPORT_THRESHOLD = 3;
// Peer-vouched tier — same color palette as Junto so the eye learns one
// rank language across the card. Visibility threshold is 5 so the bronze
// floor is never "missing".
function vouchedTier(count: number): 'bronze' | 'silver' | 'gold' {
  if (count >= 50) return 'gold';
  if (count >= 10) return 'silver';
  return 'bronze';
}
const TIER_COLOR = {
  bronze: '#B87333',
  silver: '#9DA9B5',
  gold: '#E0B040',
} as const;

const POSITIVE_KEYS = new Set<string>(POSITIVE_BADGES.map((b) => b.key));
const NEGATIVE_KEYS = new Set<string>(NEGATIVE_BADGES.map((b) => b.key));

// Per-trait Lucide icons for the vouched row. Lucide icons render in the
// same family as the rest of the UI — cleaner than the colored emojis the
// peer-review screen uses for tap targets.
const POSITIVE_TRAIT_ICON: Record<string, LucideIcon> = {
  punctual: Clock,
  prepared: Backpack,
  conciliant: Handshake,
  prudent: ShieldCheck,
};
// level_accurate is deprecated. Hidden everywhere.
const DEPRECATED_PEER_KEYS = new Set(['level_accurate']);

interface VouchedItem {
  key: string;
  label: string;
  count: number;
}
interface WarningItem {
  key: string;
  label: string;
  severity: 'amber' | 'red';
}
interface JuntoAward {
  id: string;
  Icon: LucideIcon;
  count: number;
  tier: 'bronze' | 'silver' | 'gold';
}

// Data-driven Junto award definitions. Adding / removing / tuning a badge
// is just an entry change here + an i18n entry under badges.awardLabel.{id}.
//
// `outings` — main count threshold (joined / created / multi-day / outings in category)
// `minDistinct` — extra threshold for themed badges (distinct sports of this kind)
// `evaluate` — pulls (count, distinctSports) from the server aggregates.
type AwardEval = { count: number; distinctSports?: number };
interface AwardDef {
  id: string;
  Icon: LucideIcon;
  outings: [number, number, number];     // bronze / silver / gold
  minDistinct?: [number, number, number];
  evaluate: (a: AwardAggregates) => AwardEval;
}

const AWARDS: AwardDef[] = [
  {
    id: 'joined',
    Icon: Award,
    outings: [5, 20, 50],
    evaluate: (a) => ({ count: a.joined }),
  },
  {
    id: 'created',
    Icon: Trophy,
    outings: [5, 20, 50],
    evaluate: (a) => ({ count: a.created }),
  },
  {
    id: 'polyvalent',
    Icon: Compass,
    outings: [3, 5, 8],
    evaluate: (a) => ({ count: a.distinct_sports }),
  },
  {
    id: 'aventurier',
    Icon: Tent,
    outings: [1, 3, 5],
    evaluate: (a) => ({ count: a.multi_day_count }),
  },
  // Themed — by sports.category. The `minDistinct` floor stops a single sport
  // from carrying the whole tier.
  {
    id: 'aquatique',
    Icon: Waves,
    outings: [25, 50, 100],
    minDistinct: [3, 4, 5],
    evaluate: (a) => {
      const c = a.by_category?.water;
      return { count: c?.outings ?? 0, distinctSports: c?.distinct_sports ?? 0 };
    },
  },
  {
    id: 'montagne',
    Icon: Mountain,
    outings: [25, 50, 100],
    minDistinct: [3, 4, 5],
    evaluate: (a) => {
      const c = a.by_category?.mountain;
      return { count: c?.outings ?? 0, distinctSports: c?.distinct_sports ?? 0 };
    },
  },
  {
    id: 'route',
    Icon: Bike,
    outings: [25, 50, 100],
    minDistinct: [2, 3, 3], // road has fewer sports — relax distinct floor
    evaluate: (a) => {
      const c = a.by_category?.road;
      return { count: c?.outings ?? 0, distinctSports: c?.distinct_sports ?? 0 };
    },
  },
  {
    id: 'air',
    Icon: Plane,
    outings: [10, 25, 50],
    minDistinct: [1, 1, 1], // air sports are inherently rare
    evaluate: (a) => {
      const c = a.by_category?.air;
      return { count: c?.outings ?? 0, distinctSports: c?.distinct_sports ?? 0 };
    },
  },
];

function evaluateAward(def: AwardDef, agg: AwardAggregates): { tier: 'bronze' | 'silver' | 'gold' | null; count: number } {
  const result = def.evaluate(agg);
  const distinct = result.distinctSports ?? Number.POSITIVE_INFINITY;
  const tiers = [
    { name: 'gold' as const,   threshold: def.outings[2], distinctFloor: def.minDistinct?.[2] ?? 0 },
    { name: 'silver' as const, threshold: def.outings[1], distinctFloor: def.minDistinct?.[1] ?? 0 },
    { name: 'bronze' as const, threshold: def.outings[0], distinctFloor: def.minDistinct?.[0] ?? 0 },
  ];
  for (const t of tiers) {
    if (result.count >= t.threshold && distinct >= t.distinctFloor) {
      return { tier: t.name, count: result.count };
    }
  }
  return { tier: null, count: result.count };
}
interface SportItem {
  sportKey: string;
  count: number;
  label: string;
  dots: number;
  lastAt: string | null;
  firstAt: string | null;
  levelVotes?: { over: number; right: number; under: number };
}

type DetailTarget =
  | { kind: 'vouched'; item: VouchedItem }
  | { kind: 'warning'; item: WarningItem }
  | { kind: 'sport'; item: SportItem }
  | { kind: 'award'; item: JuntoAward };

export function BadgeDisplay({ reputation, trophies, sportLevels = [], sportLevelVotes = [], awardAggregates }: BadgeDisplayProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [selected, setSelected] = useState<DetailTarget | null>(null);

  const { vouched, warnings, sports, awards } = useMemo(() => {
    const vouchedList: VouchedItem[] = [];
    const warningList: WarningItem[] = [];

    for (const rep of reputation) {
      if (DEPRECATED_PEER_KEYS.has(rep.badge_key)) continue;
      const count = rep.vote_count ?? 0;
      if (POSITIVE_KEYS.has(rep.badge_key)) {
        if (count < VOUCHED_THRESHOLD) continue;
        vouchedList.push({
          key: rep.badge_key,
          label: t(`badges.${rep.badge_key}`, { defaultValue: rep.badge_key }),
          count,
        });
      } else if (NEGATIVE_KEYS.has(rep.badge_key)) {
        if (count < WARNING_THRESHOLD) continue;
        warningList.push({
          key: rep.badge_key,
          label: t(`badges.${rep.badge_key}`, { defaultValue: rep.badge_key }),
          severity: count >= WARNING_RED_THRESHOLD ? 'red' : 'amber',
        });
      }
    }

    vouchedList.sort((a, b) => b.count - a.count);
    // Show red warnings first so the strongest signal lands at the start of the row.
    warningList.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'red' ? -1 : 1));

    const sportMetaByKey = new Map<string, { dots: number; lastAt: string | null; firstAt: string | null }>(
      sportLevels.map((sl) => [sl.sport_key, { dots: sl.dots, lastAt: sl.last_at, firstAt: sl.first_at }])
    );

    const levelVotesByKey = new Map<string, { over: number; right: number; under: number }>(
      sportLevelVotes.map((sv) => [
        sv.sport_key,
        { over: sv.level_over, right: sv.level_right, under: sv.level_under },
      ])
    );

    const sportList: SportItem[] = trophies
      .filter((tr) => tr.category === 'sport' && tr.sport_key && tr.count >= SPORT_THRESHOLD)
      .map((tr) => {
        const meta = sportMetaByKey.get(tr.sport_key as string);
        return {
          sportKey: tr.sport_key as string,
          count: tr.count,
          label: t(`sports.${tr.sport_key}`, { defaultValue: tr.sport_key as string }),
          dots: meta?.dots ?? 1,
          lastAt: meta?.lastAt ?? null,
          firstAt: meta?.firstAt ?? null,
          levelVotes: levelVotesByKey.get(tr.sport_key as string),
        };
      })
      .sort((a, b) => b.count - a.count);

    // Junto awards — iterate the data-driven AWARDS list, surface only the
    // ones the user has earned at least bronze on.
    const awardsList: JuntoAward[] = [];
    if (awardAggregates) {
      for (const def of AWARDS) {
        const evald = evaluateAward(def, awardAggregates);
        if (evald.tier) {
          awardsList.push({
            id: def.id,
            Icon: def.Icon,
            count: evald.count,
            tier: evald.tier,
          });
        }
      }
    }

    return { vouched: vouchedList, warnings: warningList, sports: sportList, awards: awardsList };
  }, [reputation, trophies, sportLevels, sportLevelVotes, awardAggregates, t]);

  const hasPeer = vouched.length > 0 || warnings.length > 0;
  if (!hasPeer && sports.length === 0 && awards.length === 0) return null;

  return (
    <View style={styles.card}>
      {hasPeer && (
        <View style={styles.section}>
          <SectionHeader
            Icon={Users}
            label={t('profil.badgeSectionPeer')}
            styles={styles}
            colors={colors}
          />
          {vouched.length > 0 && (
            <VouchedRow
              items={vouched}
              styles={styles}
              colors={colors}
              onPress={(item) => setSelected({ kind: 'vouched', item })}
            />
          )}
          {warnings.length > 0 && (
            <View style={vouched.length > 0 ? styles.warningSpacer : undefined}>
              <WarningRow
                items={warnings}
                styles={styles}
                colors={colors}
                onPress={(item) => setSelected({ kind: 'warning', item })}
              />
            </View>
          )}
        </View>
      )}

      {awards.length > 0 && (
        <View style={[styles.section, hasPeer && styles.sectionGap]}>
          <SectionHeader
            Icon={Trophy}
            label={t('profil.badgeSectionAuto')}
            styles={styles}
            colors={colors}
          />
          <AwardRow
            items={awards}
            styles={styles}
            onPress={(item) => setSelected({ kind: 'award', item })}
            t={t}
          />
        </View>
      )}

      {sports.length > 0 && (
        <View style={[styles.section, (hasPeer || awards.length > 0) && styles.sectionGap]}>
          <SectionHeader
            Icon={Mountain}
            label={t('profil.badgeSectionSports')}
            styles={styles}
            colors={colors}
          />
          <SportRow
            items={sports}
            styles={styles}
            colors={colors}
            onPress={(item) => setSelected({ kind: 'sport', item })}
          />
        </View>
      )}

      <DetailModal
        target={selected}
        onClose={() => setSelected(null)}
        styles={styles}
        t={t}
      />
    </View>
  );
}

function SectionHeader({
  Icon,
  label,
  styles,
  colors,
}: {
  Icon: LucideIcon;
  label: string;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}) {
  return (
    <View style={styles.sectionHeader}>
      <Icon size={11} color={colors.textMuted} strokeWidth={2.2} />
      <Text style={styles.sectionLabel}>{label}</Text>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Vouched row — inline `✓ Trait ·N   Trait ·N   ...`
// ---------------------------------------------------------------------------

function VouchedRow({
  items,
  styles,
  colors,
  onPress,
}: {
  items: VouchedItem[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: (item: VouchedItem) => void;
}) {
  return (
    <View style={styles.wrapRowChips}>
      {items.map((it) => {
        const Icon = POSITIVE_TRAIT_ICON[it.key];
        const tierColor = TIER_COLOR[vouchedTier(it.count)];
        return (
          <Pressable
            key={it.key}
            onPress={() => onPress(it)}
            hitSlop={6}
            style={({ pressed }) => [styles.lineItem, pressed && styles.tappedDim]}
          >
            {Icon && <Icon size={13} color={tierColor} strokeWidth={2.2} />}
            <Text style={styles.lineTraitText}>{it.label}</Text>
            <Text style={[styles.lineCountText, { color: tierColor }]}>·{it.count}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Warning row — `⚠ Trait signalé` (amber) or `⛔ Trait à éviter` (red)
// ---------------------------------------------------------------------------

function WarningRow({
  items,
  styles,
  onPress,
}: {
  items: WarningItem[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: (item: WarningItem) => void;
}) {
  const { t } = useTranslation();
  return (
    <View style={styles.wrapRowChips}>
      {items.map((it) => {
        const isRed = it.severity === 'red';
        const Icon = isRed ? OctagonAlert : AlertTriangle;
        const color = isRed ? COLOR_RED : COLOR_AMBER;
        const suffix = t(isRed ? 'badges.warning.avoid' : 'badges.warning.signaled');
        return (
          <Pressable
            key={it.key}
            onPress={() => onPress(it)}
            hitSlop={6}
            style={({ pressed }) => [styles.lineItem, pressed && styles.tappedDim]}
          >
            <Icon size={13} color={color} strokeWidth={2.4} />
            <Text style={[styles.lineTraitText, { color }]}>
              {it.label} {suffix}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Sport row — chips with emoji + count. Phase 3 will add the 4-dot level.
// ---------------------------------------------------------------------------

function SportRow({
  items,
  styles,
  onPress,
}: {
  items: SportItem[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: (item: SportItem) => void;
}) {
  return (
    <View style={styles.wrapRowChips}>
      {items.map((it) => (
        <Pressable
          key={it.sportKey}
          onPress={() => onPress(it)}
          hitSlop={4}
          style={({ pressed }) => [styles.sportChipPill, pressed && styles.tappedDim]}
        >
          <Text style={styles.sportEmoji}>{getSportIcon(it.sportKey)}</Text>
          <View style={styles.sportCountCircle}>
            <Text style={styles.sportCountText}>{it.count}</Text>
          </View>
        </Pressable>
      ))}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Award row — bronze / silver / gold cup per category (joined / created),
// derived from raw trophy counts. Single cup per category.
// ---------------------------------------------------------------------------

function AwardRow({
  items,
  styles,
  onPress,
  t,
}: {
  items: JuntoAward[];
  styles: ReturnType<typeof createStyles>;
  onPress: (item: JuntoAward) => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  return (
    <View style={styles.wrapRowChips}>
      {items.map((it) => {
        const tierColor = TIER_COLOR[it.tier];
        const label = t(`badges.awardLabel.${it.id}.${it.tier}`, { defaultValue: it.id });
        const Icon = it.Icon;
        return (
          <Pressable
            key={it.id}
            onPress={() => onPress(it)}
            hitSlop={6}
            style={({ pressed }) => [styles.lineItem, pressed && styles.tappedDim]}
          >
            <Icon size={13} color={tierColor} strokeWidth={2.2} />
            <Text style={styles.lineTraitText}>{label}</Text>
            <Text style={[styles.lineCountText, { color: tierColor }]}>·{it.count}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

// ---------------------------------------------------------------------------
// Detail modal — single layout for all three section types. Reuses the
// reliability help modal's typographic treatment.
// ---------------------------------------------------------------------------

function DetailModal({
  target,
  onClose,
  styles,
  t,
}: {
  target: DetailTarget | null;
  onClose: () => void;
  styles: ReturnType<typeof createStyles>;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  if (!target) return null;

  let title = '';
  let body = '';
  let footer: string | null = null;

  if (target.kind === 'vouched') {
    title = target.item.label;
    body = t(`badges.peerDesc.${target.item.key}`, { defaultValue: '' });
    footer = t('badges.vouchedFooter', {
      count: target.item.count,
      defaultValue: '',
    });
  } else if (target.kind === 'warning') {
    title = target.item.label;
    body = t(`badges.peerDesc.${target.item.key}`, { defaultValue: '' });
    footer = t('badges.peerNegativeHint');
  } else if (target.kind === 'sport') {
    title = `${getSportIcon(target.item.sportKey)}  ${target.item.label}`;
    body = t('badges.sportFooter', {
      count: target.item.count,
      defaultValue: `${target.item.count} activités complétées`,
    });
    const dotsLabel = t(`badges.sportDot.${target.item.dots}`, { defaultValue: '' });
    if (dotsLabel !== '') footer = dotsLabel;
  } else {
    // award
    const tierLabel = t(`badges.awardTier.${target.item.tier}`, { defaultValue: target.item.tier });
    const awardLabel = t(`badges.awardLabel.${target.item.id}.${target.item.tier}`, {
      defaultValue: target.item.id,
    });
    title = `${awardLabel} · ${tierLabel}`;
    body = t(`badges.awardDesc.${target.item.id}`, {
      count: target.item.count,
      defaultValue: `${target.item.count} activités.`,
    });
  }

  const isSport = target.kind === 'sport';
  const levelVotes = isSport ? target.item.levelVotes : undefined;
  const totalLevelVotes = levelVotes
    ? levelVotes.over + levelVotes.right + levelVotes.under
    : 0;

  // Recency / cadence — only when we have an isSport target and at least
  // one timestamp from the server.
  const lastRelative = isSport && target.item.lastAt
    ? formatRelativeFromNow(target.item.lastAt, t)
    : null;
  const frequency = isSport ? computeFrequency(target.item.count, target.item.firstAt) : null;

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.modalBackdrop} onPress={onClose}>
        <Pressable style={styles.modalCard} onPress={(e) => e.stopPropagation()}>
          <Text style={styles.modalTitle}>{title}</Text>
          {isSport && (
            <View style={styles.modalLevelRow}>
              <LevelGauge dots={target.item.dots} />
              {footer && <Text style={styles.modalLevelLabel}>{footer}</Text>}
            </View>
          )}
          {body !== '' && <Text style={styles.modalBody}>{body}</Text>}
          {footer && !isSport && <Text style={styles.modalFooter}>{footer}</Text>}

          {isSport && (lastRelative || frequency != null) && (
            <View style={styles.modalRecency}>
              {lastRelative && (
                <Text style={styles.modalRecencyLine}>
                  {t('badges.lastActivityAt', { when: lastRelative, defaultValue: `Last activity: ${lastRelative}` })}
                </Text>
              )}
              {frequency != null && (
                <Text style={styles.modalRecencyLine}>
                  {t('badges.frequency', {
                    rate: frequency.toFixed(1),
                    defaultValue: `${frequency.toFixed(1)} outings / month avg.`,
                  })}
                </Text>
              )}
            </View>
          )}

          {isSport && totalLevelVotes > 0 && levelVotes && (
            <View style={styles.modalLevelVotes}>
              <Text style={styles.modalLevelVotesHeader}>
                {t('badges.levelVotesHeader', { defaultValue: 'Level (peer review)' })}
              </Text>
              <View style={styles.modalLevelVotesRow}>
                <LevelVoteCounter
                  label={t('badges.short.level_over')}
                  count={levelVotes.over}
                  styles={styles}
                />
                <LevelVoteCounter
                  label={t('badges.short.level_right')}
                  count={levelVotes.right}
                  styles={styles}
                  highlight
                />
                <LevelVoteCounter
                  label={t('badges.short.level_under')}
                  count={levelVotes.under}
                  styles={styles}
                />
              </View>
            </View>
          )}

          <Pressable style={styles.modalDismiss} onPress={onClose}>
            <Text style={styles.modalDismissText}>
              {t('common.close', { defaultValue: 'OK' })}
            </Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

// Lightweight relative-time formatter — avoids pulling in dayjs's
// relativeTime plugin globally for one feature. Returns a localized
// short string like "12 j", "3 sem", "5 mois", "2 ans".
function formatRelativeFromNow(at: string, t: (k: string, opts?: Record<string, unknown>) => string): string {
  const days = Math.max(0, dayjs().diff(dayjs(at), 'day'));
  if (days < 1) return t('badges.relTime.today', { defaultValue: "aujourd'hui" });
  if (days < 7) return t('badges.relTime.days', { count: days, defaultValue: `${days}j` });
  if (days < 30) {
    const weeks = Math.floor(days / 7);
    return t('badges.relTime.weeks', { count: weeks, defaultValue: `${weeks} sem` });
  }
  if (days < 365) {
    const months = Math.floor(days / 30);
    return t('badges.relTime.months', { count: months, defaultValue: `${months} mois` });
  }
  const years = Math.floor(days / 365);
  return t('badges.relTime.years', { count: years, defaultValue: `${years} an` });
}

// Average outings per month, computed from first completion to now.
// Uses 1 month as the floor so a single-day burst doesn't read as
// "30 outings/month".
function computeFrequency(count: number, firstAt: string | null): number | null {
  if (!firstAt || count <= 0) return null;
  const months = Math.max(1, dayjs().diff(dayjs(firstAt), 'month'));
  return count / months;
}

function LevelVoteCounter({
  label,
  count,
  styles,
  highlight,
}: {
  label: string;
  count: number;
  styles: ReturnType<typeof createStyles>;
  highlight?: boolean;
}) {
  return (
    <View style={styles.levelVoteCell}>
      <Text style={[styles.levelVoteCount, highlight && styles.levelVoteCountHighlight]}>
        {count}
      </Text>
      <Text style={styles.levelVoteLabel}>{label}</Text>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

const COLOR_AMBER = '#D49A3F';
const COLOR_RED = '#C0392B';

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    card: {
      backgroundColor: colors.surface,
      borderRadius: 18,
      borderWidth: 1,
      borderColor: colors.line,
      paddingVertical: spacing.md - 2,
      paddingHorizontal: spacing.md,
      marginBottom: spacing.md,
    },
    section: {
      // Each section group (peer / awards / sports) is its own block.
    },
    sectionGap: {
      // Section rhythm comes from spacing alone — no divider line.
      marginTop: 22,
    },
    sectionHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      marginBottom: 12,
    },
    sectionLabel: {
      color: colors.textSecondary,
      fontSize: 10.5,
      fontWeight: '700',
      letterSpacing: 1.4,
      textTransform: 'uppercase',
    },
    warningSpacer: {
      marginTop: 6,
    },

    wrapRowChips: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      alignItems: 'flex-start',
      rowGap: 6,
      columnGap: 6,
    },

    // Each peer / award trait sits in its own pill — same surface family
    // as the sport chips below for visual cohesion across the card.
    lineItem: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 5,
      backgroundColor: colors.surfaceAlt,
      borderRadius: 8,
      paddingVertical: 5,
      paddingHorizontal: 9,
    },
    lineTraitText: {
      color: colors.textPrimary,
      fontSize: 12.5,
      fontWeight: '600',
      letterSpacing: -0.01,
    },
    lineCountText: {
      color: colors.textMuted,
      fontSize: 12.5,
      fontWeight: '700',
      marginLeft: 3,
    },

    // Sport chip — compact pill with emoji + count circle, no label, no
    // divider. Tap opens the popover for full detail (sport name, level,
    // peer review breakdown).
    sportChipPill: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      backgroundColor: colors.surfaceAlt,
      borderRadius: 8,
      paddingVertical: 5,
      paddingLeft: 8,
      paddingRight: 5,
    },
    sportEmoji: {
      fontSize: 16,
      lineHeight: 18,
    },
    sportCountCircle: {
      minWidth: 24,
      height: 24,
      borderRadius: 12,
      backgroundColor: colors.surface,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 6,
    },
    sportCountText: {
      color: colors.cta,
      fontSize: 13,
      fontWeight: '800',
      letterSpacing: -0.02,
    },

    tappedDim: {
      opacity: 0.55,
    },

    modalBackdrop: {
      flex: 1,
      backgroundColor: 'rgba(0,0,0,0.55)',
      alignItems: 'center',
      justifyContent: 'center',
      padding: spacing.lg,
    },
    modalCard: {
      width: '100%',
      maxWidth: 360,
      backgroundColor: colors.surface,
      borderRadius: 18,
      padding: spacing.lg,
      gap: 8,
      borderWidth: 1,
      borderColor: colors.line,
    },
    modalTitle: {
      color: colors.textPrimary,
      fontSize: 17,
      fontWeight: '800',
      marginBottom: 2,
    },
    modalBody: {
      color: colors.textSecondary,
      fontSize: 13,
      lineHeight: 19,
    },
    modalFooter: {
      color: colors.textMuted,
      fontSize: 12,
      fontStyle: 'italic',
      marginTop: 4,
    },
    modalLevelRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      marginTop: 6,
      marginBottom: 4,
    },
    modalLevelLabel: {
      color: colors.textPrimary,
      fontSize: 13,
      fontWeight: '700',
    },
    modalRecency: {
      marginTop: 8,
      gap: 2,
    },
    modalRecencyLine: {
      color: colors.textMuted,
      fontSize: 12,
      fontWeight: '600',
    },
    modalLevelVotes: {
      marginTop: 10,
      paddingTop: 10,
      borderTopWidth: 1,
      borderTopColor: colors.line,
      borderStyle: 'dashed',
    },
    modalLevelVotesHeader: {
      color: colors.textMuted,
      fontSize: 9.5,
      fontWeight: '600',
      letterSpacing: 1.2,
      textTransform: 'uppercase',
      marginBottom: 8,
    },
    modalLevelVotesRow: {
      flexDirection: 'row',
      backgroundColor: colors.surfaceAlt,
      borderRadius: 10,
      overflow: 'hidden',
    },
    levelVoteCell: {
      flex: 1,
      alignItems: 'center',
      paddingVertical: 8,
    },
    levelVoteCount: {
      color: colors.textPrimary,
      fontSize: 16,
      fontWeight: '800',
      letterSpacing: -0.02,
    },
    levelVoteCountHighlight: {
      color: '#7EC8A3',
    },
    levelVoteLabel: {
      color: colors.textMuted,
      fontSize: 10,
      fontWeight: '600',
      marginTop: 2,
    },
    modalDismiss: {
      alignSelf: 'center',
      marginTop: spacing.md,
      backgroundColor: colors.cta + '1F',
      borderRadius: 999,
      paddingHorizontal: 28,
      paddingVertical: 10,
    },
    modalDismissText: {
      color: colors.cta,
      fontSize: 13,
      fontWeight: '700',
    },
  });
