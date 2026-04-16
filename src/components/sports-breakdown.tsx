import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { getSportIcon } from '@/constants/sport-icons';
import type { SportBreakdownRow } from '@/services/user-service';

interface Props {
  rows: SportBreakdownRow[];
}

export function SportsBreakdown({ rows }: Props) {
  const { t } = useTranslation();

  if (rows.length === 0) {
    return (
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('profil.sportsSection')}</Text>
        <Text style={styles.emptyText}>{t('profil.noSportsYet')}</Text>
      </View>
    );
  }

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{t('profil.sportsSection')}</Text>
      <View style={styles.list}>
        {rows.map((row) => (
          <View key={row.sport_key} style={styles.row}>
            <Text style={styles.icon}>{getSportIcon(row.sport_key)}</Text>
            <View style={styles.info}>
              <Text style={styles.sportName}>
                {t(`sports.${row.sport_key}`, row.sport_key)}
              </Text>
              {row.level ? (
                <Text style={styles.level}>{row.level}</Text>
              ) : null}
            </View>
            <Text style={styles.count}>
              {t('profil.sportOutings', { count: row.completed_count })}
            </Text>
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  section: { marginBottom: spacing.lg },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
  },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },
  list: { gap: spacing.xs },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    gap: spacing.sm,
  },
  icon: { fontSize: 22 },
  info: { flex: 1 },
  sportName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    textTransform: 'capitalize',
  },
  level: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    textTransform: 'capitalize',
    marginTop: 2,
  },
  count: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
});
