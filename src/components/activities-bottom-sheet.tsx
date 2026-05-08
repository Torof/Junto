import { forwardRef, useImperativeHandle, useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import BottomSheet, { BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { ChevronUpCircle, X } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { distanceMeters } from '@/utils/geo';
import { ActivityCard } from './activity-card';

interface Props {
  activities: NearbyActivity[];
  userLocation: [number, number];
  onItemPress?: (activity: NearbyActivity) => void;
  filterLabel?: string;
  onClearFilter?: () => void;
  onCollapse?: () => void;
}

export interface ActivitiesBottomSheetHandle {
  expand: () => void;
  collapse: () => void;
}


function TabHandle({ count, label, onExpand, filterLabel, onClearFilter }: {
  count: number;
  label: string;
  onExpand: () => void;
  filterLabel?: string;
  onClearFilter?: () => void;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <View style={styles.handleContainer} pointerEvents="box-none">
      <View style={styles.topBorder} />
      <Pressable style={styles.tab} onPress={onExpand} hitSlop={6}>
        <View style={styles.tabRow}>
          <ChevronUpCircle size={16} color={colors.textPrimary} strokeWidth={2.2} />
          <Text style={styles.tabText}>{filterLabel ?? `${label} · ${count}`}</Text>
          {filterLabel && onClearFilter && (
            <Pressable
              onPress={(e) => { e.stopPropagation(); onClearFilter(); }}
              hitSlop={10}
              style={styles.clearBtn}
            >
              <X size={14} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
          )}
        </View>
      </Pressable>
    </View>
  );
}

export const ActivitiesBottomSheet = forwardRef<ActivitiesBottomSheetHandle, Props>(
  function ActivitiesBottomSheet(
    { activities, userLocation, onItemPress, filterLabel, onClearFilter, onCollapse },
    ref,
  ) {
  const { t } = useTranslation();
  const router = useRouter();
  const sheetRef = useRef<BottomSheet>(null);
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const snapPoints = useMemo(() => ['3%', '50%', '92%'], []);

  useImperativeHandle(ref, () => ({
    expand: () => sheetRef.current?.snapToIndex(1),
    collapse: () => sheetRef.current?.snapToIndex(0),
  }), []);

  const sorted = useMemo(() => {
    return activities
      .map((a) => ({ ...a, distance: distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) / 1000 }))
      .sort((a, b) => a.distance - b.distance);
  }, [activities, userLocation]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      snapPoints={snapPoints}
      onChange={(idx) => { if (idx === 0) onCollapse?.(); }}
      backgroundStyle={styles.sheetBackground}
      handleComponent={() => (
        <TabHandle
          count={sorted.length}
          label={t('map.seeList')}
          onExpand={() => sheetRef.current?.snapToIndex(2)}
          filterLabel={filterLabel}
          onClearFilter={onClearFilter}
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
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  sheetContainer: {
    zIndex: 20,
  },
  sheetBackground: {
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: 0,
    borderTopRightRadius: 0,
    borderTopWidth: 1,
    borderTopColor: colors.borderStrong,
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
    backgroundColor: colors.borderStrong,
  },
  tab: {
    position: 'absolute',
    top: -34,
    left: spacing.sm,
    height: 36,
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: radius.xs,
    borderTopRightRadius: radius.xs,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
    borderTopWidth: 1,
    borderLeftWidth: 1,
    borderRightWidth: 1,
    borderColor: colors.borderStrong,
  },
  tabRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  tabText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
  clearBtn: {
    marginLeft: 2,
    padding: 2,
    borderRadius: radius.xs,
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
