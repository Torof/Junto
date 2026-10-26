import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { useFocusEffect , useRouter } from 'expo-router';
import { useQueryClient } from '@tanstack/react-query';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { X, MapPin, Trophy } from 'lucide-react-native';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { ActivitySheet } from '@/components/activity-sheet';
import { ActivitiesBottomSheet, type ActivitiesBottomSheetHandle } from '@/components/activities-bottom-sheet';
import { FilterButton, EntityTypeToggles } from '@/components/filter-bar';
import { MapToast } from '@/components/map-toast';
import { showMapToast } from '@/store/map-toast-store';
import { MAP_FETCH_CAP } from '@/constants/map-query';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { CompassButton } from '@/components/compass-button';
import type { PlaceResult } from '@/services/geocode-service';
import { FilterSheet } from '@/components/filter-sheet';
import { CreateButton } from '@/components/create-button';
import { MapStyleButton } from '@/components/map-style-button';
import { RecenterButton } from '@/components/recenter-button';
import { askPermission } from '@/lib/permissions';
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
import { IntroOfferButton } from '@/components/intro-offer-button';
import { supabase } from '@/services/supabase';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

const BUFFER = 0.5; // 50% buffer around viewport
// Landing zoom after a place search — a valley-wide view (~20 km across), so
// the outings around the place show, not the place itself (Scott 2026-10-16).
const PLACE_ZOOM = 11;

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

// The « Découvrir askandgo » offer stands during the account's first week.
const INTRO_OFFER_DAYS = 7;

