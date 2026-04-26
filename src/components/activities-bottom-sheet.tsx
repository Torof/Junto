import { useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import BottomSheet, { BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { ChevronUpCircle } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityCard } from './activity-card';

interface Props {
  activities: NearbyActivity[];
  userLocation: [number, number];
  onItemPress?: (activity: NearbyActivity) => void;
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

function TabHandle({ count, label, onExpand }: { count: number; label: string; onExpand: () => void }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <View style={styles.handleContainer} pointerEvents="box-none">
      <View style={styles.topBorder} />
      <Pressable style={styles.tab} onPress={onExpand} hitSlop={6}>
        <View style={styles.tabGrip} />
        <View style={styles.tabRow}>
          <ChevronUpCircle size={15} color={colors.textPrimary} strokeWidth={2.2} />
          <Text style={styles.tabText}>{label} · {count}</Text>
        </View>
      </Pressable>
    </View>
  );
}

export function ActivitiesBottomSheet({ activities, userLocation, onItemPress }: Props) {
  const { t } = useTranslation();
  const router = useRouter();
  const sheetRef = useRef<BottomSheet>(null);
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

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
      handleComponent={() => (
        <TabHandle
          count={sorted.length}
          label={t('map.seeList')}
          onExpand={() => sheetRef.current?.snapToIndex(2)}
        />
      )}
      containerStyle={styles.sheetContainer}
    >
      <BottomSheetFlatList
        data={sorted}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => (
          <ActivityCard
            activity={item}
            distanceKm={item.distance}
            showCreator={false}
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

const createStyles = (colors: AppColors) => StyleSheet.create({
  sheetContainer: {
    zIndex: 20,
  },
  sheetBackground: {
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: 0,
    borderTopRightRadius: 0,
    borderTopWidth: 1,
    borderTopColor: colors.pinBorder,
  },
  handleContainer: {
    height: 12,
    justifyContent: 'flex-start',
  },
  topBorder: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 1,
    backgroundColor: colors.pinBorder,
  },
  tab: {
    position: 'absolute',
    top: -38,
    left: spacing.sm,
    height: 40,
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    alignItems: 'center',
    justifyContent: 'flex-start',
    paddingTop: 4,
    paddingHorizontal: spacing.md,
    gap: 4,
    borderTopWidth: 1,
    borderLeftWidth: 1,
    borderRightWidth: 1,
    borderColor: colors.pinBorder,
  },
  tabGrip: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
  },
  tabRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  tabText: {
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
