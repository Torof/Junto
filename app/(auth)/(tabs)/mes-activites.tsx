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

type MainTab = 'created' | 'joined' | 'pending';
type DateRange = 'all' | 'today' | 'week';

export default function MesActivitesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [refreshing, setRefreshing] = useState(false);
  const [mainTab, setMainTab] = useState<MainTab>('created');
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

  const { data: pending, isLoading: loadingPending, error: errorPending } = useQuery({
    queryKey: ['activities', 'my-pending'],
    queryFn: () => activityService.getMyPending(),
  });

  const activities = mainTab === 'created' ? created : mainTab === 'joined' ? joined : pending;
  const isLoading = mainTab === 'created' ? loadingCreated : mainTab === 'joined' ? loadingJoined : loadingPending;
  const error = mainTab === 'created' ? errorCreated : mainTab === 'joined' ? errorJoined : errorPending;

  const filtered = useMemo(() => {
    if (!activities) return [];
    const now = dayjs();

    return activities.filter((a: NearbyActivity) => {
      // Sport filter
      if (sportFilters.length > 0 && !sportFilters.includes(a.sport_key)) return false;

      // Date range filter
      if (dateRange === 'today' && !dayjs(a.starts_at).isSame(now, 'day')) return false;
      if (dateRange === 'week' && dayjs(a.starts_at).isAfter(now.add(7, 'day'))) return false;

      return true;
    });
  }, [activities, sportFilters, dateRange]);

  const emptyMessage = () => {
    if (mainTab === 'created' && (!created || created.length === 0)) return t('myActivities.emptyCreated');
    if (mainTab === 'joined' && (!joined || joined.length === 0)) return t('myActivities.emptyJoined');
    if (mainTab === 'pending' && (!pending || pending.length === 0)) return t('myActivities.emptyPending');
    if (sportFilters.length > 0 || dateRange !== 'all') return t('myActivities.noResults');
    return t('myActivities.empty');
  };

  const pendingCount = pending?.length ?? 0;

  const handleRefresh = async () => {
    setRefreshing(true);
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-created'] });
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-joined'] });
    await queryClient.invalidateQueries({ queryKey: ['activities', 'my-pending'] });
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

            <View style={styles.applyContainer}>
              <Pressable style={styles.applyButton} onPress={() => setShowFilters(false)}>
                <Text style={styles.applyText}>{t('map.apply')}</Text>
              </Pressable>
            </View>
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

  // Filter modal
  backdrop: {
    flex: 1,
    backgroundColor: colors.overlay,
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.md,
    paddingBottom: spacing.xl + 16,
    maxHeight: '70%',
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
    alignSelf: 'center',
    marginBottom: spacing.md,
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
    letterSpacing: 1,
    marginBottom: spacing.sm,
    marginTop: spacing.sm,
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs + 2,
    marginBottom: spacing.md,
  },
  chip: {
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    backgroundColor: 'transparent',
  },
  chipActive: {
    backgroundColor: colors.cta,
    borderColor: colors.cta,
  },
  chipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  chipTextActive: {
    color: '#FFFFFF',
    fontWeight: '700',
  },
  resetText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  applyContainer: {
    marginTop: spacing.md,
    paddingTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  applyButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
  },
  applyText: {
    color: '#FFFFFF',
    fontSize: fontSizes.md,
    fontWeight: '700',
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
