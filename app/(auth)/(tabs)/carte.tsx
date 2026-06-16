import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { useFocusEffect } from 'expo-router';
import { useQueryClient } from '@tanstack/react-query';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { SafeAreaView } from 'react-native-safe-area-context';
import { X, MapPin, Flag, Trophy } from 'lucide-react-native';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ProPopup } from '@/components/pro-popup';
import { ProOfferingPopup } from '@/components/pro-offering-popup';
import { ActivitiesBottomSheet, type ActivitiesBottomSheetHandle } from '@/components/activities-bottom-sheet';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { CreateButton } from '@/components/create-button';
import { AlertButton } from '@/components/alert-button';
import { MapStyleButton } from '@/components/map-style-button';
import { RecenterButton } from '@/components/recenter-button';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';
import { useNearbyPros } from '@/hooks/use-nearby-pros';
import { useNearbyProOfferings } from '@/hooks/use-nearby-pro-offerings';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { useFilteredOfferings } from '@/hooks/use-filtered-offerings';
import { useMapStore } from '@/store/map-store';
import { type NearbyActivity } from '@/services/activity-service';
import { useCreateStore } from '@/store/create-store';
import { IntroCarousel } from '@/components/intro-carousel';
import { useIntroStore } from '@/store/intro-store';
import { supabase } from '@/services/supabase';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

const BUFFER = 0.5; // 50% buffer around viewport

function addBuffer(bounds: MapBounds): QueryBounds {
  const lngSpan = bounds.neLng - bounds.swLng;
  const latSpan = bounds.neLat - bounds.swLat;
  return {
    swLng: bounds.swLng - lngSpan * BUFFER,
    swLat: bounds.swLat - latSpan * BUFFER,
    neLng: bounds.neLng + lngSpan * BUFFER,
    neLat: bounds.neLat + latSpan * BUFFER,
  };
}

function isWithinFetchedBounds(current: MapBounds, fetched: QueryBounds): boolean {
  return (
    current.swLng >= fetched.swLng &&
    current.swLat >= fetched.swLat &&
    current.neLng <= fetched.neLng &&
    current.neLat <= fetched.neLat
  );
}

// panDistance is a degree-space pythagorean used to compare to viewport
// width; deliberately distinct from the geographic haversine in @/utils/geo
// because the units cancel out in the ratio.
function panDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dlat = lat2 - lat1;
  const dlng = lng2 - lng1;
  return Math.sqrt(dlat * dlat + dlng * dlng);
}

