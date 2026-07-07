import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import {
  Users, Mountain, Trophy,
  AlertTriangle, OctagonAlert,
  Clock, Package, Handshake, Shield,
  Compass, Tent, Waves, Bike, Plane,
  Hammer, Ban, LogOut, TrendingUp,
  HelpCircle, Check, ChevronRight, Triangle, Plus, Minus,
  type LucideIcon,
} from 'lucide-react-native';
import { spacing } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { useSports } from '@/hooks/use-sports';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { useQuery } from '@tanstack/react-query';
import {
  POSITIVE_BADGES,
  NEGATIVE_BADGES,
  badgeService,
  type ReputationBadge,
  type Trophy as ReputationTrophy,
  type SportLevel,
  type SportLevelVotes,
  type AwardAggregates,
  type BadgeVoter,
} from '@/services/badge-service';

// Phase 1 of the profile remodel: replace the trophy/medal grid with three
// minimal sections that inherit the hero's visual language.
//   1. Vouched line — inline trait·count for positives crossing the 5-vote threshold
//   2. Warning line — only when an active negative crosses 5 (amber 5–14, red 15+)
//   3. Sport experience — emoji + count chips for sports with ≥3 completions
// Tier names, "newcomer", and the locked teaser section are gone.

interface BadgeDisplayProps {
  /** Target user — needed to fetch voters for the Vouched popup. */
  userId: string;
  reputation: ReputationBadge[];
  trophies: ReputationTrophy[];
  sportLevels?: SportLevel[];
  sportLevelVotes?: SportLevelVotes[];
  awardAggregates?: AwardAggregates;
  // Declared sports/levels (users.sports / levels_per_sport). Drive the
  // "Sports pratiqués" chips even before any outing (cold-start), and the
  // declared level shown next to the peer-confirmation triangle.
  declaredSports?: string[] | null;
  declaredLevels?: Record<string, string> | null;
  // On the own profile: show the "+ Ajouter" chip and route taps to the editor.
  editable?: boolean;
  onEditSports?: () => void;
  // Kept for call-site compatibility — Phase 1+ ignores them.
  completedCount?: number;
  createdCount?: number;
  showLocked?: boolean;
}

// Peer confirmation of a declared level, from the 12-month-windowed votes
// (get_user_sport_level_votes). "fiable" = right + under (level is at least what
// they claim); "gonflé" = over. Simple majority decides (Scott 2026-07-07):
// show the signal as soon as it's been judged. fiable > gonflé → up (green),
// gonflé > fiable → down (red), a tie with ≥1 vote → even (grey neutral). No
// votes at all → null (not yet judged). Size scales mildly with volume.
function sportTriangle(
  v?: { over: number; right: number; under: number },
): { kind: 'up' | 'down' | 'even'; size: number } | null {
  if (!v) return null;
  const total = v.over + v.right + v.under;
  if (total === 0) return null;
  const size = total >= 20 ? 15 : total >= 10 ? 13 : 11;
  const fiable = v.right + v.under;
  const gonfle = v.over;
  if (fiable > gonfle) return { kind: 'up', size };
  if (gonfle > fiable) return { kind: 'down', size };
  return { kind: 'even', size };
}