export default function CarteScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const { center, zoom: initialZoom, currentLocation, isLoading: locating } = useInitialLocation();
  // The map mounts with its first centre as `defaultSettings`: give the quick
  // location sources (stored fix, OS last fix) up to 400 ms to land so the
  // first frame is the region, not France (Scott 2026-10-26).
  const [mapGateOpen, setMapGateOpen] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setMapGateOpen(true), 400);
    return () => clearTimeout(t);
  }, []);
  const mapReady = !locating || mapGateOpen;
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  // Preview selection for pro / offering pins — first tap shows the
  // PinPreviewCard at the bottom of the screen; second tap on the
  // same pin (or anywhere on the preview card) opens the detail page.
  // Tap on the map elsewhere dismisses. Mutually exclusive with the
  // activity selection — picking one clears the other.
  // Drawer-list "peek" state — when the user taps a card, the matching
  // pin scales up and the card gets a CTA tint. Second tap on the
  // same card opens the detail page. Cards already carry the info the
  // tooltip would, so no popup fires for card taps.
  const [highlightedPinId, setHighlightedPinId] = useState<string | null>(null);
  const [showFilters, setShowFilters] = useState(false);
  // The list drawer is open above its 2% handle — hide the top-left filter /
  // map-style controls so the raised list reads as a clean layer.
  const [listOpen, setListOpen] = useState(false);
  const [flyToKey, setFlyToKey] = useState(0);
  const [heading, setHeading] = useState(0);
  const [resetBearingKey, setResetBearingKey] = useState(0);
  // The radius + activity search center on a chosen place if one was searched,
  // otherwise on my position (GPS, or IP fallback via useInitialLocation).
  const [searchPlace, setSearchPlace] = useState<PlaceResult | null>(null);
  const [flyTarget, setFlyTarget] = useState<[number, number] | null>(null);
  // « Me localiser » without the permission: ask (lib/permissions), then fly
  // as soon as the first fix lands.
  const [pendingLocate, setPendingLocate] = useState(false);
  useEffect(() => {
    if (!pendingLocate || !currentLocation) return;
    setPendingLocate(false);
    setFlyTarget(currentLocation);
    setFlyOffset(undefined);
    setFlyToKey((k) => k + 1);
  }, [pendingLocate, currentLocation]);
  const [flyOffset, setFlyOffset] = useState<{ x?: number; y?: number } | undefined>(undefined);
  const [flyZoom, setFlyZoom] = useState<number | undefined>(undefined);
  const [tappedPoint, setTappedPoint] = useState<{ lng: number; lat: number } | null>(null);
  const suppressMapPressUntil = useRef(0);
  const selectionBoundsSpan = useRef<number | null>(null);
  const introChecked = useRef(false);
  const [showIntro, setShowIntro] = useState(false);
  const replayRequested = useIntroStore((s) => s.replayRequested);
  const clearReplay = useIntroStore((s) => s.clearReplay);
  const offerVisible = useIntroStore((s) => s.offerVisible);
  const setOfferVisible = useIntroStore((s) => s.setOfferVisible);

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

  // A viewport fetch that hits the row cap is incomplete: say so once per
  // searched area so the user zooms in rather than trusting the field.
  const truncatedToastFor = useRef<string | null>(null);
  useEffect(() => {
    if (!searchBounds) return;
    const hit = (activities?.length ?? 0) >= MAP_FETCH_CAP
      || (pros?.length ?? 0) >= MAP_FETCH_CAP
      || (proOfferings?.length ?? 0) >= MAP_FETCH_CAP;
    const key = JSON.stringify(searchBounds);
    if (hit && truncatedToastFor.current !== key) {
      truncatedToastFor.current = key;
      showMapToast(t('map.toastTruncated'));
    }
  }, [activities, pros, proOfferings, searchBounds, t]);
  const searchCenter: [number, number] = searchPlace ? [searchPlace.lng, searchPlace.lat] : (currentLocation ?? center);
  const filtered = useFilteredActivities(activities ?? [], searchCenter);
  const filteredOfferings = useFilteredOfferings(proOfferings ?? [], searchCenter);
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
  // With a sport filter on, a storefront pin stays only when the pro offers
  // one of those sports (Scott 2026-10-16) — its offerings' sports travel
  // with the pin (NearbyPro.sport_keys).
  const sportKeys = useMapStore((s) => s.filters.sportKeys);
  const filteredProsByType = useMemo(() => {
    if (!showProOfferings) return [];
    const list = pros ?? [];
    if (sportKeys.length === 0) return list;
    return list.filter((p) => (p.sport_keys ?? []).some((k) => sportKeys.includes(k)));
  }, [pros, showProOfferings, sportKeys]);

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

  // The tour is OFFERED, never forced (Scott 2026-10-24): during the account's
  // first week, until it was opened or closed, a « Découvrir askandgo » pill
  // sits under the search bar and the menu shows « Découvrir l'app ».
  useEffect(() => {
    if (introChecked.current) return;
    introChecked.current = true;
    (async () => {
      const uid = (await supabase.auth.getUser()).data.user?.id;
      if (!uid) return;
      const { data: userRow } = await supabase
        .from('users')
        .select('tutorial_seen_at, created_at')
        .eq('id', uid)
        .single() as { data: { tutorial_seen_at: string | null; created_at: string } | null };
      if (!userRow || userRow.tutorial_seen_at) return;
      const ageMs = Date.now() - new Date(userRow.created_at).getTime();
      if (ageMs < INTRO_OFFER_DAYS * 24 * 60 * 60 * 1000) setOfferVisible(true);
    })();
  }, [setOfferVisible]);

  // Opened or closed, the tour counts as seen: the offer goes for good.
  const markIntroSeen = useCallback(async () => {
    setOfferVisible(false);
    // Must await (or .then) — supabase builders are lazy and don't fire
    // the request otherwise.
    try {
      await supabase.rpc('mark_tutorial_seen');
    } catch {
      // Non-fatal: worst case the offer shows again next launch.
    }
  }, [setOfferVisible]);

  const dismissIntro = useCallback(() => {
    setShowIntro(false);
    void markIntroSeen();
  }, [markIntroSeen]);

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
      // Statuses move server-side every minute (mig 00491): just refetch.
      void queryClient.invalidateQueries({ queryKey: ['activities'] });
    }, [queryClient])
  );

  // An activity pin tap opens its teaser drawer; pro and offering pins push
  // their full pages (2026-10-25), so only the activity has a preview state.
  const previewOpen = selectedActivity !== null;

  // Fly to a pin and land it in the upper part of the map (clear of the drawer
  // sliding up), same framing as a pin tap. Used by the cross-drawer links.
  // A searched PLACE is an area, not a point: it lands at PLACE_ZOOM to show
  // the outings around it, and dead centre — nothing slides up over it
  // (Scott 2026-10-16: « le zoom est beaucoup trop fort », then « le centre
  // arrive dans la partie supérieure »).
  const flyToPin = useCallback((coordinate: [number, number], opts?: { zoom?: number; centered?: boolean }) => {
    setFlyTarget(coordinate);
    setFlyOffset(opts?.centered ? undefined : { y: -0.28 });
    setFlyZoom(opts?.zoom);
    setFlyToKey((k) => k + 1);
  }, []);

  const clearPreview = useCallback(() => {
    setSelectedActivity(null);
  }, []);

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        {/* All floating controls hide while a pin preview is open, so the
            sheet reads as a clean temporary layer over the map. */}
        {!previewOpen && (
          <>
            <CreateButton />
            <RecenterButton onPress={async () => {
              if (!currentLocation) {
                if (await askPermission('location', 'locate')) setPendingLocate(true);
                return;
              }
              setFlyTarget(null); setFlyOffset(undefined); setFlyToKey((k) => k + 1);
            }} />
            <CompassButton heading={heading} onPress={() => setResetBearingKey((k) => k + 1)} />
          </>
        )}

        {/* Top-left controls row — filters chip + map style icon
            (Scott 2026-06-10). Sits at the left edge so the centered
            chip doesn't read as lonely and we stay clear of the
            Mapbox compass at top-right. Hidden while a preview is up OR the
            list drawer is raised, so the list reads as a clean layer. */}
        {!previewOpen && !listOpen && (
          <>
            {/* Place search (Photon) — fly to a typed place; activities around
                then load via the bounds search. */}
            <View style={[styles.searchArea, { top: insets.top + spacing.xs }]}>
              <PlaceSearchBar
                onSelect={(p) => { setSearchPlace(p); flyToPin([p.lng, p.lat], { zoom: PLACE_ZOOM, centered: true }); }}
                bias={{ lng: (currentLocation ?? center)[0], lat: (currentLocation ?? center)[1] }}
              />
            </View>
            <View style={[styles.topControls, { top: insets.top + spacing.xs + 52 }]}>
              <FilterButton onPress={() => setShowFilters(true)} />
              <MapStyleButton />
              <EntityTypeToggles />
            </View>
            {offerVisible && !showIntro && (
              <View style={[styles.introOffer, { top: insets.top + spacing.xs + 104 }]} pointerEvents="box-none">
                <IntroOfferButton onOpen={() => setShowIntro(true)} onClose={() => void markIntroSeen()} />
              </View>
            )}
          </>
        )}

        <>
            {mapReady && (
            <JuntoMapView
              center={center}
              zoom={initialZoom}
              activities={filteredActivitiesByType}
              pros={filteredProsByType}
              onProPress={(pro) => {
                // Guard the tap-through: a pin tap can also fire onMapPress,
                // which would clearPreview() and swallow the selection.
                suppressMapPressUntil.current = Date.now() + 400;
                setTappedPoint(null);
                setSelectedActivity(null);
                setHighlightedPinId(null);
                // The pro page is a full page now (2026-10-25): push it.
                router.push(`/(auth)/pro/${pro.user_id}`);
              }}
              proOfferings={filteredOfferingsByType}
              onProOfferingPress={(offering) => {
                suppressMapPressUntil.current = Date.now() + 400;
                setTappedPoint(null);
                setSelectedActivity(null);
                setHighlightedPinId(null);
                // The outing sheet is a full page now (2026-10-25): push it.
                router.push(`/(auth)/pro/offering/${offering.id}`);
              }}
              userLocation={currentLocation ?? center}
              radiusKm={radiusKm}
              radiusCenter={searchCenter}
              tapMarker={tappedPoint && !selectedActivity ? [tappedPoint.lng, tappedPoint.lat] : null}
              tapMarkerContent={tappedPoint && !selectedActivity ? (
                <View style={styles.tapMarkerContent}>
                  <X size={22} color={colors.error} strokeWidth={3} />
                  <View style={styles.createTooltipCard}>
                    <AppText style={styles.createTooltipHeader}>{t('map.createHere')}</AppText>
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
                      <AppText style={styles.createTooltipRowText}>{t('create.meetingPoint')}</AppText>
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
                      <AppText style={styles.createTooltipRowText}>{t('create.objectiveSet')}</AppText>
                    </Pressable>
                  </View>
                </View>
              ) : undefined}
              flyTo={flyToKey > 0 ? { coordinate: flyTarget ?? center, key: flyToKey, offsetRatio: flyOffset, zoom: flyZoom } : null}
              compassEnabled={false}
              onHeadingChange={setHeading}
              resetBearingKey={resetBearingKey}
              selectedActivity={selectedActivity}
              highlightedPinId={highlightedPinId}
              onActivityPress={(a) => {
                suppressMapPressUntil.current = Date.now() + 400;
                setTappedPoint(null);
                setHighlightedPinId(null);
                // Land the pin in the top third so it's clear of the
                // preview sheet that slides up from the bottom.
                setFlyTarget([a.lng, a.lat]);
                setFlyOffset({ y: -0.28 });
                setFlyToKey((k) => k + 1);
                setSelectedActivity(a);
              }}
              onMapPress={(lng, lat) => {
                if (Date.now() < suppressMapPressUntil.current) return;
                // Card-peek highlight dismisses on any map press.
                if (highlightedPinId) {
                  setHighlightedPinId(null);
                  return;
                }
                // Any open pin preview dismisses on a map press.
                if (selectedActivity) {
                  clearPreview();
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
            )}
        </>

        {/* One-line notices drawn on the map (toggle feedback). */}
        <MapToast />

        <ActivitiesBottomSheet
          ref={sheetRef}
          hidden={previewOpen}
          activities={clusterFilter ?? filteredActivitiesByType}
          proOfferings={filteredOfferingsByType}
          userLocation={currentLocation ?? center}
          highlightedItemId={highlightedPinId}
          filterLabel={clusterFilter ? t('map.activitiesAtPoint', { count: clusterFilter.length }) : undefined}
          onClearFilter={() => { setClusterFilter(null); clusterFilterAnchor.current = null; }}
          onCollapse={() => { setClusterFilter(null); clusterFilterAnchor.current = null; }}
          onOpenChange={setListOpen}
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
            setHighlightedPinId(o.id);
            setFlyTarget([o.lng, o.lat]);
            setFlyOffset({ y: -0.28 });
            setFlyToKey((k) => k + 1);
          }}
        />

        {/* UA teaser drawer — same always-mounted modal pattern as the others.
            The CTA clears the selection before pushing the page: the modal
            lives in the ROOT portal, so left open it would float over the
            pushed page. */}
        <ActivitySheet
          activity={selectedActivity}
          onClose={() => setSelectedActivity(null)}
          onOpen={(a) => {
            suppressMapPressUntil.current = Date.now() + 400;
            setSelectedActivity(null);
            router.push(`/(auth)/activity/${a.id}`);
          }}
        />

        {/* Always mounted (nullable userId) so the gorhom modal shell never
            unmounts — present()/dismiss() follow the selection. Conditionally
            mounting it corrupted native gesture state on reopen. */}


        <FilterSheet
          visible={showFilters}
          onClose={() => setShowFilters(false)}
          onPlaceSelect={(p) => { setSearchPlace(p); flyToPin([p.lng, p.lat], { zoom: PLACE_ZOOM, centered: true }); setShowFilters(false); }}
          onResetLocation={() => { setSearchPlace(null); flyToPin(currentLocation ?? center); setShowFilters(false); }}
          locationLabel={searchPlace?.label ?? null}
        />
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
  createTooltipRow: { borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card,
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
  content: {
    flex: 1,
  },
  introOffer: {
    position: 'absolute',
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  topControls: {
    position: 'absolute',
    left: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    zIndex: 10,
  },
  searchArea: {
    position: 'absolute',
    left: spacing.md,
    right: spacing.md,
    zIndex: 20,
  },
});

