import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from '@/components/activity-card';
import { supabase } from '@/services/supabase';

type MainTab = 'created' | 'joined';
type TimeFilter = 'upcoming' | 'finished';
type DateRange = 'all' | 'today' | 'week';

export default function MesActivitesScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const [mainTab, setMainTab] = useState<MainTab>('created');
  const [timeFilter, setTimeFilter] = useState<TimeFilter>('upcoming');
  const [sportFilter, setSportFilter] = useState<string | null>(null);
  const [dateRange, setDateRange] = useState<DateRange>('all');

  const { data: created, isLoading: loadingCreated, error: errorCreated } = useQuery({
    queryKey: ['activities', 'my-created'],
    queryFn: () => activityService.getMyCreated(),
  });

  const { data: joined, isLoading: loadingJoined, error: errorJoined } = useQuery({
    queryKey: ['activities', 'my-joined'],
    queryFn: () => activityService.getMyJoined(),
  });

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

  const activities = mainTab === 'created' ? created : joined;
  const isLoading = mainTab === 'created' ? loadingCreated : loadingJoined;
  const error = mainTab === 'created' ? errorCreated : errorJoined;

  const filtered = useMemo(() => {
    if (!activities) return [];
    const now = dayjs();

    return activities.filter((a: NearbyActivity) => {
      // Time filter
      const isUpcoming = dayjs(a.starts_at).isAfter(now) && !['completed', 'cancelled', 'expired'].includes(a.status);
      if (timeFilter === 'upcoming' && !isUpcoming) return false;
      if (timeFilter === 'finished' && isUpcoming) return false;

      // Sport filter
      if (sportFilter && a.sport_key !== sportFilter) return false;

      // Date range filter
      if (dateRange === 'today' && !dayjs(a.starts_at).isSame(now, 'day')) return false;
      if (dateRange === 'week' && dayjs(a.starts_at).isAfter(now.add(7, 'day'))) return false;

      return true;
    });
  }, [activities, timeFilter, sportFilter, dateRange]);

  const emptyMessage = () => {
    if (mainTab === 'created' && (!created || created.length === 0)) return t('myActivities.emptyCreated');
    if (mainTab === 'joined' && (!joined || joined.length === 0)) return t('myActivities.emptyJoined');
    if (sportFilter || dateRange !== 'all') return t('myActivities.noResults');
    return timeFilter === 'upcoming' ? t('myActivities.emptyUpcoming') : t('myActivities.emptyFinished');
  };

  const hasActiveFilters = sportFilter !== null || dateRange !== 'all';

  const resetFilters = () => {
    setSportFilter(null);
    setDateRange('all');
  };

  return (
    <View style={styles.container}>
      <View style={styles.mainTabs}>
        <Pressable
          style={[styles.mainTab, mainTab === 'created' && styles.mainTabActive]}
          onPress={() => setMainTab('created')}
        >
          <Text style={[styles.mainTabText, mainTab === 'created' && styles.mainTabTextActive]}>
            {t('myActivities.created')}
          </Text>
        </Pressable>
        <Pressable
          style={[styles.mainTab, mainTab === 'joined' && styles.mainTabActive]}
          onPress={() => setMainTab('joined')}
        >
          <Text style={[styles.mainTabText, mainTab === 'joined' && styles.mainTabTextActive]}>
            {t('myActivities.joined')}
          </Text>
        </Pressable>
      </View>

      <View style={styles.timeTabs}>
        <Pressable
          style={[styles.timeTab, timeFilter === 'upcoming' && styles.timeTabActive]}
          onPress={() => setTimeFilter('upcoming')}
        >
          <Text style={[styles.timeTabText, timeFilter === 'upcoming' && styles.timeTabTextActive]}>
            {t('myActivities.upcoming')}
          </Text>
        </Pressable>
        <Pressable
          style={[styles.timeTab, timeFilter === 'finished' && styles.timeTabActive]}
          onPress={() => setTimeFilter('finished')}
        >
          <Text style={[styles.timeTabText, timeFilter === 'finished' && styles.timeTabTextActive]}>
            {t('myActivities.finished')}
          </Text>
        </Pressable>
      </View>

      <View style={styles.filterSection}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
          {(['all', 'today', 'week'] as const).map((option) => (
            <Pressable
              key={option}
              style={[styles.chip, dateRange === option && styles.chipActive]}
              onPress={() => setDateRange(option)}
            >
              <Text style={[styles.chipText, dateRange === option && styles.chipTextActive]}>
                {t(`map.date.${option}`)}
              </Text>
            </Pressable>
          ))}
          <View style={styles.divider} />
          {(sports ?? []).map((sport) => (
            <Pressable
              key={sport.id}
              style={[styles.chip, sportFilter === sport.key && styles.chipActive]}
              onPress={() => setSportFilter(sportFilter === sport.key ? null : sport.key)}
            >
              <Text style={[styles.chipText, sportFilter === sport.key && styles.chipTextActive]}>
                {t(`sports.${sport.key}`, sport.key)}
              </Text>
            </Pressable>
          ))}
        </ScrollView>
        {hasActiveFilters && (
          <Pressable onPress={resetFilters} style={styles.resetButton}>
            <Text style={styles.resetText}>{t('map.resetFilters')}</Text>
          </Pressable>
        )}
      </View>

      {isLoading ? (
        <View style={styles.center}>
          <Text style={styles.loadingText}>...</Text>
        </View>
      ) : filtered.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>{emptyMessage()}</Text>
        </View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <ActivityCard
              activity={item}
              onPress={() => router.push(`/(auth)/activity/${item.id}`)}
            />
          )}
          contentContainerStyle={styles.list}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  mainTabs: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    gap: spacing.sm,
  },
  mainTab: {
    flex: 1,
    paddingVertical: spacing.sm,
    alignItems: 'center',
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  mainTabActive: {
    backgroundColor: colors.cta,
  },
  mainTabText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
  mainTabTextActive: {
    color: colors.textPrimary,
  },
  timeTabs: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    gap: spacing.sm,
  },
  timeTab: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.md,
    borderRadius: radius.full,
    backgroundColor: 'transparent',
  },
  timeTabActive: {
    backgroundColor: colors.surface,
  },
  timeTabText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  timeTabTextActive: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
  filterSection: {
    paddingTop: spacing.sm,
    paddingBottom: spacing.xs,
  },
  filterRow: {
    paddingHorizontal: spacing.md,
    gap: spacing.xs,
    alignItems: 'center',
  },
  chip: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
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
  divider: {
    width: 1,
    height: 16,
    backgroundColor: colors.textSecondary,
    opacity: 0.3,
    marginHorizontal: spacing.xs,
  },
  resetButton: {
    paddingHorizontal: spacing.md,
    paddingTop: spacing.xs,
    alignSelf: 'flex-end',
  },
  resetText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
  },
  list: {
    padding: spacing.md,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: fontSizes.lg,
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
