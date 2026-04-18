import { useMemo, useRef } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import BottomSheet, { BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from './activity-card';

interface Props {
  activities: NearbyActivity[];
  userLocation: [number, number];
  onItemPress?: (activity: NearbyActivity) => void;
  onSheetChange?: (index: number) => void;
}

function getDistanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function TabHandle({ count, label }: { count: number; label: string }) {
  return (
    <View style={styles.handleContainer} pointerEvents="box-none">
      <View style={styles.hairline} />
      <View style={styles.tab}>
        <View style={styles.tabGrip} />
        <Text style={styles.tabCount}>{count} {label}</Text>
      </View>
    </View>
  );
}

export function ActivitiesBottomSheet({ activities, userLocation, onItemPress, onSheetChange }: Props) {
  const { t } = useTranslation();
  const router = useRouter();
  const sheetRef = useRef<BottomSheet>(null);

  const snapPoints = useMemo(() => ['3%', '50%', '92%'], []);

  const sorted = useMemo(() => {
    return activities
      .map((a) => ({ ...a, distance: getDistanceKm(userLocation[1], userLocation[0], a.lat, a.lng) }))
      .sort((a, b) => a.distance - b.distance);
  }, [activities, userLocation]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      snapPoints={snapPoints}
      backgroundStyle={styles.sheetBackground}
      handleComponent={() => <TabHandle count={sorted.length} label={t('search.results')} />}
      onChange={onSheetChange}
    >
      <BottomSheetFlatList
        data={sorted}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => (
          <ActivityCard
            activity={item}
            distanceKm={item.distance}
            onPress={() => {
              if (onItemPress) onItemPress(item);
              router.push(`/(auth)/activity/${item.id}`);
            }}
          />
        )}
        ListEmptyComponent={
          <View style={styles.empty}>
            <Text style={styles.emptyText}>{t('search.noResults')}</Text>
          </View>
        }
      />
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  sheetBackground: {
    backgroundColor: '#142D48',
    borderTopLeftRadius: 0,
    borderTopRightRadius: 0,
  },
  handleContainer: {
    height: 12,
    justifyContent: 'flex-start',
  },
  hairline: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 2,
    backgroundColor: '#142D48',
  },
  tab: {
    position: 'absolute',
    top: -36,
    left: spacing.sm,
    width: 120,
    height: 40,
    backgroundColor: '#142D48',
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'flex-start',
    paddingTop: 4,
    gap: 4,
  },
  tabGrip: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
  },
  tabCount: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
  list: {
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.xl,
  },
  empty: {
    padding: spacing.xl,
    alignItems: 'center',
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
