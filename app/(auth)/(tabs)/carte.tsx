import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { useFocusEffect } from 'expo-router';
import { useQueryClient } from '@tanstack/react-query';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { SafeAreaView } from 'react-native-safe-area-context';
import { X } from 'lucide-react-native';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivitiesBottomSheet, type ActivitiesBottomSheetHandle } from '@/components/activities-bottom-sheet';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { CreateButton } from '@/components/create-button';
import { MapStyleButton } from '@/components/map-style-button';
import { RecenterButton } from '@/components/recenter-button';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { type NearbyActivity } from '@/services/activity-service';
import { useCreateStore } from '@/store/create-store';
import { useTutorialStore } from '@/store/tutorial-store';
import { TutorialTooltip } from '@/components/tutorial-tooltip';
import { supabase } from '@/services/supabase';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { distanceMeters } from '@/utils/geo';

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
  const [showFilters, setShowFilters] = useState(false);
  const [flyToKey, setFlyToKey] = useState(0);
  const [flyTarget, setFlyTarget] = useState<[number, number] | null>(null);
  const [flyOffset, setFlyOffset] = useState<{ x?: number; y?: number } | undefined>(undefined);
  const [tappedPoint, setTappedPoint] = useState<{ lng: number; lat: number } | null>(null);
  const suppressMapPressUntil = useRef(0);
  const selectionBoundsSpan = useRef<number | null>(null);
  const tutorialStep = useTutorialStore((s) => s.step);
  const setTutorialStep = useTutorialStore((s) => s.setStep);
  const tutorialChecked = useRef(false);
  const [showAlertTooltip, setShowAlertTooltip] = useState(false);

  const [clusterFilter, setClusterFilter] = useState<NearbyActivity[] | null>(null);
  const clusterFilterAnchor = useRef<MapBounds | null>(null);
  const sheetRef = useRef<ActivitiesBottomSheetHandle>(null);
  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);
  const searchDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { data: activities } = useNearbyActivities(searchBounds);
  const filtered = useFilteredActivities(activities ?? []);

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
    // close when the current viewport grows 30%+ above that minimum.
    if (selectionBoundsSpan.current !== null) {
      const newSpan = Math.abs(bounds.neLng - bounds.swLng);
      if (newSpan < selectionBoundsSpan.current) {
        selectionBoundsSpan.current = newSpan;
      } else if (newSpan > selectionBoundsSpan.current * 1.3) {
        setSelectedActivity(null);
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

  // Tutorial bootstrap: first visit check
  useEffect(() => {
    if (tutorialChecked.current) return;
    if (!activities) return; // wait for first fetch
    tutorialChecked.current = true;

    (async () => {
      const { data: userRow } = await supabase
        .from('users')
        .select('tutorial_seen_at')
        .single() as { data: { tutorial_seen_at: string | null } | null };

      if (userRow?.tutorial_seen_at) return;

      // Find the closest real activity around the user — tutorial uses it as target.
      // No demo activity is created (avoids polluting other users' maps).
      const list = activities ?? [];
      if (list.length > 0) {
        let nearest = list[0]!;
        let nearestDist = distanceMeters(center[1], center[0], nearest.lat, nearest.lng);
        for (const a of list) {
          const d = distanceMeters(center[1], center[0], a.lat, a.lng);
          if (d < nearestDist) {
            nearest = a;
            nearestDist = d;
          }
        }
        useTutorialStore.getState().setDemoActivityId(nearest.id);
        setTutorialStep('click_activity');
      } else {
        // No real activity nearby — skip the click-activity + open-popup steps,
        // go straight to the alert step which is the most valuable part of the tutorial.
        setTutorialStep('click_alert');
      }
    })();
  }, [activities, center, setTutorialStep]);

  // Advance tutorial when user taps a pin (popup appears)
  useEffect(() => {
    if (tutorialStep === 'click_activity' && selectedActivity) {
      setTutorialStep('open_popup');
    }
  }, [tutorialStep, selectedActivity, setTutorialStep]);

  // Delay the click_alert tooltip so it appears AFTER the activity screen transition finishes
  useEffect(() => {
    if (tutorialStep !== 'click_alert') {
      setShowAlertTooltip(false);
      return;
    }
    const timer = setTimeout(() => setShowAlertTooltip(true), 800);
    return () => clearTimeout(timer);
  }, [tutorialStep]);

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

  // Final step: user taps the map → wrap up the tutorial
  useEffect(() => {
    if (tutorialStep === 'create_activity_hint' && tappedPoint) {
      (async () => {
        await supabase.rpc('mark_tutorial_seen' as 'accept_tos');
        useTutorialStore.getState().setDemoActivityId(null);
        setTutorialStep('done');
      })();
    }
  }, [tutorialStep, tappedPoint, setTutorialStep]);

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.statusBar} />

      <View style={styles.content}>
        <CreateButton />
        <MapStyleButton />
        <FilterButton onPress={() => setShowFilters(true)} blink={tutorialStep === 'click_alert' && showAlertTooltip} />
        <RecenterButton onPress={() => { setFlyTarget(null); setFlyOffset(undefined); setFlyToKey((k) => k + 1); }} />

        <>

            <JuntoMapView
              center={center}
              activities={filtered}
              userLocation={currentLocation ?? center}
              tapMarker={tappedPoint && !selectedActivity ? [tappedPoint.lng, tappedPoint.lat] : null}
              tapMarkerContent={tappedPoint && !selectedActivity ? (
                <View style={styles.tapMarkerContent}>
                  <X size={22} color={colors.error} strokeWidth={3} />
                  <View style={styles.createTooltipInline}>
                    <Text style={styles.createTooltipTitle}>{t('map.createHere')}</Text>
                    <View style={styles.createTooltipRow}>
                      <Pressable
                        style={styles.createTooltipOption}
                        onPress={() => {
                          useCreateStore.getState().resetForm();
                          useCreateStore.getState().updateForm({ location_meeting: tappedPoint });
                          setTappedPoint(null);
                          router.push('/(auth)/create/step1');
                        }}
                      >
                        <View style={[styles.createTooltipDot, { backgroundColor: colors.pinMeeting }]} />
                        <Text style={styles.createTooltipOptionText}>{t('create.meetingPoint')}</Text>
                      </Pressable>
                      <Pressable
                        style={styles.createTooltipOption}
                        onPress={() => {
                          useCreateStore.getState().resetForm();
                          useCreateStore.getState().updateForm({ location_start: tappedPoint });
                          setTappedPoint(null);
                          router.push('/(auth)/create/step1');
                        }}
                      >
                        <View style={[styles.createTooltipDot, { backgroundColor: colors.pinStart }]} />
                        <Text style={styles.createTooltipOptionText}>{t('create.startPoint')}</Text>
                      </Pressable>
                      <Pressable
                        style={styles.createTooltipOption}
                        onPress={() => {
                          useCreateStore.getState().resetForm();
                          useCreateStore.getState().updateForm({ location_objective: tappedPoint });
                          setTappedPoint(null);
                          router.push('/(auth)/create/step1');
                        }}
                      >
                        <View style={[styles.createTooltipDot, { backgroundColor: colors.pinObjective }]} />
                        <Text style={styles.createTooltipOptionText}>{t('create.objectiveSet')}</Text>
                      </Pressable>
                    </View>
                  </View>
                </View>
              ) : undefined}
              flyTo={flyToKey > 0 ? { coordinate: flyTarget ?? center, key: flyToKey, offsetRatio: flyOffset } : null}
              selectedActivity={selectedActivity}
              popupContent={selectedActivity ? (
                <ActivityPopup
                  activity={selectedActivity}
                  onPress={() => {
                    suppressMapPressUntil.current = Date.now() + 400;
                    if (tutorialStep === 'open_popup') setTutorialStep('click_alert');
                    router.push(`/(auth)/activity/${selectedActivity.id}`);
                    setSelectedActivity(null);
                  }}
                />
              ) : undefined}
              onActivityPress={(a) => {
                setTappedPoint(null);
                if (selectedActivity?.id === a.id) {
                  // Second tap on the same pin → open the activity page
                  suppressMapPressUntil.current = Date.now() + 400;
                  if (tutorialStep === 'open_popup') setTutorialStep('click_alert');
                  router.push(`/(auth)/activity/${a.id}`);
                  setSelectedActivity(null);
                  selectionBoundsSpan.current = null;
                } else {
                  // Snapshot the viewport span so we can detect a later zoom-out
                  if (currentBounds.current) {
                    selectionBoundsSpan.current = Math.abs(currentBounds.current.neLng - currentBounds.current.swLng);
                  }
                  // First tap: fly to the pin (offset to land at ~40% horizontally)
                  setFlyTarget([a.lng, a.lat]);
                  setFlyOffset({ x: 0.1 });
                  setFlyToKey((k) => k + 1);
                  setSelectedActivity(a);
                }
              }}
              onMapPress={(lng, lat) => {
                if (Date.now() < suppressMapPressUntil.current) return;
                if (selectedActivity) {
                  const dLng = Math.abs(lng - selectedActivity.lng);
                  const dLat = Math.abs(lat - selectedActivity.lat);
                  const viewportSpan = currentBounds.current
                    ? Math.abs(currentBounds.current.neLng - currentBounds.current.swLng)
                    : 0.01;
                  if (dLng < viewportSpan * 0.05 && dLat < viewportSpan * 0.05) {
                    suppressMapPressUntil.current = Date.now() + 400;
                    if (tutorialStep === 'open_popup') setTutorialStep('click_alert');
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
          activities={clusterFilter ?? filtered}
          userLocation={currentLocation ?? center}
          filterLabel={clusterFilter ? t('map.activitiesAtPoint', { count: clusterFilter.length }) : undefined}
          onClearFilter={() => { setClusterFilter(null); clusterFilterAnchor.current = null; }}
          onCollapse={() => { setClusterFilter(null); clusterFilterAnchor.current = null; }}
          onItemPress={(a) => {
            setFlyTarget([a.lng, a.lat]);
            setFlyOffset({ x: 0.1 });
            setFlyToKey((k) => k + 1);
          }}
        />

        {tutorialStep === 'click_activity' && (
          <TutorialTooltip
            text={t('tutorial.clickActivity')}
            position="bottom"
            anchor={{ top: 100, left: 24, right: 24 }}
            onDismiss={() => {
              const demoId = useTutorialStore.getState().demoActivityId;
              const demo = filtered.find((a) => a.id === demoId);
              if (demo) {
                // Camera south of pin → pin renders in upper area of the screen, just below the tooltip
                setFlyTarget([demo.lng, demo.lat]);
                setFlyOffset({ y: -0.2 });
                setFlyToKey((k) => k + 1);
              }
            }}
          />
        )}
        {tutorialStep === 'open_popup' && (
          <TutorialTooltip
            text={t('tutorial.openPopup')}
            position="bottom"
            anchor={{ top: 100, left: 24, right: 24 }}
          />
        )}
        {tutorialStep === 'click_alert' && !selectedActivity && showAlertTooltip && (
          <TutorialTooltip
            text={t('tutorial.clickAlert')}
            position="bottom"
            anchor={{ bottom: 240, right: 8 }}
            arrowAlign="right"
          />
        )}
        {tutorialStep === 'create_activity_hint' && !tappedPoint && (
          <TutorialTooltip
            text={t('tutorial.createActivity')}
            position="bottom"
            anchor={{ bottom: 260, left: 24, right: 24 }}
          />
        )}

        <FilterSheet visible={showFilters} onClose={() => setShowFilters(false)} />
      </View>
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
  createTooltipInline: {
    alignItems: 'center',
    gap: spacing.sm,
  },
  createTooltipTitle: {
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
    overflow: 'hidden',
  },
  createTooltipRow: {
    flexDirection: 'row',
    gap: spacing.xs,
  },
  createTooltipOption: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
    elevation: 3,
    shadowColor: colors.background,
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
  },
  createTooltipDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
  createTooltipOptionText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
  statusBar: {
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
  },
});

