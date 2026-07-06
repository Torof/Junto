import { forwardRef, useCallback, useEffect, useImperativeHandle, useMemo, useRef, useState } from 'react';
import { View, Text, Pressable, StyleSheet, FlatList, Dimensions, useWindowDimensions } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import BottomSheet from '@gorhom/bottom-sheet';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
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
  // Reports whether the drawer is open above its minimum (2%) handle. Lets the
  // map hide its floating controls (filters / map style) while the list is up.
  onOpenChange?: (open: boolean) => void;
  // Fully close the drawer (index -1, handle and all) — used while a pin
  // preview sheet is up so it doesn't float over the preview.
  hidden?: boolean;
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


// Survives TabHandle remounts (module scope) — see the tabW seed below.
let lastTabW = 0;

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
  const { width: screenW } = useWindowDimensions();
  // Tab width is measured so the whole contour (line → up around the tab →
  // line) can be drawn as ONE svg path: a single stroke has perfect corners
  // by construction, and a single fill (extended 2px below the line, under
  // the sheet) leaves no visible junction between tab and drawer.
  // Seeded with the last measured width so a remount (label change, snap
  // toggle) draws the contour on its first frame instead of flashing the
  // flat no-tab line; onLayout corrects it if the label width changed.
  const [tabW, setTabW] = useState(lastTabW);
  const TAB_H = 38;
  const OVERLAP = 2;
  const r = radius.lg;
  const yLine = TAB_H - 0.5;
  const x0 = spacing.sm + 0.5;
  const x1 = spacing.sm + tabW - 0.5;
  const contour = tabW > 0
    ? `M 0 ${yLine} H ${x0} V ${0.5 + r} Q ${x0} 0.5 ${x0 + r} 0.5 H ${x1 - r} Q ${x1} 0.5 ${x1} ${0.5 + r} V ${yLine} H ${screenW}`
    : `M 0 ${yLine} H ${screenW}`;
  return (
    <View style={styles.handleContainer} pointerEvents="box-none">
      <Svg
        width={screenW}
        height={TAB_H + OVERLAP}
        style={styles.contourSvg}
        pointerEvents="none"
      >
        <Path
          d={`${contour} V ${TAB_H + OVERLAP} H 0 Z`}
          fill={colors.surfaceAlt}
        />
        <Path d={contour} fill="none" stroke={colors.pinBorder} strokeWidth={1} />
      </Svg>
      <Pressable
        style={styles.tab}
        onPress={onExpand}
        hitSlop={6}
        onLayout={(e) => {
          lastTabW = Math.round(e.nativeEvent.layout.width);
          setTabW(lastTabW);
        }}
      >
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
    { activities, proOfferings = [], userLocation, onItemPress, onProOfferingPress, highlightedItemId, filterLabel, onClearFilter, onCollapse, onOpenChange, hidden = false },
    ref,
  ) {
  const { t } = useTranslation();
  const sheetRef = useRef<BottomSheet>(null);
  const listRef = useRef<FlatList<ListItem>>(null);
  // Track snap index so the handle tap can toggle between 50% (mid)
  // and 89% (full list — clear of the status bar). gorhom drives this
  // via onChange below.
  const [snapIndex, setSnapIndex] = useState(0);
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const snapPoints = useMemo(() => ['2%', '50%', '89%'], []);

  // Fully close (index -1, handle and all) while a pin preview sheet is up,
  // then restore the 2% handle when it's gone. Driven imperatively because
  // gorhom v5 doesn't react to the `index` prop changing.
  useEffect(() => {
    if (hidden) sheetRef.current?.close();
    else sheetRef.current?.snapToIndex(0);
  }, [hidden]);

  // gorhom v5 with enableDynamicSizing=false sizes the sheet's internal
  // content container to the MAX snap height. Anything below the
  // current snap edge is rendered off-screen, so the FlatList's scroll
  // range counts items that physically sit below the visible area and
  // can never be brought into view. Constraining the inner container
  // to the current snap height in pixels makes the FlatList's scroll
  // math match what the user can actually see.
  const SNAP_RATIOS = [0.02, 0.5, 0.89];
  const screenHeight = Dimensions.get('window').height;
  const tabBarHeight = useBottomTabBarHeight();
  const HANDLE_HEIGHT = 12; // matches handleContainer style
  // The sheet sits inside the carte tab screen which sits above the
  // bottom tab bar — gorhom's snap percentages are of THIS area, not
  // the full window. Subtract the tab bar height so innerHeight
  // matches what's actually visible above the bar.
  const innerHeight = Math.max(
    0,
    (screenHeight - tabBarHeight) * (SNAP_RATIOS[snapIndex] ?? 0.5) - HANDLE_HEIGHT,
  );

  const handleToggleSnap = useCallback(() => {
    // 92% → 50% (collapse to mid for the see-map + read-list flow).
    // 50% or 2% → 92% (open fully).
    if (snapIndex === 2) sheetRef.current?.snapToIndex(1);
    else sheetRef.current?.snapToIndex(2);
  }, [snapIndex]);

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
    const base: ListItem[] = [...acts, ...offs];

    // Surface the highlighted item to index 0 so it actually IS first
    // in the list — not just scrolled there. Scrolling the list past
    // it after selection no longer reveals other items above it.
    if (!highlightedItemId) return base;
    const idx = base.findIndex((it) => it.data.id === highlightedItemId);
    if (idx <= 0) return base; // not present, or already first
    const reordered = [...base];
    const [selected] = reordered.splice(idx, 1);
    if (selected) reordered.unshift(selected);
    return reordered;
  }, [activities, proOfferings, userLocation, highlightedItemId]);

  // When the highlighted item changes, scroll it to the top of the
  // visible list so the user sees the highlighted card and the
  // highlighted pin in mirror positions (top of map, top of drawer).
  useEffect(() => {
    if (!highlightedItemId) return;
    const idx = items.findIndex((it) => it.data.id === highlightedItemId);
    if (idx < 0) return;
    // Defer to next frame — the bottom-sheet's snap animation can
    // race with scrollToIndex on the same tick and swallow it.
    requestAnimationFrame(() => {
      try {
        listRef.current?.scrollToIndex({ index: idx, animated: true, viewPosition: 0 });
      } catch {
        // scrollToIndex can throw if the row hasn't been measured yet
        // (rare in practice — items are cards with consistent height).
        // Silent fallback; the highlight tint on the card still works.
      }
    });
  }, [highlightedItemId, items]);

  // When a card is selected while the sheet is fully open (92%), drop it to
  // the mid snap (50%) so the map's zoom-to-pin lands in the freed upper half
  // instead of being hidden behind the drawer. Only collapses a FULL sheet —
  // mid/collapsed states are left untouched, and we depend solely on the
  // selection (not snapIndex) so a manual drag back to 92% isn't fought.
  useEffect(() => {
    if (highlightedItemId && snapIndex === 2) {
      sheetRef.current?.snapToIndex(1);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [highlightedItemId]);

  // Stable component for gorhom's handleComponent. The previous inline
  // arrow was a NEW component type every render, so React remounted the
  // handle on every map pan/zoom — resetting TabHandle's measured width
  // and flashing the svg contour (the "blinking tab").
  const renderHandle = useCallback(() => (
    <TabHandle
      count={items.length}
      label={t('map.seeList')}
      onExpand={handleToggleSnap}
      filterLabel={filterLabel}
      onClearFilter={onClearFilter}
    />
  ), [items.length, t, handleToggleSnap, filterLabel, onClearFilter]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      snapPoints={snapPoints}
      onChange={(idx) => {
        setSnapIndex(idx);
        if (idx === 0) onCollapse?.();
        // idx 0 = 2% handle (minimum); anything higher = drawer is "open".
        onOpenChange?.(idx > 0);
      }}
      backgroundStyle={styles.sheetBackground}
      handleComponent={renderHandle}
      containerStyle={styles.sheetContainer}
      // v5 defaults dynamic sizing to ON, which makes the sheet hug its
      // content (ignoring snapPoints when shorter, overshooting when
      // longer). Off = snap points are absolute, list scrolls inside.
      enableDynamicSizing={false}
      // Decouple the list's pan from the sheet's snap so the FlatList
      // scrolls independently at any snap point. At 50% snap, scrolling
      // the list scrolls it instead of pulling the sheet up to 92%.
      // Snap changes happen via the tab handle (tap to toggle 50% ↔ 92%,
      // drag for fine control). The failOffsetX/activeOffsetY configs
      // from the canonical-content-panning path are intentionally
      // absent here — with content panning off, they'd just disable
      // the gesture handler wrapping the list and starve the native
      // FlatList of scroll events.
      enableContentPanningGesture={false}
    >
      <View style={[styles.sheetContent, { height: innerHeight }]}>
      <FlatList
        ref={listRef}
        data={items}
        keyExtractor={(item) => `${item.kind}-${item.data.id}`}
        style={styles.flatList}
        contentContainerStyle={styles.list}
        ListHeaderComponent={DrawerFilterBar}
        stickyHeaderIndices={[0]}
        showsVerticalScrollIndicator
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
      </View>
    </BottomSheet>
  );
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  sheetContainer: {
    zIndex: 20,
  },
  sheetContent: {
    // No flex — the inline `height` from innerHeight sets the absolute
    // pixel height matching the current snap, and flex would fight it.
    overflow: 'hidden',
  },
  flatList: {
    flex: 1,
  },
  // No border on the background — the svg contour IS the line (a bg border
  // would run under the tab and reintroduce the stray pixels).
  sheetBackground: {
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: 0,
    borderTopRightRadius: 0,
  },
  handleContainer: {
    height: 12,
    justifyContent: 'flex-start',
  },
  // Whole contour (line + tab outline + fill) in one svg — single stroke =
  // clean corners, single fill overlapping 2px under the sheet = no seam.
  contourSvg: {
    position: 'absolute',
    top: -38,
    left: 0,
  },
  // Invisible hit/content area — the svg draws the tab's fill and border.
  tab: {
    position: 'absolute',
    top: -38,
    left: spacing.sm,
    height: 38,
    alignItems: 'center',
    justifyContent: 'flex-start',
    paddingTop: 4,
    paddingHorizontal: spacing.md,
    gap: 4,
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
