import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Pencil } from 'lucide-react-native';
import { colors, fontSizes, spacing } from '@/constants/theme';
import { getSportIcon } from '@/constants/sport-icons';
import type { SportBreakdownRow } from '@/services/user-service';

interface Props {
  rows: SportBreakdownRow[];
  onEdit?: () => void;
}

const LEVEL_COLORS: Record<string, string> = {
  'débutant': colors.success,
  'intermédiaire': '#3b82f6',
  'avancé': colors.warning,
  'expert': colors.error,
};

const LEVEL_PRIORITY: Record<string, number> = {
  'expert': 4,
  'avancé': 3,
  'intermédiaire': 2,
  'débutant': 1,
};

function sortByLevelThenCount(rows: SportBreakdownRow[]): SportBreakdownRow[] {
  return [...rows].sort((a, b) => {
    const levelA = LEVEL_PRIORITY[a.level ?? ''] ?? 0;
    const levelB = LEVEL_PRIORITY[b.level ?? ''] ?? 0;
    if (levelB !== levelA) return levelB - levelA;
    return b.completed_count - a.completed_count;
  });
}

const ICON_SIZE = 44;

export function SportIconGrid({ rows, onEdit }: Props) {
  const { t } = useTranslation();

  if (rows.length === 0 && !onEdit) return null;

  return (
    <View style={styles.section}>
      <View style={styles.headerRow}>
        <Text style={styles.sectionTitle}>{t('profil.sportsSection')}</Text>
        {onEdit && (
          <Pressable onPress={onEdit} hitSlop={12}>
            <Pencil size={16} color={colors.textSecondary} strokeWidth={2} />
          </Pressable>
        )}
      </View>
      {rows.length === 0 ? (
        <Pressable onPress={onEdit}>
          <Text style={styles.emptyText}>{t('profil.noSportsYet')}</Text>
        </Pressable>
      ) : (
        <View style={styles.grid}>
          {sortByLevelThenCount(rows).map((row) => {
            const borderColor = LEVEL_COLORS[row.level ?? ''] ?? colors.surface;
            return (
              <View key={row.sport_key} style={styles.iconWrap}>
                <View style={[styles.iconCircle, { borderColor }]}>
                  <Text style={styles.icon}>{getSportIcon(row.sport_key)}</Text>
                  {row.completed_count > 0 && (
                    <View style={styles.countBadge}>
                      <Text style={styles.countText}>{row.completed_count}</Text>
                    </View>
                  )}
                </View>
              </View>
            );
          })}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { marginBottom: spacing.lg },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  iconWrap: {
    alignItems: 'center',
  },
  iconCircle: {
    width: ICON_SIZE,
    height: ICON_SIZE,
    borderRadius: ICON_SIZE / 2,
    borderWidth: 3,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 20,
  },
  countBadge: {
    position: 'absolute',
    top: -4,
    right: -4,
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
    borderWidth: 2,
    borderColor: colors.background,
  },
  countText: {
    color: colors.textPrimary,
    fontSize: 10,
    fontWeight: 'bold',
  },
});
