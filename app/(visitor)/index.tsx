import { useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { JuntoMapView } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivityList } from '@/components/activity-list';
import { ViewToggle } from '@/components/view-toggle';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { useMapStore } from '@/store/map-store';
import { type NearbyActivity } from '@/services/activity-service';

export default function VisitorMapScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();
  const filtered = useFilteredActivities(activities ?? []);
  const { viewMode } = useMapStore();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  return (
    <View style={styles.container}>
      <FilterButton onPress={() => setShowFilters(true)} />
      <ViewToggle />

      {viewMode === 'map' ? (
        <>
          <JuntoMapView
            center={center}
            activities={filtered}
            onActivityPress={setSelectedActivity}
          />

          {selectedActivity && (
            <ActivityPopup
              activity={selectedActivity}
              onViewDetail={() => {
                router.push(`/(visitor)/activity/${selectedActivity.id}`);
                setSelectedActivity(null);
              }}
              onClose={() => setSelectedActivity(null)}
            />
          )}
        </>
      ) : (
        <ActivityList activities={filtered} routePrefix="/(visitor)" />
      )}

      {!selectedActivity && viewMode === 'map' && (
        <View style={styles.overlay}>
          <Text style={styles.title}>{t('app.name')}</Text>
          <Text style={styles.subtitle}>{t('visitor.explore')}</Text>

          <Pressable style={styles.loginButton} onPress={() => router.push('/(visitor)/login')}>
            <Text style={styles.loginText}>{t('auth.signIn')}</Text>
          </Pressable>
        </View>
      )}

      <FilterSheet visible={showFilters} onClose={() => setShowFilters(false)} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  overlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: colors.background + 'E6',
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.lg,
    paddingBottom: spacing.xl + 16,
    alignItems: 'center',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontWeight: 'bold',
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    marginTop: spacing.xs,
    marginBottom: spacing.md,
    textAlign: 'center',
  },
  loginButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.md,
  },
  loginText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