// Declared level (levels_per_sport value) → short display label. Values are the
// activity LEVELS; fall back to the raw string for anything unexpected.
function levelLabel(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const s = raw.trim();
  if (!s) return null;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

const VOUCHED_THRESHOLD = 5;
const WARNING_THRESHOLD = 5;
const WARNING_RED_THRESHOLD = 15;
const SPORT_THRESHOLD = 3;
// Cap voter avatars surfaced in the Vouched popup. Beyond this we render
// a "+N" overflow indicator instead of more rounded portraits.
const MAX_VISIBLE_VOTER_AVATARS = 7;
// Peer-vouched tier — same color palette as Junto so the eye learns one
// rank language across the card. Visibility threshold is 5 so the bronze
// floor is never "missing".
function vouchedTier(count: number): 'bronze' | 'silver' | 'gold' {
  // Peer-judged tiers (Scott 2026-07-07): NOT gamification — you can't grind
  // them, others judge your conduct outing after outing. 30 people vouching a
  // way of being is a real reputation, worth distinguishing.
  if (count >= 30) return 'gold';
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

// Per-trait Lucide icons. Mapping per design spec.
const POSITIVE_TRAIT_ICON: Record<string, LucideIcon> = {
  punctual: Clock,
  prepared: Package,
  conciliant: Handshake,
  prudent: Shield,
};
const NEGATIVE_TRAIT_ICON: Record<string, LucideIcon> = {
  unprepared: Package,
  aggressive: AlertTriangle,
  reckless: Ban,
  // Anticipated future negative keys — design spec listed them. Mapped
  // here so the popup renders correctly if/when they're added.
  lacheur: LogOut,
  surestime: TrendingUp,
};

// level_accurate is deprecated. Hidden everywhere.
const DEPRECATED_PEER_KEYS = new Set(['level_accurate']);

interface VouchedItem {
  key: string;
  label: string;
  count: number;
  lastAt: string | null;
}
interface WarningItem {
  key: string;
  label: string;
  count: number;
  severity: 'amber' | 'red';
}
interface JuntoAward {
  id: string;
  Icon: LucideIcon;
  count: number;
  tier: 'bronze' | 'silver' | 'gold';
  // Thresholds carried over from the AwardDef so the popover can compute
  // a "next tier" hint without re-walking the AWARDS array.
  outings: [number, number, number];
  minDistinct?: [number, number, number];
  distinctSports?: number;
  // Sentence parts from the AwardDef so the hero card can render
  // "{nounAction} {count} {nounObject}." without a label lookup.
  nounAction: string;
  nounObject: string;
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
  // Phrasing for the popup hero card sentence:
  //   "{nounAction} {count} {nounObject}." (e.g. "A créé 23 activités pour la communauté.")
  nounAction: string;
  nounObject: string;
  evaluate: (a: AwardAggregates) => AwardEval;
}

const AWARDS: AwardDef[] = [
  {
    id: 'joined',
    Icon: Users,
    nounAction: 'A rejoint',
    nounObject: "activités créées par d'autres",
    outings: [5, 20, 50],
    evaluate: (a) => ({ count: a.joined }),
  },
  {
    id: 'created',
    Icon: Hammer,
    nounAction: 'A créé',
    nounObject: 'activités pour la communauté',
    outings: [5, 20, 50],
    evaluate: (a) => ({ count: a.created }),
  },
  {
    id: 'polyvalent',
    Icon: Compass,
    nounAction: 'A pratiqué',
    nounObject: 'sports différents',
    outings: [3, 5, 8],
    evaluate: (a) => ({ count: a.distinct_sports }),
  },
  {
    id: 'aventurier',
    Icon: Tent,
    nounAction: 'A complété',
    nounObject: 'sorties multi-jours',
    outings: [1, 3, 5],
    evaluate: (a) => ({ count: a.multi_day_count }),
  },
  // Themed — by sports.category. The `minDistinct` floor stops a single sport
  // from carrying the whole tier.
  {
    id: 'aquatique',
    Icon: Waves,
    nounAction: 'A réalisé',
    nounObject: 'sorties aquatiques',
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
    nounAction: 'A réalisé',
    nounObject: 'sorties en montagne',
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
    nounAction: 'A réalisé',
    nounObject: 'sorties sur route',
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
    nounAction: 'A réalisé',
    nounObject: 'sorties de sports aériens',
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
  declaredLevel: string | null;
  // Universe category (mountain/water/air/cycling/on-foot) → tint color.
  category: string | null;
}

type DetailTarget =
  | { kind: 'vouched'; item: VouchedItem }
  | { kind: 'warning'; item: WarningItem }
  | { kind: 'sport'; item: SportItem }
  | { kind: 'award'; item: JuntoAward };

export function BadgeDisplay({ userId, reputation, trophies, sportLevels = [], sportLevelVotes = [], awardAggregates, declaredSports = [], declaredLevels = null, editable = false, onEditSports }: BadgeDisplayProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [selected, setSelected] = useState<DetailTarget | null>(null);
  const [showHelp, setShowHelp] = useState(false);
  const [showAllSports, setShowAllSports] = useState(false);
  // Cached reference list (staleTime Infinity) — used to map a sport key to its
  // universe category for the popover's tint.
  const { data: allSports } = useSports();
  const categoryByKey = useMemo(
    () => new Map((allSports ?? []).map((s) => [s.key, s.category])),
    [allSports],
  );

  const { vouched, warnings, sports } = useMemo(() => {
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
          lastAt: rep.last_at ?? null,
        });
      } else if (NEGATIVE_KEYS.has(rep.badge_key)) {
        if (count < WARNING_THRESHOLD) continue;
        warningList.push({
          key: rep.badge_key,
          label: t(`badges.${rep.badge_key}`, { defaultValue: rep.badge_key }),
          count,
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
          declaredLevel: declaredLevels?.[tr.sport_key as string] ?? null,
          category: categoryByKey.get(tr.sport_key as string) ?? null,
        };
      })
      .sort((a, b) => b.count - a.count);

    // Merge declared sports with NO qualifying outings so the profile says
    // something useful from day one (cold-start) — level only, no ×count.
    const withOutings = new Set(sportList.map((s) => s.sportKey));
    for (const key of declaredSports ?? []) {
      if (withOutings.has(key)) continue;
      sportList.push({
        sportKey: key,
        count: 0,
        label: t(`sports.${key}`, { defaultValue: key }),
        dots: 0,
        lastAt: null,
        firstAt: null,
        levelVotes: levelVotesByKey.get(key),
        declaredLevel: declaredLevels?.[key] ?? null,
        category: categoryByKey.get(key) ?? null,
      });
    }

    // Junto awards — iterate the data-driven AWARDS list, surface only the
    // ones the user has earned at least bronze on. Carry the def's
    // thresholds + distinctSports onto the item so the popover can compute
    // a "next tier" hint.
    const awardsList: JuntoAward[] = [];
    if (awardAggregates) {
      for (const def of AWARDS) {
        const evald = evaluateAward(def, awardAggregates);
        if (evald.tier) {
          const distinctSports = def.evaluate(awardAggregates).distinctSports;
          awardsList.push({
            id: def.id,
            Icon: def.Icon,
            count: evald.count,
            tier: evald.tier,
            outings: def.outings,
            minDistinct: def.minDistinct,
            distinctSports,
            nounAction: def.nounAction,
            nounObject: def.nounObject,
          });
        }
      }
    }

    return { vouched: vouchedList, warnings: warningList, sports: sportList, awards: awardsList };
  }, [reputation, trophies, sportLevels, sportLevelVotes, awardAggregates, declaredSports, declaredLevels, categoryByKey, t]);

  const hasPeer = vouched.length > 0 || warnings.length > 0;

  // Card now always renders — empty sections show a pedagogical placeholder
  // so a brand-new user understands what each section will eventually hold,
  // even before any data exists.

  const SPORTS_LIMIT = 6;
  const visibleSports = showAllSports ? sports : sports.slice(0, SPORTS_LIMIT);
  const hiddenSportsCount = sports.length - visibleSports.length;

  return (
    <>
      {/* ── Sports pratiqués ── its own card ── */}
      <View style={styles.card}>
        <View style={styles.section}>
          <SectionHeader
            Icon={Mountain}
            label={t('profil.badgeSectionSports')}
            styles={styles}
            colors={colors}
          />
          {sports.length > 0 || editable ? (
            <>
              <SportRow
                items={visibleSports}
                styles={styles}
                colors={colors}
                onPress={(item) => setSelected({ kind: 'sport', item })}
                editable={editable}
                onEdit={onEditSports}
                t={t}
              />
              {hiddenSportsCount > 0 && (
                <Pressable onPress={() => setShowAllSports(true)} hitSlop={6} style={styles.seeAllBtn}>
                  <Text style={styles.seeAllText}>
                    {t('profil.sportsSeeAll', { defaultValue: 'Voir tout ({{count}})', count: sports.length })}
                  </Text>
                </Pressable>
              )}
            </>
          ) : (
            <Text style={styles.emptyHint}>{t('profil.badgeEmptySports')}</Text>
          )}
        </View>
      </View>

      {/* ── Ses partenaires disent… ── its own card ── */}
      <View style={styles.card}>
        <Pressable
          style={styles.helpButton}
          onPress={() => setShowHelp(true)}
          hitSlop={10}
        >
          <HelpCircle size={16} color={colors.textMuted} strokeWidth={2} />
        </Pressable>
        <View style={styles.section}>
          <SectionHeader
            Icon={Users}
            label={t('profil.badgeSectionPeer')}
            styles={styles}
            colors={colors}
          />
          {hasPeer ? (
            <>
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
            </>
          ) : (
            <Text style={styles.emptyHint}>{t('profil.badgeEmptyPeer')}</Text>
          )}
        </View>
      </View>

      <DetailModal
        target={selected}
        userId={userId}
        onClose={() => setSelected(null)}
        styles={styles}
        colors={colors}
        t={t}
      />

      <Modal visible={showHelp} animationType="fade" transparent onRequestClose={() => setShowHelp(false)}>
        <Pressable style={styles.helpBackdrop} onPress={() => setShowHelp(false)}>
          <Pressable style={styles.helpCard} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.helpTitle}>{t('profil.badgeHelp.title')}</Text>
            <Text style={styles.helpBody}>{t('profil.badgeHelp.intro')}</Text>

            <Text style={styles.helpHeading}>{t('profil.badgeSectionPeer')}</Text>
            <Text style={styles.helpBody}>{t('profil.badgeHelp.peer')}</Text>

            <Text style={styles.helpHeading}>{t('profil.badgeSectionAuto')}</Text>
            <Text style={styles.helpBody}>{t('profil.badgeHelp.junto')}</Text>

            <Text style={styles.helpHeading}>{t('profil.badgeSectionSports')}</Text>
            <Text style={styles.helpBody}>{t('profil.badgeHelp.sports')}</Text>

            <Pressable style={styles.helpDismiss} onPress={() => setShowHelp(false)}>
              <Text style={styles.helpDismissText}>{t('common.close', { defaultValue: 'OK' })}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </>
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
            <Text style={[styles.lineCountText, { color: tierColor }]}>{it.count}</Text>
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
  colors,
  onPress,
  editable,
  onEdit,
  t,
}: {
  items: SportItem[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: (item: SportItem) => void;
  editable?: boolean;
  onEdit?: () => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  return (
    <View style={styles.wrapRowChips}>
      {items.map((it) => {
        // ×N · niveau · triangle — count first (glued to the emoji, "12 sorties
        // d'escalade"), then the declared level + peer-confirmation triangle as
        // their own unit so the number never reads as a rating of the level.
        const lvl = levelLabel(it.declaredLevel);
        const tri = sportTriangle(it.levelVotes);
        return (
          <Pressable
            key={it.sportKey}
            onPress={() => onPress(it)}
            hitSlop={4}
            style={({ pressed }) => [styles.sportChipPill, pressed && styles.tappedDim]}
          >
            <Text style={styles.sportEmoji}>{getSportIcon(it.sportKey)}</Text>
            {it.count > 0 && <Text style={styles.sportCountInline}>×{it.count}</Text>}
            {lvl && it.count > 0 && <View style={styles.sportSep} />}
            {lvl && <Text style={styles.sportLevelText}>{lvl}</Text>}
            {tri && (tri.kind === 'even' ? (
              // Judged but split — a neutral grey bar (a triangle would imply
              // a direction the votes don't support).
              <Minus size={tri.size} color={colors.textMuted} strokeWidth={3} />
            ) : (
              <Triangle
                size={tri.size}
                color={tri.kind === 'up' ? colors.success : colors.error}
                fill={tri.kind === 'up' ? colors.success : colors.error}
                strokeWidth={0}
                style={tri.kind === 'down' ? styles.triDown : undefined}
              />
            ))}
          </Pressable>
        );
      })}
      {editable && (
        <Pressable
          onPress={onEdit}
          hitSlop={4}
          style={({ pressed }) => [styles.sportAddChip, pressed && styles.tappedDim]}
        >
          <Plus size={13} color={colors.cta} strokeWidth={2.6} />
          <Text style={styles.sportAddText}>{t('profil.addSport', { defaultValue: 'Ajouter' })}</Text>
        </Pressable>
      )}
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
            <Text style={[styles.lineCountText, { color: tierColor }]}>{it.count}</Text>
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

// ---------------------------------------------------------------------------
// Modal shell — drag handle + optional 3px top accent rule (Warning only).
// No default OK button; only Warning has one (production behaviour preserved).
// Closes on backdrop tap. Per the design handoff (POPUPS_HANDOFF.md §3).
// ---------------------------------------------------------------------------
function ModalShell({
  visible,
  onClose,
  tone,
  padded = true,
  styles,
  children,
}: {
  visible: boolean;
  onClose: () => void;
  tone?: 'amber' | 'red';
  padded?: boolean;
  styles: ReturnType<typeof createStyles>;
  children: React.ReactNode;
}) {
  const accentBar =
    tone === 'red' ? COLOR_RED :
    tone === 'amber' ? COLOR_AMBER :
    null;
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.modalBackdrop} onPress={onClose}>
        <Pressable style={styles.modalCard} onPress={(e) => e.stopPropagation()}>
          {accentBar && <View style={[styles.modalAccentBar, { backgroundColor: accentBar }]} />}
          <View style={styles.modalDragHandleWrap}>
            <View style={styles.modalDragHandle} />
          </View>
          <View style={padded ? styles.modalContent : undefined}>
            {children}
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

function DetailModal({
  target,
  userId,
  onClose,
  styles,
  colors,
  t,
}: {
  target: DetailTarget | null;
  userId: string;
  onClose: () => void;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  if (!target) return null;
  const tone =
    target.kind === 'warning'
      ? (target.item.severity === 'red' ? 'red' : 'amber')
      : undefined;
  return (
    <ModalShell visible onClose={onClose} tone={tone} styles={styles}>
      {target.kind === 'vouched' && (
        <VouchedDetail
          item={target.item}
          userId={userId}
          styles={styles}
          colors={colors}
          t={t}
        />
      )}
      {target.kind === 'warning' && (
        <WarningDetail item={target.item} styles={styles} t={t} />
      )}
      {target.kind === 'award' && (
        <AwardDetail item={target.item} styles={styles} colors={colors} t={t} />
      )}
      {target.kind === 'sport' && (
        <SportDetail item={target.item} styles={styles} colors={colors} />
      )}
    </ModalShell>
  );
}

// ---------------------------------------------------------------------------
// Vouched popup (P2) — caption · title row (icon + label + ×count) ·
// pull-quote card with avatar stack + "Voir tous" · description.
// Spec: POPUPS_HANDOFF.md §4.1.
// ---------------------------------------------------------------------------
function VouchedDetail({
  item,
  userId,
  styles,
  colors,
  t,
}: {
  item: VouchedItem;
  userId: string;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  const Icon = POSITIVE_TRAIT_ICON[item.key];
  const accent = COLOR_SUCCESS;
  const description = t(`badges.peerDesc.${item.key}`, { defaultValue: '' });
  // Earned rank → a cup sized and coloured by tier, in the header's right space.
  const tier = vouchedTier(item.count);
  const tierColor = TIER_COLOR[tier];
  const trophySize = tier === 'gold' ? 40 : tier === 'silver' ? 33 : 26;

  // Lazy fetch the most recent voters for this trait. Avatars only —
  // no nav click-through. Privacy stance: voter identity is exposed
  // visually to strengthen the trust signal (see mig 00169 comment).
  const { data: voters = [] } = useQuery<BadgeVoter[]>({
    queryKey: ['badgeVoters', userId, item.key],
    queryFn: () => badgeService.getVotersForBadge(userId, item.key),
    enabled: !!userId,
    staleTime: 5 * 60_000,
  });
  const visibleVoters = voters.slice(0, MAX_VISIBLE_VOTER_AVATARS);
  // Overflow counts UNIQUE voters not yet shown — not raw vote count.
  // The RPC (mig 00171) returns deduped voters, so voters.length is the
  // true unique count. The "12 votes" label below uses item.count, which
  // does include duplicate votes — those are two different signals.
  const uniqueOverflow = Math.max(0, voters.length - visibleVoters.length);

  return (
    <>
      <Text style={styles.popupCaption}>{t('badges.vouchedCaption', { defaultValue: 'Décerné par les pairs' })}</Text>

      <View style={styles.vouchedTitleRow}>
        {Icon && <Icon size={20} color={accent} strokeWidth={2} />}
        <Text style={styles.vouchedTitle} numberOfLines={1}>{item.label}</Text>
        <Text style={styles.vouchedCountMono}>×{item.count}</Text>
        <View style={styles.vouchedTitleSpacer} />
        <Trophy size={trophySize} color={tierColor} fill={tierColor + '2E'} strokeWidth={1.7} />
      </View>

      {/* Description first — Scott's call: text precedes the voter card so
          the reader sees what the trait MEANS before seeing who agrees. */}
      {description !== '' && <Text style={styles.vouchedDescription}>{description}</Text>}

      <View style={[styles.pullQuoteCard, { borderLeftColor: accent }]}>
        <View style={styles.pullQuoteAvatars}>
          <View style={styles.pullQuoteAvatarsLeft}>
            <VoterAvatarStack
              voters={visibleVoters}
              ringColor={colors.surface}
            />
            {/* "..." rendered whenever ≥1 avatar exists — Scott's call:
                visual separator regardless of overflow state. */}
            {visibleVoters.length > 0 && (
              <Text style={styles.pullQuoteEllipsis}>...</Text>
            )}
            {uniqueOverflow > 0 && (
              <Text style={styles.pullQuoteOverflow}>+{uniqueOverflow}</Text>
            )}
          </View>
          <Text style={styles.pullQuotePeersLabel}>
            <Text style={[styles.pullQuotePeersCount, { color: accent }]}>{item.count}</Text>
            {' '}{t('badges.vouchedVotesLabel', { count: item.count, defaultValue: 'votes' })}
          </Text>
        </View>
      </View>
    </>
  );
}

// ---------------------------------------------------------------------------
// Warning popup (W1 header + production grammar) — left-aligned icon-square
// + label + ×count + mono caption ("SIGNALÉ" / "À ÉVITER") · centered
// description · italic decay note · OK button. Spec: §4.2.
// ---------------------------------------------------------------------------
function WarningDetail({
  item,
  styles,
  t,
}: {
  item: WarningItem;
  styles: ReturnType<typeof createStyles>;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  const isRed = item.severity === 'red';
  const accent = isRed ? COLOR_RED : COLOR_AMBER;
  const Icon = NEGATIVE_TRAIT_ICON[item.key] ?? (isRed ? OctagonAlert : AlertTriangle);
  const description = t(`badges.peerDesc.${item.key}`, { defaultValue: '' });
  const caption = t(isRed ? 'badges.warning.avoid' : 'badges.warning.signaled');
  return (
    <>
      <View style={styles.warningHeaderRow}>
        <View style={[styles.warningHeaderIconSquare, { backgroundColor: accent + '1F' }]}>
          <Icon size={18} color={accent} strokeWidth={1.8} />
        </View>
        <View style={styles.warningHeaderRight}>
          <View style={styles.warningHeaderTitleRow}>
            <Text style={styles.warningHeaderTitle}>{item.label}</Text>
            <Text style={styles.warningHeaderCountMono}>×{item.count}</Text>
          </View>
          <Text style={[styles.warningHeaderCaption, { color: accent }]}>{caption}</Text>
        </View>
      </View>

      {description !== '' && <Text style={styles.warningDescription}>{description}</Text>}

      <Text style={styles.warningDecayNote}>{t('badges.peerNegativeHint')}</Text>
    </>
  );
}

// ---------------------------------------------------------------------------
// Award popup (A3) — gradient hero card with tier-color border, icon disk,
// "Décerné par Junto" caption, tier-specific French label, sentence-stat
// with big count. Below: progression list with three tier rows + footer
// "X de plus pour {next}". Spec: §4.3.
// ---------------------------------------------------------------------------
function AwardDetail({
  item,
  styles,
  colors,
  t,
}: {
  item: JuntoAward;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  const tierColor = TIER_COLOR[item.tier];
  const Icon = item.Icon;
  const awardLabel = t(`badges.awardLabel.${item.id}.${item.tier}`, { defaultValue: item.id });
  // Sentence stat parts (e.g. "A créé" + count + "activités pour la communauté.")
  const nounAction = item.nounAction ?? '';
  const nounObject = item.nounObject ?? '';

  const tierKeys: ('bronze' | 'silver' | 'gold')[] = ['bronze', 'silver', 'gold'];
  const currentIndex = tierKeys.indexOf(item.tier);

  return (
    <>
      <View style={[
        styles.awardHeroCard,
        { backgroundColor: tierColor + '14', borderColor: tierColor + '55' },
      ]}>
        <View style={styles.awardHeroTopRow}>
          <View style={[
            styles.awardHeroIconDisk,
            { backgroundColor: tierColor + '40', borderColor: tierColor },
          ]}>
            <Icon size={18} color={tierColor} strokeWidth={1.8} />
          </View>
          <View style={styles.awardHeroTopRight}>
            <Text style={styles.popupCaption}>
              {t('badges.awardCaption', { defaultValue: 'Décerné par Junto' })}
            </Text>
            <Text style={[styles.awardHeroLabel, { color: tierColor }]}>{awardLabel}</Text>
          </View>
        </View>
        <Text style={styles.awardSentence}>
          {nounAction}{' '}
          <Text style={[styles.awardSentenceCount, { color: tierColor }]}>{item.count}</Text>
          {' '}{nounObject}.
        </Text>
      </View>

      <Text style={[styles.popupCaption, styles.awardProgressionCaption]}>
        {t('badges.awardProgression', { defaultValue: 'Progression' })}
      </Text>
      <View style={styles.awardProgressionRow}>
        {tierKeys.map((tk, i) => {
          const reached = i <= currentIndex;
          const tcolor = TIER_COLOR[tk];
          const tlabel = t(`badges.awardLabel.${item.id}.${tk}`, { defaultValue: tk });
          const threshold = item.outings[i];
          // Each column owns half a bar on each side. The neighboring
          // column owns the matching half, so colors must match between
          // (col i right-half) and (col i+1 left-half) for the bar to
          // read as continuous when reached.
          // Bars use a single neutral "reached" color — tinting them
          // with the tier color competes with the dots and reads as a
          // hot, flat segment. textSecondary is muted enough to recede
          // and still convey progress, line stays for unreached.
          const leftBarReached = i > 0 && i <= currentIndex;
          const leftBarColor = leftBarReached ? colors.textSecondary : colors.line;
          const rightBarReached = i < tierKeys.length - 1 && (i + 1) <= currentIndex;
          const rightBarColor = rightBarReached ? colors.textSecondary : colors.line;
          return (
            <View key={tk} style={styles.awardProgressionColumn}>
              <Text style={[
                styles.awardProgressionThreshold,
                { color: reached ? tcolor : colors.textMuted },
              ]}>+{threshold}</Text>
              <View style={styles.awardProgressionDotRow}>
                <View
                  style={[
                    styles.awardProgressionHalfBar,
                    { backgroundColor: i > 0 ? leftBarColor : 'transparent' },
                  ]}
                />
                <View
                  style={[
                    styles.awardProgressionDot,
                    reached
                      ? { backgroundColor: tcolor }
                      : { borderWidth: 1.5, borderColor: colors.line },
                  ]}
                >
                  {reached && <Check size={12} color={colors.background} strokeWidth={3} />}
                </View>
                <View
                  style={[
                    styles.awardProgressionHalfBar,
                    { backgroundColor: i < tierKeys.length - 1 ? rightBarColor : 'transparent' },
                  ]}
                />
              </View>
              <Text style={[
                styles.awardProgressionLabel,
                { color: reached ? tcolor : colors.textSecondary },
              ]}>{tlabel}</Text>
            </View>
          );
        })}
      </View>
    </>
  );
}

// ---------------------------------------------------------------------------
// Sport popup (S1) — sport identity row · big count headline · "AVIS DES
// PAIRS" caption · peer-level signal pill (3 states). No frequency, no
// last-sortie, no level dots. Spec: §4.4 + §4.5.
// ---------------------------------------------------------------------------
function SportDetail({
  item,
  styles,
  colors,
}: {
  item: SportItem;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}) {
  const { t } = useTranslation();
  const lv = item.levelVotes;
  const justeCount = lv?.right ?? 0;
  const overCount = lv?.over ?? 0;
  // Same split as the chip triangle: fiable = juste + sous-estimé, gonflé = over.
  const fiable = justeCount + (lv?.under ?? 0);
  const gonfle = overCount;

  const accent = sportCategoryColor(item.category, '#4B7CB8');

  return (
    <>
      <View style={styles.sportIdentityRow}>
        <View style={[styles.sportEmojiSquare, { backgroundColor: accent + '1F', borderColor: accent + '40' }]}>
          <Text style={styles.sportEmojiBig}>{getSportIcon(item.sportKey)}</Text>
        </View>
        <View style={styles.sportIdentityText}>
          <Text style={styles.sportName}>{item.label}</Text>
          {item.count > 0 && (
            <Text style={styles.sportOutingsSub}>
              {t('badges.sportOutingsHeadline', {
                count: item.count,
                defaultValue: item.count > 1 ? '{{count}} sorties terminées' : '{{count}} sortie terminée',
              })}
            </Text>
          )}
        </View>
      </View>

      <Text style={[styles.popupCaption, styles.sportPeerCaption]}>
        {t('badges.peerOpinionCaption', { defaultValue: 'Avis des pairs' })}
      </Text>

      {/* Raw vote breakdown — green up = fiable, red down = gonflé. The old
          summary pill was redundant with these and used inconsistent logic
          (ignored sous-estimé, no grey tie) — removed. */}
      <View style={styles.sportVoteRow}>
        <View style={styles.sportVoteItem}>
          <Triangle size={14} color={colors.success} fill={colors.success} strokeWidth={0} />
          <Text style={[styles.sportVoteNum, { color: colors.success }]}>{fiable}</Text>
        </View>
        <View style={styles.sportVoteItem}>
          <Triangle size={14} color={colors.error} fill={colors.error} strokeWidth={0} style={styles.triDown} />
          <Text style={[styles.sportVoteNum, { color: colors.error }]}>{gonfle}</Text>
        </View>
      </View>
    </>
  );
}

// Peer-level signal pill — 3 states from net votes. Spec: §4.5.
function PeerLevelSignal({
  juste,
  over,
  styles,
  colors,
  t,
}: {
  juste: number;
  over: number;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  const total = juste + over;
  if (total < 3) {
    return (
      <View style={[
        styles.peerLevelPill,
        { backgroundColor: colors.surfaceAlt, borderColor: colors.line },
      ]}>
        <Users size={14} color={colors.textSecondary} strokeWidth={1.8} />
        <Text style={[styles.peerLevelTitle, { color: colors.textSecondary }]}>
          {t('badges.peerLevelNeutral', { defaultValue: 'Pas encore assez de retours' })}
        </Text>
        <Text style={styles.peerLevelSub}>
          {' '}· {t('badges.peerLevelTotal', { count: total, defaultValue: `${total} retour(s)` })}
        </Text>
      </View>
    );
  }
  const positive = juste >= over;
  const accent = positive ? COLOR_SUCCESS : COLOR_RED;
  const StateIcon = positive ? Check : AlertTriangle;
  const title = positive
    ? t('badges.peerLevelPositive', { defaultValue: 'Niveau juste' })
    : t('badges.peerLevelNegative', { defaultValue: 'Surestime son niveau' });
  const sub = positive
    ? t('badges.peerLevelPositiveSub', { count: juste, defaultValue: `${juste} pair(s) valident` })
    : t('badges.peerLevelNegativeSub', { count: over, defaultValue: `${over} signalement(s)` });
  return (
    <View style={[
      styles.peerLevelPill,
      { backgroundColor: accent + '1A', borderColor: accent + '59' },
    ]}>
      <StateIcon size={14} color={accent} strokeWidth={1.8} />
      <Text style={[styles.peerLevelTitle, { color: accent }]}>{title}</Text>
      <Text style={styles.peerLevelSub}> · {sub}</Text>
    </View>
  );
}

// ---------------------------------------------------------------------------
// Voter avatar stack — real profile pictures of recent voters. Falls back
// to a hashed-color disk + first letter when avatar_url is null. Display
// only, no nav click-through (privacy stance: faces visible to strengthen
// the trust signal, but no doxxing path).
// ---------------------------------------------------------------------------
function VoterAvatarStack({
  voters,
  size = 22,
  overlap = 7,
  ringColor,
}: {
  voters: BadgeVoter[];
  size?: number;
  overlap?: number;
  ringColor: string;
}) {
  return (
    <View style={{ flexDirection: 'row' }}>
      {voters.map((v, i) => {
        const initial = (v.display_name?.trim()?.[0] ?? '?').toUpperCase();
        const ring = {
          width: size,
          height: size,
          borderRadius: size / 2,
          borderWidth: 2,
          borderColor: ringColor,
          marginLeft: i === 0 ? 0 : -overlap,
          overflow: 'hidden' as const,
          alignItems: 'center' as const,
          justifyContent: 'center' as const,
        };
        if (v.avatar_url) {
          return (
            <Image
              key={v.voter_id}
              source={{ uri: v.avatar_url }}
              style={ring}
              contentFit="cover"
            />
          );
        }
        return (
          <View
            key={v.voter_id}
            style={[ring, { backgroundColor: hashHue(v.voter_id) }]}
          >
            <Text style={{
              color: '#FFFFFF',
              fontSize: size * 0.42,
              fontWeight: '700',
              letterSpacing: -0.4,
            }}>{initial}</Text>
          </View>
        );
      })}
    </View>
  );
}

// Deterministic muted hue from a voter UUID — keeps fallback disks stable
// across renders without storing per-user color anywhere.
function hashHue(seed: string): string {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) | 0;
  return `hsl(${Math.abs(h) % 360}, 35%, 55%)`;
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

// Formats frequency as a whole-number phrase. Above ~0.75/mo, we round
// to integer outings/month; below that we invert to "1 every X months".
function formatFrequencyLabel(
  count: number,
  firstAt: string | null,
  t: (k: string, opts?: Record<string, unknown>) => string,
): string | null {
  const freq = computeFrequency(count, firstAt);
  if (freq == null) return null;
  if (freq >= 0.75) {
    const perMonth = Math.max(1, Math.round(freq));
    return t('badges.frequencyPerMonth', {
      count: perMonth,
      defaultValue: `${perMonth} sortie/mois en moyenne`,
    });
  }
  const monthsPer = Math.max(2, Math.round(1 / freq));
  return t('badges.frequencyEveryMonths', {
    count: monthsPer,
    defaultValue: `1 sortie tous les ${monthsPer} mois`,
  });
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

const COLOR_AMBER = '#E8A33D';
const COLOR_RED = '#E5524E';
const COLOR_SUCCESS = '#7EC8A3';

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
    emptyHint: {
      color: colors.textMuted,
      fontSize: 12,
      fontStyle: 'italic',
      lineHeight: 17,
    },
    seeAllBtn: {
      marginTop: spacing.sm,
      alignSelf: 'flex-start',
    },
    seeAllText: {
      color: colors.cta,
      fontSize: 13,
      fontWeight: '700',
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
      borderRadius: 999,
      paddingVertical: 6,
      paddingHorizontal: 11,
    },
    sportEmoji: {
      fontSize: 16,
      lineHeight: 18,
    },
    sportCountInline: {
      color: '#4B7CB8',
      fontSize: 13,
      fontWeight: '800',
      letterSpacing: -0.02,
    },
    sportSep: {
      width: 3,
      height: 3,
      borderRadius: 2,
      backgroundColor: colors.textMuted,
      opacity: 0.5,
    },
    sportLevelText: {
      color: colors.textPrimary,
      fontSize: 13,
      fontWeight: '700',
    },
    triDown: {
      transform: [{ rotate: '180deg' }],
    },
    sportVoteRow: {
      flexDirection: 'row',
      gap: spacing.lg,
      marginTop: spacing.sm,
      marginBottom: spacing.sm,
    },
    sportVoteItem: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
    },
    sportVoteNum: {
      fontSize: 17,
      fontWeight: '800',
      letterSpacing: -0.02,
    },
    sportAddChip: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
      borderRadius: 999,
      borderWidth: 1,
      borderColor: colors.cta,
      borderStyle: 'dashed',
      paddingVertical: 6,
      paddingHorizontal: 11,
    },
    sportAddText: {
      color: colors.cta,
      fontSize: 13,
      fontWeight: '700',
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
      // Same blue as the "joined" stat in the hero — informational, not
      // call-to-action. CTA orange was reading as "tap me" pressure.
      color: '#4B7CB8',
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
      borderRadius: 20,
      paddingTop: 0,
      paddingBottom: 0,
      paddingHorizontal: 0,
      borderWidth: 1,
      borderColor: colors.line,
      overflow: 'hidden',
    },
    modalAccentBar: {
      height: 3,
    },
    modalDragHandleWrap: {
      alignItems: 'center',
      paddingTop: 10,
    },
    modalDragHandle: {
      width: 36,
      height: 4,
      borderRadius: 2,
      backgroundColor: 'rgba(255,255,255,0.10)',
    },
    modalContent: {
      paddingHorizontal: 22,
      paddingTop: 18,
      paddingBottom: 22,
    },
    // Caption mono — small uppercase letter-spaced label used in several
    // popups ("DÉCERNÉ PAR LES PAIRS", "DÉCERNÉ PAR JUNTO", "AVIS DES
    // PAIRS", "PROGRESSION", "VOUCHS REÇUS").
    popupCaption: {
      color: colors.textMuted,
      fontSize: 9.5,
      fontWeight: '700',
      letterSpacing: 1.5,
      textTransform: 'uppercase',
    },

    // ── Vouched popup ────────────────────────────────────────────────
    vouchedTitleRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 9,
      marginTop: 8,
      marginBottom: 16,
    },
    vouchedTitle: {
      fontSize: 22,
      fontWeight: '800',
      letterSpacing: -0.5,
      color: colors.textPrimary,
      flexShrink: 1,
    },
    vouchedTitleSpacer: {
      flex: 1,
      minWidth: 8,
    },
    vouchedCountMono: {
      fontSize: 13,
      fontWeight: '600',
      color: colors.textMuted,
      letterSpacing: 0.2,
    },
    pullQuoteCard: {
      borderRadius: 14,
      borderLeftWidth: 3,
      backgroundColor: 'rgba(126,200,163,0.08)',
      paddingTop: 14,
      paddingRight: 18,
      paddingBottom: 14,
      paddingLeft: 18,
      marginBottom: 4,
    },
    pullQuoteAvatars: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 10,
      flexWrap: 'wrap',
    },
    pullQuoteAvatarsLeft: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      flexShrink: 1,
    },
    pullQuotePeersLabel: {
      fontSize: 12.5,
      fontWeight: '500',
      color: colors.textSecondary,
    },
    pullQuotePeersCount: {
      fontWeight: '700',
    },
    pullQuoteEllipsis: {
      fontSize: 14,
      fontWeight: '700',
      color: colors.textMuted,
      letterSpacing: 1,
      marginLeft: -2,
    },
    pullQuoteOverflow: {
      fontSize: 12.5,
      fontWeight: '700',
      color: colors.textSecondary,
    },
    vouchedDescription: {
      fontSize: 15,
      lineHeight: 22,
      fontStyle: 'italic',
      color: colors.textPrimary,
      opacity: 0.82,
      marginBottom: 16,
    },

    // ── Warning popup ────────────────────────────────────────────────
    warningHeaderRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      marginBottom: 18,
    },
    warningHeaderIconSquare: {
      width: 36,
      height: 36,
      borderRadius: 10,
      alignItems: 'center',
      justifyContent: 'center',
    },
    warningHeaderRight: {
      flex: 1,
      minWidth: 0,
    },
    warningHeaderTitleRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
    },
    warningHeaderTitle: {
      fontSize: 19,
      fontWeight: '800',
      letterSpacing: -0.4,
      color: colors.textPrimary,
    },
    warningHeaderCountMono: {
      fontSize: 12,
      fontWeight: '600',
      color: colors.textMuted,
      letterSpacing: 0.2,
    },
    warningHeaderCaption: {
      fontSize: 9.5,
      fontWeight: '700',
      letterSpacing: 1.5,
      textTransform: 'uppercase',
      marginTop: 3,
    },
    warningDescription: {
      fontSize: 14.5,
      lineHeight: 22,
      color: colors.textPrimary,
      textAlign: 'center',
      paddingHorizontal: 4,
    },
    warningDecayNote: {
      marginTop: 16,
      fontSize: 12,
      lineHeight: 18,
      fontStyle: 'italic',
      color: colors.textMuted,
      textAlign: 'center',
      paddingHorizontal: 8,
    },
    // ── Award popup ──────────────────────────────────────────────────
    awardHeroCard: {
      borderRadius: 14,
      borderWidth: 1,
      paddingTop: 18,
      paddingHorizontal: 18,
      paddingBottom: 16,
      marginBottom: 14,
    },
    awardHeroTopRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
      marginBottom: 12,
    },
    awardHeroIconDisk: {
      width: 38,
      height: 38,
      borderRadius: 19,
      borderWidth: 1.5,
      alignItems: 'center',
      justifyContent: 'center',
    },
    awardHeroTopRight: {
      flex: 1,
      minWidth: 0,
    },
    awardHeroLabel: {
      fontSize: 21,
      fontWeight: '800',
      letterSpacing: -0.5,
      lineHeight: 24,
      marginTop: 2,
    },
    awardSentence: {
      fontSize: 15,
      lineHeight: 21,
      color: colors.textPrimary,
    },
    awardSentenceCount: {
      fontSize: 26,
      fontWeight: '800',
      letterSpacing: -0.6,
    },
    awardProgressionCaption: {
      marginBottom: 10,
    },
    // Horizontal progression — three equal-flex columns, each holding
    // [threshold (top) · dot+half-bars · label (bottom)]. The dot row
    // owns two half-bars (flex:1 each) flanking the dot, so adjacent
    // columns' half-bars meet at the column boundary, forming an
    // edge-to-edge line that visually starts and ends at dot centers.
    awardProgressionRow: {
      flexDirection: 'row',
      alignItems: 'flex-start',
      marginTop: 4,
    },
    awardProgressionColumn: {
      flex: 1,
      alignItems: 'center',
      gap: 4,
    },
    awardProgressionDotRow: {
      flexDirection: 'row',
      alignItems: 'center',
      alignSelf: 'stretch',
    },
    awardProgressionHalfBar: {
      flex: 1,
      height: 2,
      borderRadius: 1,
    },
    awardProgressionDot: {
      width: 22,
      height: 22,
      borderRadius: 11,
      alignItems: 'center',
      justifyContent: 'center',
    },
    awardProgressionLabel: {
      fontSize: 12,
      fontWeight: '700',
      textAlign: 'center',
    },
    awardProgressionThreshold: {
      fontSize: 11,
      fontWeight: '700',
      textAlign: 'center',
    },
    // ── Sport popup ──────────────────────────────────────────────────
    sportIdentityRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 12,
      marginBottom: 22,
    },
    sportIdentityText: {
      flex: 1,
      minWidth: 0,
    },
    sportOutingsSub: {
      fontSize: 13,
      fontWeight: '500',
      color: colors.textSecondary,
      marginTop: 2,
    },
    sportEmojiSquare: {
      width: 44,
      height: 44,
      borderRadius: 12,
      backgroundColor: 'rgba(75,124,184,0.12)',
      borderWidth: 1,
      borderColor: 'rgba(75,124,184,0.25)',
      alignItems: 'center',
      justifyContent: 'center',
    },
    sportEmojiBig: {
      fontSize: 24,
      lineHeight: 28,
    },
    sportName: {
      fontSize: 22,
      fontWeight: '800',
      letterSpacing: -0.5,
      color: colors.textPrimary,
    },
    sportHeadlineRow: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      gap: 8,
      marginBottom: 18,
    },
    sportHeadlineCount: {
      fontSize: 42,
      fontWeight: '800',
      letterSpacing: -1.6,
      lineHeight: 44,
      color: colors.textPrimary,
    },
    sportHeadlineLabel: {
      fontSize: 15,
      fontWeight: '500',
      color: colors.textSecondary,
      paddingBottom: 6,
    },
    sportPeerCaption: {
      marginBottom: 8,
    },
    peerLevelPill: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      paddingVertical: 10,
      paddingHorizontal: 14,
      borderRadius: 12,
      borderWidth: 1,
      flexWrap: 'wrap',
    },
    peerLevelTitle: {
      fontSize: 13,
      fontWeight: '600',
    },
    peerLevelSub: {
      fontSize: 12,
      fontWeight: '500',
      color: colors.textSecondary,
    },

    modalHeroIcon: {
      width: 56,
      height: 56,
      borderRadius: 28,
      alignSelf: 'center',
      alignItems: 'center',
      justifyContent: 'center',
      borderWidth: 1.5,
      marginBottom: 6,
    },
    modalChip: {
      alignSelf: 'center',
      paddingHorizontal: 10,
      paddingVertical: 3,
      borderRadius: 999,
      marginBottom: 4,
    },
    modalChipText: {
      fontSize: 11,
      fontWeight: '800',
      letterSpacing: 0.6,
      textTransform: 'uppercase',
    },
    // Vouched popup — leads with the testimony count. The big number is
    // the trust signal; the trait icon sits to its left so the eye reads
    // "icon + count + label" as one unit before the title.
    trustHeroRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 14,
      marginBottom: 8,
    },
    trustHeroIcon: {
      width: 44,
      height: 44,
      borderRadius: 22,
      alignItems: 'center',
      justifyContent: 'center',
      borderWidth: 1.5,
    },
    trustMetricBlock: {
      alignItems: 'flex-start',
    },
    trustMetricNumber: {
      fontSize: 32,
      fontWeight: '800',
      letterSpacing: -1,
      lineHeight: 36,
    },
    trustMetricLabel: {
      color: colors.textMuted,
      fontSize: 11,
      fontWeight: '600',
      letterSpacing: 0.4,
    },
    // Warning popup — severity banner replaces the hero+chip combo. One
    // strong colored bar reads as "this is the verdict" before anything
    // else.
    warningBanner: {
      alignSelf: 'center',
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      paddingHorizontal: 16,
      paddingVertical: 8,
      borderRadius: 8,
      marginBottom: 8,
    },
    warningBannerText: {
      color: '#FFFFFF',
      fontSize: 12.5,
      fontWeight: '800',
      letterSpacing: 1.4,
      textTransform: 'uppercase',
    },
    // Award popup — concrete behavior metric in tier color, replaces the
    // tier chip. The tier name itself moves to a quiet footer next to
    // the next-tier hint.
    awardMetric: {
      fontSize: 16,
      fontWeight: '700',
      textAlign: 'center',
      marginTop: 4,
      marginBottom: 4,
    },
    awardTierFooterRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
      marginTop: 8,
    },
    awardTierFooterText: {
      fontSize: 11,
      fontWeight: '800',
      letterSpacing: 1.2,
      textTransform: 'uppercase',
    },
    awardTierFooterSeparator: {
      color: colors.textMuted,
      fontSize: 11,
    },
    awardTierFooterMuted: {
      color: colors.textMuted,
      fontSize: 12,
      fontStyle: 'italic',
    },
    // Sport popup — emoji hero in a tinted circle. The sport popup carries
    // the strongest trust signal (concrete count + level + recency) so it
    // earns hero treatment.
    sportHero: {
      width: 56,
      height: 56,
      borderRadius: 28,
      alignSelf: 'center',
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: colors.surfaceAlt,
      marginBottom: 6,
    },
    sportHeroEmoji: {
      fontSize: 30,
      lineHeight: 36,
    },
    modalTitle: {
      color: colors.textPrimary,
      fontSize: 17,
      fontWeight: '800',
      marginBottom: 2,
      textAlign: 'center',
    },
    modalBody: {
      color: colors.textSecondary,
      fontSize: 13,
      lineHeight: 19,
      textAlign: 'center',
      marginTop: 6,
    },
    modalFooter: {
      color: colors.textMuted,
      fontSize: 12,
      fontStyle: 'italic',
      marginTop: 8,
      textAlign: 'center',
    },
    // Facts block — bordered card grouping the objective data lines
    // (count, last activity, frequency). Visually separates them from
    // the peer-validation stamp that sits beneath.
    factsBlock: {
      borderWidth: 1,
      borderColor: colors.line,
      borderRadius: 12,
      paddingVertical: spacing.sm + 2,
      paddingHorizontal: spacing.md,
      marginTop: 10,
      gap: 4,
      alignItems: 'center',
    },
    factsLine: {
      color: colors.textPrimary,
      fontSize: 13,
      fontWeight: '600',
      textAlign: 'center',
    },
    modalLevelSignal: {
      marginTop: 8,
      fontSize: 12.5,
      fontWeight: '700',
      textAlign: 'center',
      letterSpacing: -0.01,
    },
    // Peer-validation stamp — passport-stamp aesthetic. Tinted bg + colored
    // border + uppercase verdict + count. Centered. Sits as a deliberate
    // "this level has been certified" element, not just another text line.
    levelStamp: {
      alignSelf: 'center',
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      borderWidth: 1.5,
      borderRadius: 8,
      paddingVertical: 7,
      paddingHorizontal: 14,
      marginTop: 12,
    },
    levelStampText: {
      fontSize: 11,
      fontWeight: '800',
      letterSpacing: 1.2,
      textTransform: 'uppercase',
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

    // Help button (top-right ?) + its modal — same visual family as the
    // reliability help modal in profile-hero.
    helpButton: {
      position: 'absolute',
      top: 10,
      right: 10,
      width: 28,
      height: 28,
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 1,
    },
    helpBackdrop: {
      flex: 1,
      backgroundColor: 'rgba(0,0,0,0.55)',
      alignItems: 'center',
      justifyContent: 'center',
      padding: spacing.lg,
    },
    helpCard: {
      width: '100%',
      maxWidth: 380,
      backgroundColor: colors.surface,
      borderRadius: 18,
      borderWidth: 1,
      borderColor: colors.line,
      padding: spacing.lg,
      gap: 6,
    },
    helpTitle: {
      color: colors.textPrimary,
      fontSize: 17,
      fontWeight: '800',
      marginBottom: 2,
    },
    helpHeading: {
      color: colors.textPrimary,
      fontSize: 12,
      fontWeight: '700',
      marginTop: 10,
      letterSpacing: 1.2,
      textTransform: 'uppercase',
    },
    helpBody: {
      color: colors.textSecondary,
      fontSize: 13,
      lineHeight: 19,
    },
    helpDismiss: {
      alignSelf: 'center',
      marginTop: spacing.md,
      backgroundColor: colors.cta + '1F',
      borderRadius: 999,
      paddingHorizontal: 28,
      paddingVertical: 10,
    },
    helpDismissText: {
      color: colors.cta,
      fontSize: 13,
      fontWeight: '700',
    },
  });
