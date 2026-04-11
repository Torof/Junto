import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, ScrollView, StyleSheet, Modal } from 'react-native';
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
  const [sportFilters, setSportFilters] = useState<string[]>([]);
  const [dateRange, setDateRange] = useState<DateRange>('all');
  const [showFilters, setShowFilters] = useState(false);

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
      if (sportFilters.length > 0 && !sportFilters.includes(a.sport_key)) return false;

      // Date range filter
      if (dateRange === 'today' && !dayjs(a.starts_at).isSame(now, 'day')) return false;
      if (dateRange === 'week' && dayjs(a.starts_at).isAfter(now.add(7, 'day'))) return false;

      return true;
    });
  }, [activities, timeFilter, sportFilters, dateRange]);

  const emptyMessage = () => {
    if (mainTab === 'created' && (!created || created.length === 0)) return t('myActivities.emptyCreated');
    if (mainTab === 'joined' && (!joined || joined.length === 0)) return t('myActivities.emptyJoined');
    if (sportFilters.length > 0 || dateRange !== 'all') return t('myActivities.noResults');
    return timeFilter === 'upcoming' ? t('myActivities.emptyUpcoming') : t('myActivities.emptyFinished');
  };

  const hasActiveFilters = sportFilters.length > 0 || dateRange !== 'all';

  const resetFilters = () => {
    setSportFilters([]);
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
        <View style={styles.timeTabSpacer} />
        <Pressable
          style={[styles.filterToggle, hasActiveFilters && styles.filterToggleActive]}
          onPress={() => setShowFilters(true)}
        >
          <Text style={styles.filterIcon}>{hasActiveFilters ? '⚙ ●' : '⚙'}</Text>
        </Pressable>
      </View>

      <Modal visible={showFilters} animationType="slide" transparent>
        <Pressable style={styles.backdrop} onPress={() => setShowFilters(false)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.handle} />

            <View style={styles.sheetHeader}>
              <Text style={styles.sheetTitle}>{t('myActivities.filters')}</Text>
              {hasActiveFilters && (
                <Pressable onPress={resetFilters}>
                  <Text style={styles.resetText}>{t('map.resetFilters')}</Text>
                </Pressable>
              )}
            </View>

            <Text style={styles.filterLabel}>{t('map.dateLabel')}</Text>
            <View style={styles.chipRow}>
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
            </View>

            <Text style={styles.filterLabel}>{t('map.sportLabel')}</Text>
            <ScrollView style={styles.sportList} showsVerticalScrollIndicator={false}>
              <View style={styles.chipRow}>
                {(sports ?? []).map((sport) => (
                  <Pressable
                    key={sport.id}
                    style={[styles.chip, sportFilters.includes(sport.key) && styles.chipActive]}
                    onPress={() => setSportFilters((prev) =>
                      prev.includes(sport.key) ? prev.filter((k) => k !== sport.key) : [...prev, sport.key]
                    )}
                  >
                    <Text style={[styles.chipText, sportFilters.includes(sport.key) && styles.chipTextActive]}>
                      {t(`sports.${sport.key}`, sport.key)}
                    </Text>
                  </Pressable>
                ))}
              </View>
            </ScrollView>

            <Pressable style={styles.applyButton} onPress={() => setShowFilters(false)}>
              <Text style={styles.applyText}>{t('map.apply')}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

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
  timeTabSpacer: {
    flex: 1,
  },
  filterToggle: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  filterToggleActive: {
    backgroundColor: colors.cta + '30',
  },
  filterIcon: {
    fontSize: 16,
    color: colors.textSecondary,
  },
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.lg,
    paddingBottom: spacing.xl + 16,
    maxHeight: '70%',
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
    alignSelf: 'center',
    marginBottom: spacing.lg,
    opacity: 0.4,
  },
  sheetHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  sheetTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
  },
  filterLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    marginTop: spacing.sm,
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  chip: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  chipActive: {
    backgroundColor: colors.cta,
  },
  chipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  chipTextActive: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
  sportList: {
    maxHeight: 200,
  },
  resetText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
  },
  applyButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginTop: spacing.lg,
  },
  applyText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
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
