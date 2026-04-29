import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, ScrollView, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { AlertTriangle, OctagonAlert } from 'lucide-react-native';
import { spacing } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import {
  POSITIVE_BADGES,
  NEGATIVE_BADGES,
  type ReputationBadge,
  type Trophy as ReputationTrophy,
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
  // Kept for call-site compatibility — Phase 1 doesn't read them.
  completedCount?: number;
  createdCount?: number;
  showLocked?: boolean;
}

const VOUCHED_THRESHOLD = 5;
const WARNING_THRESHOLD = 5;
const WARNING_RED_THRESHOLD = 15;
const SPORT_THRESHOLD = 3;

const POSITIVE_KEYS = new Set<string>(POSITIVE_BADGES.map((b) => b.key));
const NEGATIVE_KEYS = new Set<string>(NEGATIVE_BADGES.map((b) => b.key));
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
interface SportItem {
  sportKey: string;
  count: number;
  label: string;
}

type DetailTarget =
  | { kind: 'vouched'; item: VouchedItem }
  | { kind: 'warning'; item: WarningItem }
  | { kind: 'sport'; item: SportItem };

export function BadgeDisplay({ reputation, trophies }: BadgeDisplayProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [selected, setSelected] = useState<DetailTarget | null>(null);

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

    const sportList: SportItem[] = trophies
      .filter((tr) => tr.category === 'sport' && tr.sport_key && tr.count >= SPORT_THRESHOLD)
      .map((tr) => ({
        sportKey: tr.sport_key as string,
        count: tr.count,
        label: t(`sports.${tr.sport_key}`, { defaultValue: tr.sport_key as string }),
      }))
      .sort((a, b) => b.count - a.count);

    return { vouched: vouchedList, warnings: warningList, sports: sportList };
  }, [reputation, trophies, t]);

  if (vouched.length === 0 && warnings.length === 0 && sports.length === 0) return null;

  return (
    <View style={styles.card}>
      {vouched.length > 0 && (
        <VouchedRow
          items={vouched}
          styles={styles}
          colors={colors}
          onPress={(item) => setSelected({ kind: 'vouched', item })}
        />
      )}

      {warnings.length > 0 && (
        <>
          {vouched.length > 0 && <View style={styles.divider} />}
          <WarningRow
            items={warnings}
            styles={styles}
            colors={colors}
            onPress={(item) => setSelected({ kind: 'warning', item })}
          />
        </>
      )}

      {sports.length > 0 && (
        <>
          {(vouched.length > 0 || warnings.length > 0) && <View style={styles.divider} />}
          <SportRow
            items={sports}
            styles={styles}
            colors={colors}
            onPress={(item) => setSelected({ kind: 'sport', item })}
          />
        </>
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
    <ScrollableLine
      styles={styles}
      colors={colors}
      prefix={<Text style={[styles.linePrefix, styles.linePrefixVouched]}>✓</Text>}
    >
      {items.map((it, i) => (
        <Pressable key={it.key} onPress={() => onPress(it)} hitSlop={6} style={styles.lineItem}>
          <Text style={styles.lineTraitText}>{it.label}</Text>
          <Text style={styles.lineCountText}>·{it.count}</Text>
          {i < items.length - 1 && <View style={styles.lineSpacer} />}
        </Pressable>
      ))}
    </ScrollableLine>
  );
}

// ---------------------------------------------------------------------------
// Warning row — `⚠ Trait signalé` (amber) or `⛔ Trait à éviter` (red)
// ---------------------------------------------------------------------------

function WarningRow({
  items,
  styles,
  colors,
  onPress,
}: {
  items: WarningItem[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: (item: WarningItem) => void;
}) {
  const { t } = useTranslation();
  return (
    <ScrollableLine styles={styles} colors={colors}>
      {items.map((it, i) => {
        const isRed = it.severity === 'red';
        const Icon = isRed ? OctagonAlert : AlertTriangle;
        const color = isRed ? COLOR_RED : COLOR_AMBER;
        const suffix = t(isRed ? 'badges.warning.avoid' : 'badges.warning.signaled');
        return (
          <Pressable key={it.key} onPress={() => onPress(it)} hitSlop={6} style={styles.lineItem}>
            <Icon size={13} color={color} strokeWidth={2.4} />
            <Text style={[styles.lineTraitText, { color }]}>
              {' '}{it.label} {suffix}
            </Text>
            {i < items.length - 1 && <View style={styles.lineSpacer} />}
          </Pressable>
        );
      })}
    </ScrollableLine>
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
}: {
  items: SportItem[];
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  onPress: (item: SportItem) => void;
}) {
  return (
    <ScrollableLine styles={styles} colors={colors}>
      {items.map((it) => (
        <Pressable
          key={it.sportKey}
          onPress={() => onPress(it)}
          hitSlop={4}
          style={styles.sportChip}
        >
          <Text style={styles.sportEmoji}>{getSportIcon(it.sportKey)}</Text>
          <Text style={styles.sportCount}>{it.count}</Text>
        </Pressable>
      ))}
    </ScrollableLine>
  );
}

// ---------------------------------------------------------------------------
// Generic horizontally-scrollable line wrapper. Tracks overflow so we can show
// a chevron affordance on the right edge while there's content past the
// visible area, matching the rest of the page.
// ---------------------------------------------------------------------------

function ScrollableLine({
  children,
  styles,
  colors,
  prefix,
}: {
  children: React.ReactNode;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  prefix?: React.ReactNode;
}) {
  const [viewWidth, setViewWidth] = useState(0);
  const [contentWidth, setContentWidth] = useState(0);
  const [scrollX, setScrollX] = useState(0);
  const hasMore = contentWidth - viewWidth - scrollX > 4;

  return (
    <View style={styles.scrollWrap}>
      {prefix && <View style={styles.prefixWrap}>{prefix}</View>}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
        onLayout={(e) => setViewWidth(e.nativeEvent.layout.width)}
        onContentSizeChange={(w) => setContentWidth(w)}
        onScroll={(e) => setScrollX(e.nativeEvent.contentOffset.x)}
        scrollEventThrottle={32}
      >
        {children}
      </ScrollView>
      {hasMore && (
        <View pointerEvents="none" style={[styles.fade, { backgroundColor: colors.surface + 'E6' }]} />
      )}
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
  } else {
    title = `${getSportIcon(target.item.sportKey)}  ${target.item.label}`;
    body = t('badges.sportFooter', {
      count: target.item.count,
      defaultValue: `${target.item.count} activités complétées`,
    });
  }

  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.modalBackdrop} onPress={onClose}>
        <Pressable style={styles.modalCard} onPress={(e) => e.stopPropagation()}>
          <Text style={styles.modalTitle}>{title}</Text>
          {body !== '' && <Text style={styles.modalBody}>{body}</Text>}
          {footer && <Text style={styles.modalFooter}>{footer}</Text>}
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
    divider: {
      borderBottomWidth: 1,
      borderBottomColor: colors.line,
      borderStyle: 'dashed',
      marginVertical: spacing.sm,
    },

    scrollWrap: {
      flexDirection: 'row',
      alignItems: 'center',
      position: 'relative',
    },
    prefixWrap: {
      paddingRight: 8,
    },
    linePrefix: {
      fontSize: 13,
      fontWeight: '700',
    },
    linePrefixVouched: {
      color: '#7EC8A3',
    },
    scrollContent: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingRight: 24,
    },
    fade: {
      position: 'absolute',
      right: 0,
      top: 0,
      bottom: 0,
      width: 22,
    },

    lineItem: {
      flexDirection: 'row',
      alignItems: 'center',
    },
    lineSpacer: {
      width: 14,
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

    sportChip: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 5,
      backgroundColor: colors.surfaceAlt,
      borderRadius: 999,
      paddingVertical: 4,
      paddingHorizontal: 10,
      marginRight: 6,
    },
    sportEmoji: {
      fontSize: 16,
      lineHeight: 18,
    },
    sportCount: {
      color: colors.textPrimary,
      fontSize: 12.5,
      fontWeight: '700',
      letterSpacing: -0.01,
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
