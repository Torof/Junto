import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet, Modal, RefreshControl } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import { SlidersHorizontal } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from '@/components/activity-card';
import { LogoSpinner } from '@/components/logo-spinner';
import { SportDropdown } from '@/components/sport-dropdown';

type MainTab = 'created' | 'joined';
type TimeFilter = 'upcoming' | 'finished';
type DateRange = 'all' | 'today' | 'week';

export default function MesActivitesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [refreshing, setRefreshing] = useState(false);
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

  const handleRefresh = async () => {
    setRefreshing(true);
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-created'] });
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-joined'] });
    setRefreshing(false);
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
          <View style={styles.filterIconWrap}>
            <SlidersHorizontal size={18} color={hasActiveFilters ? colors.cta : colors.textSecondary} strokeWidth={2} />
            {hasActiveFilters && <View style={styles.filterDot} />}
          </View>
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
            <SportDropdown
              selected={sportFilters}
              onSelect={(key) => setSportFilters((prev) =>
                prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]
              )}
              multiSelect
              label={t('map.sportLabel')}
            />

            <Pressable style={styles.applyButton} onPress={() => setShowFilters(false)}>
              <Text style={styles.applyText}>{t('map.apply')}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

      {isLoading ? (
        <View style={styles.center}>
          <LogoSpinner size={48} />
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
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor={colors.cta}
              colors={[colors.cta]}
            />
          }
        />
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
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
  filterIconWrap: {
    width: 20,
    height: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  filterDot: {
    position: 'absolute',
    top: -2,
    right: -4,
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: colors.cta,
  },
  backdrop: {
    flex: 1,
    backgroundColor: colors.overlay,
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
