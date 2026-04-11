import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';
import { supabase } from '@/services/supabase';

const DATE_OPTIONS = ['all', 'today', 'week'] as const;

export function FilterBar() {
  const { t } = useTranslation();
  const { filters, setSportFilter, setDateFilter } = useMapStore();

  const { data: sports } = useQuery({
    queryKey: ['sports'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sports')
        .select('id, key, display_order')
        .order('display_order');
      if (error) throw error;
      return data;
    },
  });

  return (
    <View style={styles.container}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.scroll}>
        {/* Date filters */}
        {DATE_OPTIONS.map((option) => (
          <Pressable
            key={option}
            style={[styles.chip, filters.dateRange === option && styles.chipActive]}
            onPress={() => setDateFilter(option)}
          >
            <Text style={[styles.chipText, filters.dateRange === option && styles.chipTextActive]}>
              {t(`map.date.${option}`)}
            </Text>
          </Pressable>
        ))}

        <View style={styles.separator} />

        {/* Sport filters */}
        {(sports ?? []).map((sport) => (
          <Pressable
            key={sport.id}
            style={[styles.chip, filters.sportKey === sport.key && styles.chipActive]}
            onPress={() => setSportFilter(filters.sportKey === sport.key ? null : sport.key)}
          >
            <Text
              style={[styles.chipText, filters.sportKey === sport.key && styles.chipTextActive]}
            >
              {t(`sports.${sport.key}`, sport.key)}
            </Text>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 96,
    left: 0,
    right: 0,
    zIndex: 10,
  },
  scroll: {
    paddingHorizontal: spacing.md,
  },
  chip: {
    backgroundColor: colors.background + 'CC',
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    marginRight: spacing.sm,
  },
  chipActive: {
    backgroundColor: colors.cta,
  },
  chipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  chipTextActive: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
  separator: {
    width: 1,
    backgroundColor: colors.textSecondary,
    marginHorizontal: spacing.sm,
    opacity: 0.3,
  },
});
