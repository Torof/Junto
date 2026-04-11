import { useState, useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from '@/components/activity-card';

type MainTab = 'created' | 'joined';
type TimeFilter = 'upcoming' | 'finished';

export default function MesActivitesScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const [mainTab, setMainTab] = useState<MainTab>('created');
  const [timeFilter, setTimeFilter] = useState<TimeFilter>('upcoming');

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
      const isUpcoming = dayjs(a.starts_at).isAfter(now) && !['completed', 'cancelled', 'expired'].includes(a.status);
      return timeFilter === 'upcoming' ? isUpcoming : !isUpcoming;
    });
  }, [activities, timeFilter]);

  const emptyMessage = () => {
    if (mainTab === 'created' && (!created || created.length === 0)) return t('myActivities.emptyCreated');
    if (mainTab === 'joined' && (!joined || joined.length === 0)) return t('myActivities.emptyJoined');
    return timeFilter === 'upcoming' ? t('myActivities.emptyUpcoming') : t('myActivities.emptyFinished');
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
    paddingBottom: spacing.sm,
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
