import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet, RefreshControl } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
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
import { levelSpanMatchesTiers } from '@/constants/sport-levels';
import { distanceMeters } from '@/utils/geo';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useAuth } from '@/hooks/use-auth';
import { getFriendlyError } from '@/utils/friendly-error';

// Hierarchy (Scott 2026-07-06): the PRIMARY axis is time/state — À venir ·
// Terminées · En attente (badged). Créées/Rejointes demoted to a secondary
// scope refinement, defaulting to "Toutes" (created + joined merged, date
// sorted) so the tab reads as your agenda at a glance.
type MainTab = 'upcoming' | 'finished' | 'pending';
type Scope = 'all' | 'created' | 'joined';

export default function MesActivitesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const insets = useSafeAreaInsets();
  const { center, currentLocation } = useInitialLocation();
  const { session } = useAuth();
  const filters = useMyActivitiesFilterStore((s) => s.filters);
  const [refreshing, setRefreshing] = useState(false);
  const [mainTab, setMainTab] = useState<MainTab>('upcoming');
  const [scope, setScope] = useState<Scope>('all');
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

  // Source list: pending is its own state; otherwise the scope picks
  // created / joined / both merged (they're disjoint lists).
  const activities = useMemo(() => {
    if (mainTab === 'pending') return pending;
    if (scope === 'created') return created;
    if (scope === 'joined') return joined;
    return [...(created ?? []), ...(joined ?? [])];
  }, [mainTab, scope, created, joined, pending]);
  const isLoading = mainTab === 'pending'
    ? loadingPending
    : scope === 'created' ? loadingCreated : scope === 'joined' ? loadingJoined : (loadingCreated || loadingJoined);
  const error = mainTab === 'pending'
    ? errorPending
    : scope === 'created' ? errorCreated : scope === 'joined' ? errorJoined : (errorCreated ?? errorJoined);

  const userLocation = currentLocation ?? center;

  const filtered = useMemo(() => {
    if (!activities) return [];
    const now = dayjs();

    const filteredList = activities.filter((a: NearbyActivity) => {
      // Time filter — only for created/joined. Pending entries are
      // active-only since mig 00263 (stale requests auto-expire on
      // activity end + the view filters by status); the chip row is
      // hidden for pending.
      if (mainTab !== 'pending') {
        const isUpcoming = dayjs(a.starts_at).isAfter(now) && !['completed', 'cancelled', 'expired'].includes(a.status);
        if (mainTab === 'upcoming' && !isUpcoming) return false;
        if (mainTab === 'finished' && isUpcoming) return false;
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

      if (!levelSpanMatchesTiers(a.sport_key, a.level, a.level_max, filters.levelTiers)) return false;

      if (filters.radiusKm !== null) {
        const limit = filters.radiusKm * 1000;
        if (distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) > limit) return false;
      }

      return true;
    });

    // Sort. sortBy === null means default (date asc). 3-state chip
    // cycle in the Trier par tab: asc → desc → null.
    const sorted = [...filteredList];
    const { sortBy, sortDir } = filters;
    const effectiveSort = sortBy ?? 'date';
    const dir = sortBy !== null && sortDir === 'desc' ? -1 : 1;
    if (effectiveSort === 'date') {
      sorted.sort((a, b) => (dayjs(a.starts_at).valueOf() - dayjs(b.starts_at).valueOf()) * dir);
    } else if (effectiveSort === 'distance') {
      sorted.sort((a, b) => (
        distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) -
        distanceMeters(userLocation[1], userLocation[0], b.lat, b.lng)
      ) * dir);
    } else if (effectiveSort === 'sport') {
      sorted.sort((a, b) => a.sport_key.localeCompare(b.sport_key) * dir);
    } else if (effectiveSort === 'remaining') {
      const remaining = (a: NearbyActivity) =>
        a.max_participants === null ? Infinity : a.max_participants - a.participant_count;
      sorted.sort((a, b) => (remaining(a) - remaining(b)) * dir);
    }

    return sorted;
  }, [activities, mainTab, filters, userLocation]);

  const hasMapFilters =
    filters.sportKeys.length > 0
    || filters.dateMode !== 'all'
    || filters.levelTiers.length > 0
    || filters.radiusKm !== null;

  const emptyMessage = () => {
    if (mainTab === 'pending') return t('myActivities.emptyPending');
    if (scope === 'created' && (!created || created.length === 0)) return t('myActivities.emptyCreated');
    if (scope === 'joined' && (!joined || joined.length === 0)) return t('myActivities.emptyJoined');
    if (hasMapFilters) return t('myActivities.noResults');
    return mainTab === 'upcoming' ? t('myActivities.emptyUpcoming') : t('myActivities.emptyFinished');
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
      {/* PRIMARY — time/state, big underlined tabs (the PP tab-bar language). */}
      <View style={styles.mainTabs}>
        {(['upcoming', 'finished', 'pending'] as const).map((tab) => (
          <Pressable
            key={tab}
            style={[styles.mainTab, mainTab === tab && styles.mainTabActive]}
            onPress={() => setMainTab(tab)}
          >
            <Text style={[styles.mainTabText, mainTab === tab && styles.mainTabTextActive]}>
              {tab === 'upcoming'
                ? t('myActivities.upcoming', { defaultValue: 'À venir' })
                : tab === 'finished'
                  ? t('myActivities.finished', { defaultValue: 'Terminées' })
                  : t('myActivities.pending', { defaultValue: 'En attente' })}
            </Text>
            {tab === 'pending' && pendingCount > 0 && (
              <View style={styles.pendingBadge}>
                <Text style={styles.pendingBadgeText}>{pendingCount}</Text>
              </View>
            )}
          </Pressable>
        ))}
      </View>

      {/* SECONDARY — scope chips (Toutes par défaut) + a VISIBLE Filtres chip.
          Pending has no scope: it's one list. */}
      <View style={styles.scopeRow}>
        {mainTab !== 'pending' ? (
          <View style={styles.scopeChips}>
            {(['all', 'created', 'joined'] as const).map((s) => (
              <Pressable
                key={s}
                style={[styles.scopeChip, scope === s && styles.scopeChipActive]}
                onPress={() => setScope(s)}
              >
                <Text style={[styles.scopeChipText, scope === s && styles.scopeChipTextActive]}>
                  {s === 'all'
                    ? t('myActivities.all', { defaultValue: 'Toutes' })
                    : s === 'created'
                      ? t('myActivities.created', { defaultValue: 'Créées' })
                      : t('myActivities.joined', { defaultValue: 'Rejointes' })}
                </Text>
              </Pressable>
            ))}
          </View>
        ) : (
          <View style={styles.scopeChips} />
        )}
        <Pressable style={styles.filterChip} onPress={() => setShowFilters(true)}>
          <SlidersHorizontal size={15} color={hasMapFilters ? colors.cta : colors.textPrimary} strokeWidth={2.2} />
          <Text style={[styles.filterChipText, hasMapFilters && { color: colors.cta }]}>
            {t('myActivities.filters', { defaultValue: 'Filtres' })}
          </Text>
          {hasMapFilters && <View style={styles.filterDot} />}
        </Pressable>
      </View>

      <FilterSheet
        visible={showFilters}
        onClose={() => setShowFilters(false)}
        hideAlertsTab
        showSortTab
        useStore={useMyActivitiesFilterStore}
        showEntityFilter={false}
      />

      {isLoading ? (
        <View style={styles.center}>
          <LogoSpinner size={48} />
        </View>
      ) : error ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>{getFriendlyError(error, 'generic')}</Text>
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
              currentUserId={session?.user?.id ?? null}
              onPress={() => router.push(`/(auth)/activity/${item.id}`)}
            />
          )}
          contentContainerStyle={[styles.list, { paddingBottom: insets.bottom + spacing.md }]}
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

  // PRIMARY — À venir / Terminées / En attente. Big, bold, cta underline:
  // the same tab language as the PP drawer.
  mainTabs: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  mainTab: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderBottomWidth: 3,
    borderBottomColor: 'transparent',
  },
  mainTabActive: {
    borderBottomColor: colors.cta,
  },
  mainTabText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '600',
  },
  mainTabTextActive: {
    color: colors.cta,
    fontWeight: '800',
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

  // SECONDARY — scope chips + the visible Filtres chip, one row.
  scopeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.xs,
    gap: spacing.sm,
  },
  scopeChips: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 2, flex: 1 },
  scopeChip: {
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 1,
  },
  scopeChipActive: {
    borderColor: colors.cta,
    backgroundColor: colors.cta + '18',
  },
  scopeChipText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  scopeChipTextActive: { color: colors.cta, fontWeight: '800' },
  filterChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 1,
    backgroundColor: colors.surface,
  },
  filterChipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  filterDot: {
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
