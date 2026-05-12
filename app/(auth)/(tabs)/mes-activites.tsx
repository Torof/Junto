import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet, RefreshControl } from 'react-native';
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
import { FilterSheet } from '@/components/filter-sheet';
import { useMyActivitiesFilterStore } from '@/store/my-activities-filter-store';
import { getLevelScale } from '@/constants/sport-levels';
import { distanceMeters } from '@/utils/geo';
import { useInitialLocation } from '@/hooks/use-initial-location';

type MainTab = 'created' | 'joined' | 'pending';
type TimeFilter = 'upcoming' | 'finished';

const OPEN_LEVEL = 'Tous niveaux';

export default function MesActivitesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { center, currentLocation } = useInitialLocation();
  const filters = useMyActivitiesFilterStore((s) => s.filters);
  const [refreshing, setRefreshing] = useState(false);
  const [mainTab, setMainTab] = useState<MainTab>('created');
  const [timeFilter, setTimeFilter] = useState<TimeFilter>('upcoming');
  const [showFilters, setShowFilters] = useState(false);

  const { data: created, isLoading: loadingCreated, error: errorCreated } = useQuery({
    queryKey: ['activities', 'my-created'],
    queryFn: () => activityService.getMyCreated(),
  });

  const { data: joined, isLoading: loadingJoined, error: errorJoined } = useQuery({
    queryKey: ['activities', 'my-joined'],
    queryFn: () => activityService.getMyJoined(),
  });

  const { data: pending, isLoading: loadingPending, error: errorPending } = useQuery({
    queryKey: ['activities', 'my-pending'],
    queryFn: () => activityService.getMyPending(),
  });

  const activities = mainTab === 'created' ? created : mainTab === 'joined' ? joined : pending;
  const isLoading = mainTab === 'created' ? loadingCreated : mainTab === 'joined' ? loadingJoined : loadingPending;
  const error = mainTab === 'created' ? errorCreated : mainTab === 'joined' ? errorJoined : errorPending;

  const userLocation = currentLocation ?? center;

  const filtered = useMemo(() => {
    if (!activities) return [];
    const now = dayjs();

    const filteredList = activities.filter((a: NearbyActivity) => {
      // Time filter — only for created/joined (pending requests can only
      // be in-the-future by definition; the chip row is hidden for pending).
      if (mainTab !== 'pending') {
        const isUpcoming = dayjs(a.starts_at).isAfter(now) && !['completed', 'cancelled', 'expired'].includes(a.status);
        if (timeFilter === 'upcoming' && !isUpcoming) return false;
        if (timeFilter === 'finished' && isUpcoming) return false;
      }

      // Shared filters from useMyActivitiesFilterStore (sport / date / level / radius).
      if (filters.sportKeys.length > 0 && !filters.sportKeys.includes(a.sport_key)) return false;

      if (filters.dateMode === 'today' && !dayjs(a.starts_at).isSame(now, 'day')) return false;
      if (filters.dateMode === 'week' && dayjs(a.starts_at).isAfter(now.add(7, 'day'))) return false;
      if (filters.dateMode === 'date' && filters.specificDate && !dayjs(a.starts_at).isSame(dayjs(filters.specificDate), 'day')) return false;
      if (filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo) {
        const from = dayjs(filters.rangeFrom).startOf('day');
        const to = dayjs(filters.rangeTo).endOf('day');
        const d = dayjs(a.starts_at);
        if (!(d.isAfter(from) && d.isBefore(to))) return false;
      }

      if (filters.levelTiers.length > 0) {
        if (a.level && a.level !== OPEN_LEVEL) {
          const scale = getLevelScale(a.sport_key);
          const option = scale.find((o) => o.label === a.level);
          if (option?.description && !filters.levelTiers.includes(option.description as typeof filters.levelTiers[number])) {
            return false;
          }
        }
      }

      if (filters.radiusKm !== null) {
        const limit = filters.radiusKm * 1000;
        if (distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) > limit) return false;
      }

      return true;
    });

    // Sort. Default 'date' ascending for upcoming/pending, descending for
    // finished (most recent first when looking back). Other sort options
    // ignore timeFilter direction — they sort by their own metric.
    const sorted = [...filteredList];
    const sortBy = filters.sortBy;
    if (sortBy === 'date') {
      const dirDesc = mainTab !== 'pending' && timeFilter === 'finished';
      sorted.sort((a, b) => {
        const diff = dayjs(a.starts_at).valueOf() - dayjs(b.starts_at).valueOf();
        return dirDesc ? -diff : diff;
      });
    } else if (sortBy === 'distance') {
      sorted.sort((a, b) =>
        distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) -
        distanceMeters(userLocation[1], userLocation[0], b.lat, b.lng),
      );
    } else if (sortBy === 'sport') {
      sorted.sort((a, b) => a.sport_key.localeCompare(b.sport_key));
    } else if (sortBy === 'remaining') {
      const remaining = (a: NearbyActivity) =>
        a.max_participants === null ? Infinity : a.max_participants - a.participant_count;
      sorted.sort((a, b) => remaining(b) - remaining(a));
    }

    return sorted;
  }, [activities, mainTab, timeFilter, filters, userLocation]);

  const hasMapFilters =
    filters.sportKeys.length > 0
    || filters.dateMode !== 'all'
    || filters.levelTiers.length > 0
    || filters.radiusKm !== null;

  const emptyMessage = () => {
    if (mainTab === 'created' && (!created || created.length === 0)) return t('myActivities.emptyCreated');
    if (mainTab === 'joined' && (!joined || joined.length === 0)) return t('myActivities.emptyJoined');
    if (mainTab === 'pending' && (!pending || pending.length === 0)) return t('myActivities.emptyPending');
    if (hasMapFilters) return t('myActivities.noResults');
    if (mainTab === 'pending') return t('myActivities.emptyPending');
    return timeFilter === 'upcoming' ? t('myActivities.emptyUpcoming') : t('myActivities.emptyFinished');
  };

  const pendingCount = pending?.length ?? 0;

  const handleRefresh = async () => {
    setRefreshing(true);
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-created'] });
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-joined'] });
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-pending'] });
    setRefreshing(false);
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
        <Pressable
          style={[styles.mainTab, mainTab === 'pending' && styles.mainTabActive]}
          onPress={() => setMainTab('pending')}
        >
          <Text style={[styles.mainTabText, mainTab === 'pending' && styles.mainTabTextActive]}>
            {t('myActivities.pending')}
          </Text>
          {pendingCount > 0 && (
            <View style={styles.pendingBadge}>
              <Text style={styles.pendingBadgeText}>{pendingCount}</Text>
            </View>
          )}
        </Pressable>
        <View style={styles.tabSpacer} />
        <Pressable style={styles.filterToggle} onPress={() => setShowFilters(true)}>
          <View style={styles.filterIconWrap}>
            <SlidersHorizontal size={18} color={hasMapFilters ? colors.cta : colors.textSecondary} strokeWidth={2} />
            {hasMapFilters && <View style={styles.filterDot} />}
          </View>
        </Pressable>
      </View>

      {/* Time refinement — only meaningful for created/joined; pending
          requests are upcoming by definition. */}
      {mainTab !== 'pending' && (
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
      )}

      <FilterSheet
        visible={showFilters}
        onClose={() => setShowFilters(false)}
        hideAlertsTab
        useStore={useMyActivitiesFilterStore}
      />

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

  // Primary scope (Créées / Rejointes / En attente) — underline tab
  // pattern with the filter icon docked right.
  mainTabs: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  mainTab: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  mainTabActive: {
    borderBottomColor: colors.borderStrong,
  },
  mainTabText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    fontWeight: '500',
  },
  mainTabTextActive: {
    color: colors.textPrimary,
    fontWeight: '700',
  },
  pendingBadge: {
    minWidth: 16,
    height: 16,
    borderRadius: radius.sm,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
    marginLeft: 4,
  },
  pendingBadgeText: { color: '#FFFFFF', fontSize: 10, fontWeight: '700' },
  tabSpacer: {
    flex: 1,
  },

  // Secondary time refinement (À venir / Passées) — only rendered for
  // created/joined tabs.
  timeTabs: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.xs,
    gap: spacing.xs + 2,
  },
  timeTab: {
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    backgroundColor: 'transparent',
  },
  timeTabActive: {
    backgroundColor: colors.cta,
    borderColor: colors.cta,
  },
  timeTabText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  timeTabTextActive: {
    color: '#FFFFFF',
    fontWeight: '700',
  },
  filterToggle: {
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
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
    borderRadius: radius.xs,
    backgroundColor: colors.cta,
  },

  // List + states
  list: {
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.md,
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
