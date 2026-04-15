import { useState, useCallback, useRef, useEffect } from 'react';
import { useFocusEffect } from 'expo-router';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { SafeAreaView } from 'react-native-safe-area-context';
import { X } from 'lucide-react-native';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivitiesBottomSheet } from '@/components/activities-bottom-sheet';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { CreateButton } from '@/components/create-button';
import { AlertButton } from '@/components/alert-button';
import { SearchAreaButton } from '@/components/search-area-button';
import { RecenterButton } from '@/components/recenter-button';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { type NearbyActivity } from '@/services/activity-service';
import { useCreateStore } from '@/store/create-store';
import { useTutorialStore } from '@/store/tutorial-store';
import { TutorialTooltip } from '@/components/tutorial-tooltip';
import { supabase } from '@/services/supabase';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';

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

function panDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dlat = lat2 - lat1;
  const dlng = lng2 - lng1;
  return Math.sqrt(dlat * dlat + dlng * dlng);
}

export default function CarteScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const { center } = useInitialLocation();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  const [showFilters, setShowFilters] = useState(false);
  const [flyToKey, setFlyToKey] = useState(0);
  const [flyTarget, setFlyTarget] = useState<[number, number] | null>(null);
  const [flyOffset, setFlyOffset] = useState<{ x?: number; y?: number } | undefined>(undefined);
  const [tappedPoint, setTappedPoint] = useState<{ lng: number; lat: number } | null>(null);
  const suppressMapPressUntil = useRef(0);
  const tutorialStep = useTutorialStore((s) => s.step);
  const setTutorialStep = useTutorialStore((s) => s.setStep);
  const tutorialChecked = useRef(false);
  const [showAlertTooltip, setShowAlertTooltip] = useState(false);

  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const [showSearchButton, setShowSearchButton] = useState(false);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);

  const { data: activities } = useNearbyActivities(searchBounds);
  const filtered = useFilteredActivities(activities ?? []);

  const doSearch = useCallback((bounds: MapBounds) => {
    lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
    setSearchBounds(addBuffer(bounds));
    setShowSearchButton(false);
  }, []);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;
    setTappedPoint(null);

    // First load — auto-search
    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      doSearch(bounds);
      return;
    }

    // If viewport extends beyond fetched bounds (zoom out) — auto-refetch silently
    if (searchBounds && !isWithinFetchedBounds(bounds, searchBounds)) {
      doSearch(bounds);
      return;
    }

    // If user panned significantly — show search button (don't auto-fetch)
    if (lastSearchCenter.current) {
      const viewportWidth = Math.abs(bounds.neLng - bounds.swLng);
      const dist = panDistance(
        lastSearchCenter.current.lat, lastSearchCenter.current.lng,
        bounds.centerLat, bounds.centerLng,
      );
      if (dist > viewportWidth * 0.3) {
        setShowSearchButton(true);
      }
    }
  }, [searchBounds, doSearch]);

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

      // Always call — idempotent: reuses existing demo nearby, else creates one
      const { data: demoId } = await supabase.rpc('seed_demo_activity' as 'join_activity', {
        p_lng: center[0],
        p_lat: center[1],
      } as unknown as { p_activity_id: string });
      if (demoId) useTutorialStore.getState().setDemoActivityId(demoId as unknown as string);
      if ((activities ?? []).length === 0 && currentBounds.current) {
        doSearch(currentBounds.current);
      }

      setTutorialStep('click_activity');
    })();
  }, [activities, center, doSearch, setTutorialStep]);

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
      void supabase.rpc('check_activity_transitions' as 'accept_tos');
    }, [])
  );

  // Final step: user taps the map → wrap up the tutorial
  useEffect(() => {
    if (tutorialStep === 'create_activity_hint' && tappedPoint) {
      (async () => {
        await supabase.rpc('mark_tutorial_seen' as 'accept_tos');
        const demoId = useTutorialStore.getState().demoActivityId;
        if (demoId) {
          await supabase.rpc('delete_demo_activity' as 'join_activity', {
            p_activity_id: demoId,
          } as unknown as { p_activity_id: string });
          useTutorialStore.getState().setDemoActivityId(null);
        }
        setTutorialStep('done');
      })();
    }
  }, [tutorialStep, tappedPoint, setTutorialStep]);

  const handleSearchArea = useCallback(() => {
    if (currentBounds.current) {
      doSearch(currentBounds.current);
    }
  }, [doSearch]);

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.statusBar} />

      <View style={styles.content}>
        <AlertButton blink={tutorialStep === 'click_alert' && showAlertTooltip} />
        <CreateButton />
        <FilterButton onPress={() => setShowFilters(true)} />
        <RecenterButton onPress={() => { setFlyTarget(null); setFlyOffset(undefined); setFlyToKey((k) => k + 1); }} />

        <>
            {showSearchButton && <SearchAreaButton onPress={handleSearchArea} />}

            <JuntoMapView
              center={center}
              activities={filtered}
              userLocation={center}
              tapMarker={tappedPoint && !selectedActivity ? [tappedPoint.lng, tappedPoint.lat] : null}
              tapMarkerContent={tappedPoint && !selectedActivity ? (
                <View style={styles.tapMarkerContent}>
                  <X size={22} color="#ef4444" strokeWidth={3} />
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
                        <View style={[styles.createTooltipDot, { backgroundColor: '#3b82f6' }]} />
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
                        <View style={[styles.createTooltipDot, { backgroundColor: '#22c55e' }]} />
                        <Text style={styles.createTooltipOptionText}>{t('create.startPoint')}</Text>
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
                } else {
                  // First tap: fly to the pin (offset to land at ~40% horizontally)
                  setFlyTarget([a.lng, a.lat]);
                  setFlyOffset({ x: 0.1 });
                  setFlyToKey((k) => k + 1);
                  setSelectedActivity(a);
                }
              }}
              onMapPress={(lng, lat) => {
                if (Date.now() < suppressMapPressUntil.current) return;
                if (selectedActivity) { setSelectedActivity(null); return; }
                setTappedPoint({ lng, lat });
              }}
              onBoundsChange={handleBoundsChange}
            />


        </>

        <ActivitiesBottomSheet
          activities={filtered}
          userLocation={center}
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

const styles = StyleSheet.create({
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
    backgroundColor: '#ffffff',
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
    elevation: 3,
    shadowColor: '#000',
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
    color: '#000000',
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
