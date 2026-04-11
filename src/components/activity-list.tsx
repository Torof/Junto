import { FlatList, View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing } from '@/constants/theme';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from './activity-card';

interface ActivityListProps {
  activities: NearbyActivity[];
  routePrefix: '/(visitor)' | '/(auth)';
}

export function ActivityList({ activities, routePrefix }: ActivityListProps) {
  const { t } = useTranslation();
  const router = useRouter();

  if (activities.length === 0) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyText}>{t('map.noActivities')}</Text>
      </View>
    );
  }

  return (
    <FlatList
      data={activities}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => (
        <ActivityCard
          activity={item}
          onPress={() => router.push(`${routePrefix}/activity/${item.id}`)}
        />
      )}
      contentContainerStyle={styles.list}
      style={styles.container}
    />
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  list: {
    padding: spacing.md,
  },
  empty: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