export default function CarteScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const router = useRouter();
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const { center, currentLocation } = useInitialLocation();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  // Preview selection for pro / offering pins — first tap shows the
  // PinPreviewCard at the bottom of the screen; second tap on the
  // same pin (or anywhere on the preview card) opens the detail page.
  // Tap on the map elsewhere dismisses. Mutually exclusive with the
  // activity selection — picking one clears the other.
  const [selectedPro, setSelectedPro] = useState<import('@/services/pro-service').NearbyPro | null>(null);
  const [selectedOffering, setSelectedOffering] = useState<import('@/services/pro-offering-service').ProOffering | null>(null);
  // Drawer-list "peek" state — when the user taps a card, the matching
  // pin scales up and the card gets a CTA tint. Second tap on the
  // same card opens the detail page. Cards already carry the info the
  // tooltip would, so no popup fires for card taps.
  const [highlightedPinId, setHighlightedPinId] = useState<string | null>(null);
  const [showFilters, setShowFilters] = useState(false);
  const [flyToKey, setFlyToKey] = useState(0);
  const [flyTarget, setFlyTarget] = useState<[number, number] | null>(null);
  const [flyOffset, setFlyOffset] = useState<{ x?: number; y?: number } | undefined>(undefined);
  const [tappedPoint, setTappedPoint] = useState<{ lng: number; lat: number } | null>(null);
  const suppressMapPressUntil = useRef(0);
  const selectionBoundsSpan = useRef<number | null>(null);
  const introChecked = useRef(false);
  const [showIntro, setShowIntro] = useState(false);
  const replayRequested = useIntroStore((s) => s.replayRequested);
  const clearReplay = useIntroStore((s) => s.clearReplay);

  const [clusterFilter, setClusterFilter] = useState<NearbyActivity[] | null>(null);
  const clusterFilterAnchor = useRef<MapBounds | null>(null);
  const sheetRef = useRef<ActivitiesBottomSheetHandle>(null);
  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);
  const searchDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { data: activities } = useNearbyActivities(searchBounds);
  const { data: pros } = useNearbyPros(searchBounds);
  const { data: proOfferings } = useNearbyProOfferings(searchBounds);
  const filtered = useFilteredActivities(activities ?? [], currentLocation ?? center);
  const filteredOfferings = useFilteredOfferings(proOfferings ?? [], currentLocation ?? center);
  const radiusKm = useMapStore((s) => s.filters.radiusKm);
  // Entity-type filter — both default true; the filter sheet's
  // Activités / Pros checkboxes flip these. Empty arrays go to both
  // the map (no pins of that type) and the bottom-sheet drawer.
  const showActivities = useMapStore((s) => s.filters.showActivities);
  const showProOfferings = useMapStore((s) => s.filters.showProOfferings);
  const filteredActivitiesByType = showActivities ? filtered : [];
  const filteredOfferingsByType = showProOfferings ? filteredOfferings : [];
  // The "Pros" checkbox means the whole pro layer — storefront pins (PP)
  // AND offering pins (RA). It used to hide only the offerings.
  const filteredProsByType = showProOfferings ? (pros ?? []) : [];

  const doSearch = useCallback((bounds: MapBounds) => {
    lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
    setSearchBounds(addBuffer(bounds));
  }, []);

  const scheduleSearch = useCallback((bounds: MapBounds) => {
    if (searchDebounce.current) clearTimeout(searchDebounce.current);
    searchDebounce.current = setTimeout(() => {
      doSearch(bounds);
      searchDebounce.current = null;
    }, 500);
  }, [doSearch]);

  useEffect(() => {
    return () => {
      if (searchDebounce.current) clearTimeout(searchDebounce.current);
    };
  }, []);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;
    setTappedPoint(null);

    // Clear the cluster-filter drawer once the user starts navigating again
    // (zoom or pan beyond a small threshold). Tapping the cluster doesn't move
    // the camera, so the filter survives until the user actually moves on.
    if (clusterFilter !== null && clusterFilterAnchor.current) {
      const a = clusterFilterAnchor.current;
      const oldSpan = Math.abs(a.neLng - a.swLng);
      const newSpan = Math.abs(bounds.neLng - bounds.swLng);
      const zoomChanged = Math.abs(newSpan - oldSpan) / oldSpan > 0.05;
      const panMoved =
        Math.abs(bounds.centerLng - a.centerLng) > oldSpan * 0.1 ||
        Math.abs(bounds.centerLat - a.centerLat) > oldSpan * 0.1;
      if (zoomChanged || panMoved) {
        setClusterFilter(null);
        clusterFilterAnchor.current = null;
      }
    }

    // Close the popup on zoom-out: track the smallest viewport span since selection,
    // close when the current viewport grows 30%+ above that minimum. Same rule
    // for all three popup types (activity / pro / offering).
    if (selectionBoundsSpan.current !== null) {
      const newSpan = Math.abs(bounds.neLng - bounds.swLng);
      if (newSpan < selectionBoundsSpan.current) {
        selectionBoundsSpan.current = newSpan;
      } else if (newSpan > selectionBoundsSpan.current * 1.3) {
        setSelectedActivity(null);
        setSelectedPro(null);
        setSelectedOffering(null);
        selectionBoundsSpan.current = null;
      }
    }

    // First load — auto-search immediately
    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      doSearch(bounds);
      return;
    }

    // Viewport extends beyond fetched buffer (typically a zoom-out) — fetch immediately
    // so newly-uncovered areas populate without waiting for the debounce window.
    if (searchBounds && !isWithinFetchedBounds(bounds, searchBounds)) {
      if (searchDebounce.current) {
        clearTimeout(searchDebounce.current);
        searchDebounce.current = null;
      }
      doSearch(bounds);
      return;
    }

    // Significant pan inside the buffered area — debounced refetch
    if (lastSearchCenter.current) {
      const viewportWidth = Math.abs(bounds.neLng - bounds.swLng);
      const dist = panDistance(
        lastSearchCenter.current.lat, lastSearchCenter.current.lng,
        bounds.centerLat, bounds.centerLng,
      );
      if (dist > viewportWidth * 0.3) {
        scheduleSearch(bounds);
      }
    }
  }, [searchBounds, doSearch, scheduleSearch, clusterFilter]);

  // First-run intro: show the one-time carousel if the user hasn't seen it.
  // No element anchoring or step machinery — it's a self-contained overlay.
  useEffect(() => {
    if (introChecked.current) return;
    introChecked.current = true;
    (async () => {
      const { data: userRow } = await supabase
        .from('users')
        .select('tutorial_seen_at')
        .single() as { data: { tutorial_seen_at: string | null } | null };
      if (!userRow?.tutorial_seen_at) setShowIntro(true);
    })();
  }, []);

  const dismissIntro = useCallback(() => {
    setShowIntro(false);
    void supabase.rpc('mark_tutorial_seen' as 'accept_tos');
  }, []);

  // Replay requested from the settings drawer ("Revoir l'intro").
  useEffect(() => {
    if (replayRequested) {
      setShowIntro(true);
      clearReplay();
    }
  }, [replayRequested, clearReplay]);

  // Refresh activity statuses every time the map tab gets focus
  useFocusEffect(
    useCallback(() => {
      (async () => {
        await supabase.rpc('check_activity_transitions' as 'accept_tos');
        // Invalidate so the freshly-transitioned statuses are re-fetched
        await queryClient.invalidateQueries({ queryKey: ['activities'] });
      })();
    }, [queryClient])
  );

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.statusBar} />

      <View style={styles.content}>
        <CreateButton />
        <RecenterButton onPress={() => { setFlyTarget(null); setFlyOffset(undefined); setFlyToKey((k) => k + 1); }} />
        <AlertButton />

        {/* Top-left controls row — filters chip + map style icon
            (Scott 2026-06-10). Sits at the left edge so the centered
            chip doesn't read as lonely and we stay clear of the
            Mapbox compass at top-right. */}
        <View style={styles.topControls}>
          <FilterButton onPress={() => setShowFilters(true)} />
          <MapStyleButton />
        </View>

        <>

            <JuntoMapView
              center={center}
              activities={filteredActivitiesByType}
              pros={filteredProsByType}
              onProPress={(pro) => {
                setTappedPoint(null);
                setSelectedActivity(null);
                setSelectedOffering(null);
                setHighlightedPinId(null);
                if (selectedPro?.user_id === pro.user_id) {
                  // Second tap: open the full pro page.
                  suppressMapPressUntil.current = Date.now() + 400;
                  router.push(`/(auth)/pro/${pro.user_id}`);
                  setSelectedPro(null);
                  selectionBoundsSpan.current = null;
                } else {
                  if (currentBounds.current) {
                    selectionBoundsSpan.current = Math.abs(currentBounds.current.neLng - currentBounds.current.swLng);
                  }
                  const cb = currentBounds.current;
                  const viewCenterLng = cb ? (cb.swLng + cb.neLng) / 2 : pro.primary_lng;
                  const offsetX = pro.primary_lng < viewCenterLng ? 0.25 : -0.25;
                  setFlyTarget([pro.primary_lng, pro.primary_lat]);
                  setFlyOffset({ x: offsetX, y: -0.28 });
                  setFlyToKey((k) => k + 1);
                  setSelectedPro(pro);
                }
              }}
              proOfferings={filteredOfferingsByType}
              onProOfferingPress={(offering) => {
                setTappedPoint(null);
                setSelectedActivity(null);
                setSelectedPro(null);
                setHighlightedPinId(null);
                if (selectedOffering?.id === offering.id) {
                  // Second tap: open the full offering page.
                  suppressMapPressUntil.current = Date.now() + 400;
                  router.push(`/(auth)/pro/offering/${offering.id}`);
                  setSelectedOffering(null);
                  selectionBoundsSpan.current = null;
                } else {
                  if (currentBounds.current) {
                    selectionBoundsSpan.current = Math.abs(currentBounds.current.neLng - currentBounds.current.swLng);
                  }
                  const cb = currentBounds.current;
                  const viewCenterLng = cb ? (cb.swLng + cb.neLng) / 2 : offering.lng;
                  const offsetX = offering.lng < viewCenterLng ? 0.25 : -0.25;
                  setFlyTarget([offering.lng, offering.lat]);
                  setFlyOffset({ x: offsetX, y: -0.28 });
                  setFlyToKey((k) => k + 1);
                  setSelectedOffering(offering);
                }
              }}
              userLocation={currentLocation ?? center}
              radiusKm={radiusKm}
              radiusCenter={currentLocation ?? center}
              tapMarker={tappedPoint && !selectedActivity ? [tappedPoint.lng, tappedPoint.lat] : null}
              tapMarkerContent={tappedPoint && !selectedActivity ? (
                <View style={styles.tapMarkerContent}>
                  <X size={22} color={colors.error} strokeWidth={3} />
                  <View style={styles.createTooltipCard}>
                    <Text style={styles.createTooltipHeader}>{t('map.createHere')}</Text>
                    <Pressable
                      style={[styles.createTooltipRow, { borderLeftColor: colors.pinMeeting }]}
                      onPress={() => {
                        useCreateStore.getState().resetForm();
                        useCreateStore.getState().updateForm({ location_meeting: tappedPoint });
                        setTappedPoint(null);
                        router.push('/(auth)/create/step1');
                      }}
                    >
                      <MapPin size={18} color={colors.pinMeeting} strokeWidth={2.4} />
                      <Text style={styles.createTooltipRowText}>{t('create.meetingPoint')}</Text>
                    </Pressable>
                    <Pressable
                      style={[styles.createTooltipRow, { borderLeftColor: colors.pinStart }]}
                      onPress={() => {
                        useCreateStore.getState().resetForm();
                        useCreateStore.getState().updateForm({ location_start: tappedPoint });
                        setTappedPoint(null);
                        router.push('/(auth)/create/step1');
                      }}
                    >
                      <Flag size={18} color={colors.pinStart} strokeWidth={2.4} />
                      <Text style={styles.createTooltipRowText}>{t('create.startPoint')}</Text>
                    </Pressable>
                    <Pressable
                      style={[styles.createTooltipRow, { borderLeftColor: colors.pinObjective }]}
                      onPress={() => {
                        useCreateStore.getState().resetForm();
                        useCreateStore.getState().updateForm({ location_objective: tappedPoint });
                        setTappedPoint(null);
                        router.push('/(auth)/create/step1');
                      }}
                    >
                      <Trophy size={18} color={colors.pinObjective} strokeWidth={2.4} />
                      <Text style={styles.createTooltipRowText}>{t('create.objectiveSet')}</Text>
                    </Pressable>
                  </View>
                </View>
              ) : undefined}
              flyTo={flyToKey > 0 ? { coordinate: flyTarget ?? center, key: flyToKey, offsetRatio: flyOffset } : null}
              selectedActivity={selectedActivity}
              selectedPro={selectedPro}
              selectedOffering={selectedOffering}
              highlightedPinId={highlightedPinId}
              popupContent={selectedActivity ? (
                <ActivityPopup
                  activity={selectedActivity}
                  onPress={() => {
                    suppressMapPressUntil.current = Date.now() + 400;
                    router.push(`/(auth)/activity/${selectedActivity.id}`);
                    setSelectedActivity(null);
                  }}
                />
              ) : undefined}
              proPopupContent={selectedPro ? (
                <ProPopup
                  pro={selectedPro}
                  onPress={() => {
                    suppressMapPressUntil.current = Date.now() + 400;
                    router.push(`/(auth)/pro/${selectedPro.user_id}`);
                    setSelectedPro(null);
                  }}
                />
              ) : undefined}
              offeringPopupContent={selectedOffering ? (
                <ProOfferingPopup
                  offering={selectedOffering}
                  onPress={() => {
                    suppressMapPressUntil.current = Date.now() + 400;
                    router.push(`/(auth)/pro/offering/${selectedOffering.id}`);
                    setSelectedOffering(null);
                  }}
                />
              ) : undefined}
              onActivityPress={(a) => {
                setTappedPoint(null);
                setSelectedPro(null);
                setSelectedOffering(null);
                setHighlightedPinId(null);
                if (selectedActivity?.id === a.id) {
                  // Second tap on the same pin → open the activity page
                  suppressMapPressUntil.current = Date.now() + 400;
                  router.push(`/(auth)/activity/${a.id}`);
                  setSelectedActivity(null);
                  selectionBoundsSpan.current = null;
                } else {
                  // Snapshot the viewport span so we can detect a later zoom-out
                  if (currentBounds.current) {
                    selectionBoundsSpan.current = Math.abs(currentBounds.current.neLng - currentBounds.current.swLng);
                  }
                  // Shift sideways so the popup gets a clear horizontal
                  // runway. Pin on the left half of the viewport lands
                  // at 25% from the left (popup extends right); right
                  // half → 75% (popup extends left). Vertical position
                  // is locked: flyTo's coordinate.lat is set to the
                  // CURRENT viewport's center lat, not the pin's, so
                  // the camera only zooms + slides horizontally.
                  // Land the pin at a fixed position: top third
                  // vertically (y: -0.28) and 25% or 75% horizontally
                  // depending on which side it currently sits on.
                  const cb = currentBounds.current;
                  const viewCenterLng = cb ? (cb.swLng + cb.neLng) / 2 : a.lng;
                  const offsetX = a.lng < viewCenterLng ? 0.25 : -0.25;
                  setFlyTarget([a.lng, a.lat]);
                  setFlyOffset({ x: offsetX, y: -0.28 });
                  setFlyToKey((k) => k + 1);
                  setSelectedActivity(a);
                }
              }}
              onMapPress={(lng, lat) => {
                if (Date.now() < suppressMapPressUntil.current) return;
                // Card-peek highlight dismisses on any map press too.
                if (highlightedPinId) {
                  setHighlightedPinId(null);
                  return;
                }
                // Pro / offering previews dismiss on any map press.
                if (selectedPro || selectedOffering) {
                  setSelectedPro(null);
                  setSelectedOffering(null);
                  return;
                }
                if (selectedActivity) {
                  const dLng = Math.abs(lng - selectedActivity.lng);
                  const dLat = Math.abs(lat - selectedActivity.lat);
                  const viewportSpan = currentBounds.current
                    ? Math.abs(currentBounds.current.neLng - currentBounds.current.swLng)
                    : 0.01;
                  if (dLng < viewportSpan * 0.05 && dLat < viewportSpan * 0.05) {
                    suppressMapPressUntil.current = Date.now() + 400;
                    router.push(`/(auth)/activity/${selectedActivity.id}`);
                    setSelectedActivity(null);
                    selectionBoundsSpan.current = null;
                    return;
                  }
                  setSelectedActivity(null);
                  return;
                }
                setTappedPoint({ lng, lat });
              }}
              onBoundsChange={handleBoundsChange}
              onStuckClusterPress={(stuck) => {
                setSelectedActivity(null);
                setClusterFilter(stuck);
                clusterFilterAnchor.current = currentBounds.current;
                // Defer one frame so the sheet sees the new activities list before expanding
                requestAnimationFrame(() => sheetRef.current?.expand());
              }}
            />


        </>

        <ActivitiesBottomSheet
          ref={sheetRef}
          activities={clusterFilter ?? filteredActivitiesByType}
          proOfferings={filteredOfferingsByType}
          userLocation={currentLocation ?? center}
          highlightedItemId={highlightedPinId}
          filterLabel={clusterFilter ? t('map.activitiesAtPoint', { count: clusterFilter.length }) : undefined}
          onClearFilter={() => { setClusterFilter(null); clusterFilterAnchor.current = null; }}
          onCollapse={() => { setClusterFilter(null); clusterFilterAnchor.current = null; }}
          onItemPress={(a) => {
            // Tap-to-peek: first tap on a card highlights the pin on
            // the map; second tap on the same card opens the detail
            // page. Cards already carry the info the tooltip would, so
            // no popup is fired for card taps.
            if (highlightedPinId === a.id) {
              suppressMapPressUntil.current = Date.now() + 400;
              router.push(`/(auth)/activity/${a.id}`);
              setHighlightedPinId(null);
              return;
            }
            // Clear any pin-tap state (mutually exclusive with peek).
            setSelectedActivity(null);
            setSelectedPro(null);
            setSelectedOffering(null);
            setHighlightedPinId(a.id);
            // Fly the map so the pin lands at ~22% from the top —
            // well above the 50% drawer line and clearly visible in
            // the top half. Negative y shifts the camera south so the
            // pin moves UP on screen relative to center.
            setFlyTarget([a.lng, a.lat]);
            setFlyOffset({ y: -0.28 });
            setFlyToKey((k) => k + 1);
          }}
          onProOfferingPress={(o) => {
            if (highlightedPinId === o.id) {
              suppressMapPressUntil.current = Date.now() + 400;
              router.push(`/(auth)/pro/offering/${o.id}`);
              setHighlightedPinId(null);
              return;
            }
            setSelectedActivity(null);
            setSelectedPro(null);
            setSelectedOffering(null);
            setHighlightedPinId(o.id);
            setFlyTarget([o.lng, o.lat]);
            setFlyOffset({ y: -0.28 });
            setFlyToKey((k) => k + 1);
          }}
        />

        <FilterSheet visible={showFilters} onClose={() => setShowFilters(false)} />
      </View>

      {showIntro && <IntroCarousel onDone={dismissIntro} />}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  tapMarkerContent: {
    alignItems: 'center',
    gap: spacing.xs,
  },
  createTooltipCard: {
    backgroundColor: colors.background,
    borderRadius: radius.lg,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.sm,
    minWidth: 200,
    elevation: 6,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.18,
    shadowRadius: 6,
    gap: spacing.xs,
  },
  createTooltipHeader: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
    paddingHorizontal: spacing.sm,
    paddingTop: spacing.xs,
    paddingBottom: spacing.xs,
  },
  createTooltipRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderLeftWidth: 4,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
  },
  createTooltipRowText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    flex: 1,
  },
  statusBar: {
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
  },
  topControls: {
    position: 'absolute',
    top: spacing.md,
    left: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    zIndex: 10,
  },
});

