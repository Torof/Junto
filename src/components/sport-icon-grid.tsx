import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Pencil, Check, AlertTriangle } from 'lucide-react-native';
import { fontSizes, spacing } from '@/constants/theme';
import { getSportIcon } from '@/constants/sport-icons';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import type { SportBreakdownRow } from '@/services/user-service';
import type { SportEndorsement } from '@/services/endorsement-service';
import { LevelGauge, levelStringToDots } from '@/components/level-gauge';

interface Props {
  rows: SportBreakdownRow[];
  onEdit?: () => void;
  endorsements?: SportEndorsement[];
}

function sortByCount(rows: SportBreakdownRow[]): SportBreakdownRow[] {
  return [...rows].sort((a, b) => b.completed_count - a.completed_count);
}

export function SportIconGrid({ rows, onEdit, endorsements = [] }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [showAll, setShowAll] = useState(false);

  const endorsementMap = useMemo(() => {
    const m: Record<string, number> = {};
    endorsements.forEach((e) => { m[e.sport_key] = e.net_count; });
    return m;
  }, [endorsements]);

  if (rows.length === 0 && !onEdit) return null;

  const practiced = sortByCount(rows.filter((r) => r.completed_count > 0));
  const declared = sortByCount(rows.filter((r) => r.completed_count === 0));
  const visible = showAll ? [...practiced, ...declared] : practiced;

  return (
    <View style={styles.card}>
      <View style={styles.headerRow}>
        <Text style={styles.title}>
          {t('profil.sportsSection').toUpperCase()} · {rows.length}
        </Text>
        {onEdit && (
          <Pressable onPress={onEdit} hitSlop={12}>
            <Pencil size={14} color={colors.textMuted} strokeWidth={2} />
          </Pressable>
        )}
      </View>


      {rows.length === 0 ? (
        <Pressable onPress={onEdit} style={styles.emptyWrap}>
          <Text style={styles.emptyText}>{t('profil.noSportsYet')}</Text>
        </Pressable>
      ) : (
        <>
          {visible.length === 0 ? (
            <Pressable onPress={() => setShowAll(true)} style={styles.emptyWrap}>
              <Text style={styles.emptyText}>{t('profil.noPracticedYet')}</Text>
            </Pressable>
          ) : (
            visible.map((row, idx) => (
              <SportRow
                key={row.sport_key}
                row={row}
                endorsementNet={endorsementMap[row.sport_key] ?? 0}
                isLast={idx === visible.length - 1}
                styles={styles}
                colors={colors}
                t={t}
              />
            ))
          )}

          {declared.length > 0 && (
            <Pressable onPress={() => setShowAll((v) => !v)} style={styles.moreRow}>
              <Text style={styles.moreText}>
                {showAll
                  ? t('profil.showLess')
                  : t('profil.seeOtherSports', { count: declared.length, defaultValue: `Voir les ${declared.length} autres →` })}
              </Text>
            </Pressable>
          )}
        </>
      )}
    </View>
  );
}

function SportRow({
  row, endorsementNet, isLast, styles, colors, t,
}: {
  row: SportBreakdownRow;
  endorsementNet: number;
  isLast: boolean;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  t: (k: string, opts?: Record<string, unknown>) => string;
}) {
  const dimmed = row.completed_count === 0;
  const showEndorsement = endorsementNet !== 0;
  const positiveEndorsement = endorsementNet > 0;
  const endorsementMagnitude = Math.abs(endorsementNet);
  return (
    <View style={[styles.sportRow, !isLast && styles.sportRowBorder]}>
      <LevelGauge dots={levelStringToDots(row.level)} />
      <Text style={styles.emoji}>{getSportIcon(row.sport_key)}</Text>
      <Text style={styles.sportName} numberOfLines={1}>
        {t(`sports.${row.sport_key}`, { defaultValue: row.sport_key })}
      </Text>
      {showEndorsement && (
        <View style={[
          styles.endorsePill,
          positiveEndorsement ? styles.endorsePillPos : styles.endorsePillNeg,
        ]}>
          {positiveEndorsement
            ? <Check size={10} color="#7EC8A3" strokeWidth={3} />
            : <AlertTriangle size={10} color="#E5524E" strokeWidth={2.4} />}
          <Text style={[
            styles.endorseText,
            { color: positiveEndorsement ? '#7EC8A3' : '#E5524E' },
          ]}>×{endorsementMagnitude}</Text>
        </View>
      )}
      <View style={[styles.countPill, dimmed && styles.countPillDimmed]}>
        <Text style={[styles.countNumber, dimmed && { color: colors.textMuted }]}>
          {row.completed_count}
        </Text>
        <Text style={[styles.countUnit, dimmed && { color: colors.textMuted }]}>
          {t('profil.activitiesCount', { count: row.completed_count })}
        </Text>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: 18,
    borderWidth: 1, borderColor: colors.line,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: 4,
    marginBottom: spacing.md,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    paddingHorizontal: 10,
    marginBottom: 4,
  },
  title: {
    color: colors.textPrimary,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },

  emptyWrap: {
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontStyle: 'italic',
    textAlign: 'center',
  },

  sportRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 9,
    paddingHorizontal: 10,
  },
  sportRowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
    borderStyle: 'dashed',
  },

  emoji: {
    fontSize: 20,
    lineHeight: 22,
    width: 24,
    textAlign: 'center',
  },
  sportName: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: 13.5,
    fontWeight: '700',
    letterSpacing: -0.01,
    textTransform: 'capitalize',
  },
  endorsePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 6,
    paddingVertical: 2,
  },
  endorsePillPos: {
    backgroundColor: '#7EC8A3' + '18',
    borderColor: '#7EC8A3' + '4D',
  },
  endorsePillNeg: {
    backgroundColor: '#E5524E' + '18',
    borderColor: '#E5524E' + '4D',
  },
  endorseText: {
    fontSize: 10.5,
    fontWeight: '800',
    letterSpacing: -0.02,
  },

  countPill: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 4,
    backgroundColor: colors.cta + '1A',
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  countPillDimmed: {
    backgroundColor: colors.textMuted + '1A',
    opacity: 0.6,
  },
  countNumber: {
    color: colors.cta,
    fontSize: 13,
    fontWeight: '800',
    letterSpacing: -0.02,
  },
  countUnit: {
    color: colors.cta,
    fontSize: 10.5,
    fontWeight: '600',
  },

  legend: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 10,
    paddingVertical: spacing.xs,
    marginBottom: spacing.xs,
  },
  legendGauges: {
    flexDirection: 'row',
    gap: 6,
  },
  legendText: {
    color: colors.textMuted,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },

  moreRow: {
    paddingVertical: 10,
    alignItems: 'center',
  },
  moreText: {
    color: colors.textSecondary,
    fontSize: 10.5,
    fontWeight: '600',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
});
