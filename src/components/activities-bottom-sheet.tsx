import { forwardRef, useImperativeHandle, useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import BottomSheet, { BottomSheetFlatList } from '@gorhom/bottom-sheet';
import { useTranslation } from 'react-i18next';
import { ChevronUpCircle, X } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { type ProOffering } from '@/services/pro-offering-service';
import { distanceMeters } from '@/utils/geo';
import { ActivityCard } from './activity-card';
import { ProOfferingCard } from './pro-offering-card';
import { DrawerFilterBar } from './drawer-filter-bar';

interface Props {
  activities: NearbyActivity[];
  proOfferings?: ProOffering[];
  userLocation: [number, number];
  onItemPress?: (activity: NearbyActivity) => void;
  onProOfferingPress?: (offering: ProOffering) => void;
  // Id (activity id or offering id) of the currently "peeked" item.
  // Renders a CTA-color border on the matching card so the user can
  // see the link between this card and the highlighted pin on the map.
  highlightedItemId?: string | null;
  filterLabel?: string;
  onClearFilter?: () => void;
  onCollapse?: () => void;
}

// Unified item shape so the FlatList can render either entity in the
// same scroll. Activities come first (time-pressing), offerings after
// (always-available catalog).
type ListItem =
  | { kind: 'activity'; data: NearbyActivity; distance: number }
  | { kind: 'offering'; data: ProOffering; distance: number };

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
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  return (
    <View style={styles.handleContainer} pointerEvents="box-none">
      <View style={styles.topBorder} />
      <Pressable style={styles.tab} onPress={onExpand} hitSlop={6}>
        <View style={styles.tabGrip} />
        <View style={styles.tabRow}>
          <ChevronUpCircle size={15} color={colors.textPrimary} strokeWidth={2.2} />
          <Text style={styles.tabText}>{filterLabel ?? `${label} · ${count}`}</Text>
          {filterLabel && onClearFilter && (
            <Pressable
              onPress={(e) => { e.stopPropagation(); onClearFilter(); }}
              hitSlop={10}
              style={styles.clearBtn}
              accessibilityLabel={t('map.clearFilter', { defaultValue: 'Clear filter' })}
            >
              <X size={13} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
          )}
        </View>
      </Pressable>
    </View>
  );
}

export const ActivitiesBottomSheet = forwardRef<ActivitiesBottomSheetHandle, Props>(
  function ActivitiesBottomSheet(
    { activities, proOfferings = [], userLocation, onItemPress, onProOfferingPress, highlightedItemId, filterLabel, onClearFilter, onCollapse },
    ref,
  ) {
  const { t } = useTranslation();
  const sheetRef = useRef<BottomSheet>(null);
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const snapPoints = useMemo(() => ['2%', '50%', '92%'], []);

  useImperativeHandle(ref, () => ({
    expand: () => sheetRef.current?.snapToIndex(1),
    collapse: () => sheetRef.current?.snapToIndex(0),
  }), []);

  // Activities keep the parent's chosen sort (useFilteredActivities).
  // Offerings are sorted by distance ascending — they're atemporal so
  // there's no other meaningful axis. Concatenated activities-first
  // so the time-pressing surface stays at the top.
  const items = useMemo<ListItem[]>(() => {
    const acts: ListItem[] = activities.map((a) => ({
      kind: 'activity',
      data: a,
      distance: distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) / 1000,
    }));
    const offs: ListItem[] = proOfferings
      .map((o) => ({
        kind: 'offering' as const,
        data: o,
        distance: distanceMeters(userLocation[1], userLocation[0], o.lat, o.lng) / 1000,
      }))
      .sort((a, b) => a.distance - b.distance);
    return [...acts, ...offs];
  }, [activities, proOfferings, userLocation]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      snapPoints={snapPoints}
      onChange={(idx) => { if (idx === 0) onCollapse?.(); }}
      backgroundStyle={styles.sheetBackground}
      handleComponent={() => (
        <TabHandle
          count={items.length}
          label={t('map.seeList')}
          onExpand={() => sheetRef.current?.snapToIndex(2)}
          filterLabel={filterLabel}
          onClearFilter={onClearFilter}
        />
      )}
      containerStyle={styles.sheetContainer}
      // v5 defaults dynamic sizing to ON, which makes the sheet hug its
      // content (ignoring snapPoints when shorter, overshooting when
      // longer). Off = snap points are absolute, list scrolls inside.
      enableDynamicSizing={false}
      // Let horizontal gestures escape the sheet's pan so the radius
      // slider (and any future horizontal control) keeps working. The
      // pan still activates on vertical drags as soon as direction is
      // disambiguated.
      failOffsetX={[-5, 5]}
      activeOffsetY={[-10, 10]}
    >
      <BottomSheetFlatList
        data={items}
        keyExtractor={(item) => `${item.kind}-${item.data.id}`}
        contentContainerStyle={styles.list}
        ListHeaderComponent={DrawerFilterBar}
        stickyHeaderIndices={[0]}
        renderItem={({ item }) => {
          // Tap behavior is now owned by the parent — no inline router.push.
          // Parent decides "peek (highlight pin) vs navigate (open page)"
          // based on whether the same id was already highlighted.
          const isHighlighted = highlightedItemId === item.data.id;
          if (item.kind === 'activity') {
            return (
              <ActivityCard
                activity={item.data}
                distanceKm={item.distance}
                showCreator={false}
                isHighlighted={isHighlighted}
                onPress={() => onItemPress?.(item.data)}
              />
            );
          }
          return (
            <ProOfferingCard
              offering={item.data}
              distanceKm={item.distance}
              isHighlighted={isHighlighted}
              onPress={() => onProOfferingPress?.(item.data)}
            />
          );
        }}
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
  clearBtn: {
    marginLeft: 4,
    padding: 2,
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
