import { useState, useMemo, useCallback, useEffect, useRef } from 'react';
import { View, Pressable, Modal, StyleSheet, PanResponder } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import Svg, { Polyline } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { X, Undo2, Trash2, Pencil, Magnet, Waypoints, MapPinned } from 'lucide-react-native';
import Animated from 'react-native-reanimated';
import * as Burnt from 'burnt';
import { WaypointDraftPanel, commitDraft, draftFromTap, draftFromWaypoint, type WaypointDraft } from './waypoint-draft-panel';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';
import { MAX_WAYPOINTS, snapToLine, withWaypoints } from '@/utils/trace-waypoints';
import { JuntoMapView, type MapPin, type JuntoMapRef } from './map-view';
import { MapStyleButton } from './map-style-button';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { distanceMeters } from '@/utils/geo';
import { simplifyRDP, type Pt } from '@/utils/simplify-path';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { activityService, type GeoJsonLineString, type TraceWaypoint } from '@/services/activity-service';
import { snapTrailService } from '@/services/snap-trail-service';
import { fetchTraceElevations } from '@/utils/trace-elevation';

interface Props {
  visible: boolean;
  saving?: boolean;
  // When false, "Valider" attaches the trace straight away (no name step) —
  // used when drawing to attach to an activity rather than to the library.
  askName?: boolean;
  onClose: () => void;
  onSave: (name: string, geojson: GeoJsonLineString) => void;
}

// A chunk = one user action that appended coordinates to the trace:
//   - a tap in nav mode (anchor + the coords added since the previous anchor,
//     snapped to the trail or a straight [prev→here]);
//   - a freehand stroke (anchor null, the whole stroke's coords).
// The flat trace is just every chunk's coords concatenated. Undo pops the last
// chunk. Modelling it this way keeps snap, straight-line, freehand and undo all
// consistent.
interface Chunk {
  id: number;
  kind: 'tap' | 'stroke';
  anchor: [number, number] | null; // raw tapped point (routing input); null for strokes
  coords: [number, number][];       // coords this action contributes to the flat line
  snapped: boolean;
  pending: boolean;                  // snap request in flight
  fallback: boolean;                 // snap attempted but off-trail → kept straight
  // One altitude per coord (IGN), fetched once the chunk is settled; undefined
  // until then, null entries where IGN has no data. Lets the D+ show while
  // drawing and the saved trace leave already 3D (Scott 2026-10-16).
  ele?: (number | null)[];
}

// Reusable trace-drawing tool. Two modes: tap-to-place points (snapped onto the
// real trail via `snap-trail`, toggleable) or freehand drawing. Returns a GeoJSON
// LineString, same shape as an imported GPX.
export function TraceDrawModal({ visible, saving = false, askName = true, onClose, onSave }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const { center } = useInitialLocation();

  const [chunks, setChunks] = useState<Chunk[]>([]);
  const [snapEnabled, setSnapEnabled] = useState(true);
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState('');
  // « Étapes » mode (Scott 2026-11-02): stops placed on the line being drawn.
  const [wps, setWps] = useState<TraceWaypoint[]>([]);
  const [draft, setDraft] = useState<WaypointDraft | null>(null);
  const imePadding = useKeyboardDockPadding(insets.bottom + spacing.sm);

  const nextId = useRef(1);
  const chunksRef = useRef<Chunk[]>([]);
  useEffect(() => { chunksRef.current = chunks; }, [chunks]);

  // Reset whenever the modal is hidden so a reopen starts blank.
  useEffect(() => {
    if (!visible) {
      setChunks([]);
      setNaming(false);
      setName('');
      setSnapEnabled(true);
      setWps([]);
      setDraft(null);
    }
  }, [visible]);

  // Tap in nav mode → add a waypoint. With snap on, optimistically draw a
  // straight segment then replace it with the trail-following path when it
  // returns (or keep straight on off-trail / failure).
  const addPoint = useCallback((lng: number, lat: number) => {
    const p: [number, number] = [lng, lat];
    const prev = chunksRef.current;
    const id = nextId.current++;

    if (prev.length === 0) {
      setChunks((c) => [...c, { id, kind: 'tap', anchor: p, coords: [p], snapped: false, pending: false, fallback: false }]);
      return;
    }

    const from = prev[prev.length - 1]!.anchor ?? prev[prev.length - 1]!.coords.at(-1)!;
    setChunks((c) => [...c, {
      id, kind: 'tap', anchor: p, coords: [p], snapped: false, pending: snapEnabled, fallback: false,
    }]);
    if (!snapEnabled) return;

    void snapTrailService.snapSegment(from, p).then((res) => {
      setChunks((c) => c.map((ch) => {
        if (ch.id !== id) return ch;
        if (res.ok) {
          // Drop the routed segment's first point (≈ the previous anchor,
          // already in the line) to avoid a duplicate at the join.
          return { ...ch, coords: res.coordinates.slice(1), snapped: true, pending: false, fallback: false };
        }
        return { ...ch, pending: false, snapped: false, fallback: true };
      }));
    });
  }, [snapEnabled]);

  // Freehand mode: 'nav' = pan/zoom + tap-to-place (default); 'draw' = the map
  // is locked and the finger traces a line.
  // 'stops' = the trace is there, a tap on it places a stop (refuge, water…).
  const [mode, setMode] = useState<'nav' | 'draw' | 'stops'>('nav');
  const mapRef = useRef<JuntoMapRef>(null);
  const livePtsRef = useRef<Pt[]>([]);        // current stroke, in screen px
  const [, setLiveTick] = useState(0);         // forces re-render of the live SVG

  useEffect(() => { if (!visible) setMode('nav'); }, [visible]);

  // On stroke end: thin the finger path (RDP, px), convert screen→geo in ONE
  // batch (getCoordinateFromView is async), and append it as one stroke chunk.
  const commitStroke = useCallback(async () => {
    const raw = livePtsRef.current;
    livePtsRef.current = [];
    setLiveTick((tick) => tick + 1);
    const map = mapRef.current;
    if (raw.length < 2 || !map) return;
    const thinned = simplifyRDP(raw, 3);
    try {
      const converted = await Promise.all(thinned.map((p) => map.getCoordinateFromView([p.x, p.y])));
      const geo = converted
        .filter((c): c is number[] => Array.isArray(c) && typeof c[0] === 'number' && typeof c[1] === 'number')
        .map((c) => [c[0]!, c[1]!] as [number, number]);
      if (geo.length >= 2) {
        const id = nextId.current++;
        setChunks((c) => [...c, { id, kind: 'stroke', anchor: null, coords: geo, snapped: false, pending: false, fallback: false }]);
      }
    } catch {
      /* rare conversion failure — drop this stroke silently */
    }
  }, []);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: (e) => {
        livePtsRef.current = [{ x: e.nativeEvent.locationX, y: e.nativeEvent.locationY }];
        setLiveTick((tick) => tick + 1);
      },
      onPanResponderMove: (e) => {
        const { locationX: x, locationY: y } = e.nativeEvent;
        const last = livePtsRef.current[livePtsRef.current.length - 1];
        if (!last || Math.hypot(x - last.x, y - last.y) >= 2) {
          livePtsRef.current.push({ x, y });
          setLiveTick((tick) => tick + 1);
        }
      },
      onPanResponderRelease: () => { void commitStroke(); },
      onPanResponderTerminate: () => { void commitStroke(); },
    }),
  ).current;

  // Altitudes: once no snap is in flight, every settled chunk still without
  // `ele` is sent to IGN in ONE batched call (debounced so a burst of taps
  // costs one call), then split back per chunk. A chunk whose coords changed
  // meanwhile (snap returned) is a new object without `ele` → picked up next
  // round. Best effort: on failure the chunks stay 2D and D+ simply hides.
  // After one refusal (outside IGN coverage, quota, offline) stop asking for
  // this drawing session: every later tap would resend all 2D chunks and burn
  // the hourly point quota for nothing (counter-audit 2026-10, F2).
  const elevationOffRef = useRef(false);
  useEffect(() => { if (visible) elevationOffRef.current = false; }, [visible]);

  useEffect(() => {
    if (!visible) return;
    if (elevationOffRef.current) return;
    if (chunks.some((c) => c.pending)) return;
    const todo = chunks.filter((c) => !c.ele && c.coords.length > 0);
    if (todo.length === 0) return;
    const timer = setTimeout(() => {
      const batch = todo.map((c) => ({ id: c.id, coords: c.coords }));
      const flat = batch.flatMap((b) => b.coords);
      void fetchTraceElevations(flat).then((z) => {
        if (!z) { elevationOffRef.current = true; return; }
        let offset = 0;
        const perChunk = new Map<number, { coords: [number, number][]; ele: (number | null)[] }>();
        for (const b of batch) {
          perChunk.set(b.id, { coords: b.coords, ele: z.slice(offset, offset + b.coords.length) });
          offset += b.coords.length;
        }
        setChunks((cur) => cur.map((ch) => {
          const hit = perChunk.get(ch.id);
          // Only attach when the chunk's coords are still the ones we sent.
          return hit && hit.coords === ch.coords ? { ...ch, ele: hit.ele } : ch;
        }));
      });
    }, 500);
    return () => clearTimeout(timer);
  }, [chunks, visible]);

  // Flatten every chunk into the trace line (3D where altitudes are known).
  // Consecutive duplicate points at joins are dropped so the saved GeoJSON is
  // clean.
  const flatCoords = useMemo(() => {
    const out: number[][] = [];
    for (const ch of chunks) {
      ch.coords.forEach((c, i) => {
        const last = out[out.length - 1];
        if (last && last[0] === c[0] && last[1] === c[1]) return;
        const alt = ch.ele?.[i];
        out.push(typeof alt === 'number' ? [c[0], c[1], alt] : [c[0], c[1]]);
      });
    }
    return out;
  }, [chunks]);

  // No line left (undo / clear) → back to placing points.
  useEffect(() => { if (mode === 'stops' && flatCoords.length < 2) { setMode('nav'); setDraft(null); } }, [mode, flatCoords.length]);

  // D+ from the server (same derivation as the saved trace), refreshed when
  // the 3D line changes and at least 90 % of it carries altitudes.
  const [gainM, setGainM] = useState<number | null>(null);
  useEffect(() => {
    const n = flatCoords.length;
    const withZ = flatCoords.filter((c) => c.length > 2).length;
    if (n < 2 || withZ < Math.ceil(n * 0.9)) { setGainM(null); return; }
    let cancelled = false;
    const timer = setTimeout(() => {
      void activityService.computeTraceStats({ type: 'LineString', coordinates: flatCoords })
        .then((s) => { if (!cancelled) setGainM(s.elevation_gain_m); })
        .catch(() => { if (!cancelled) setGainM(null); });
    }, 300);
    return () => { cancelled = true; clearTimeout(timer); };
  }, [flatCoords]);

  const anchors = useMemo(
    () => chunks.filter((c) => c.anchor).map((c) => ({ id: c.id, coord: c.anchor! })),
    [chunks],
  );

  const distanceKm = useMemo(() => {
    let m = 0;
    for (let i = 1; i < flatCoords.length; i++) {
      const a = flatCoords[i - 1]!;
      const b = flatCoords[i]!;
      m += distanceMeters(a[1]!, a[0]!, b[1]!, b[0]!);
    }
    return m / 1000;
  }, [flatCoords]);

  const snapping = chunks.some((c) => c.pending);
  const fallbackCount = chunks.filter((c) => c.fallback).length;
  // Snap only applies to Points mode (freehand can't route) → show it "off" in draw mode.
  const snapVisualOn = snapEnabled && mode !== 'draw';

  const pins: MapPin[] = [
    ...(mode === 'stops' ? [] : anchors.map((a) => ({ id: `pt-${a.id}`, coordinate: a.coord, color: colors.cta }))),
    ...(draft ? [{ id: 'wp-draft', coordinate: [draft.lng, draft.lat] as [number, number], color: colors.mapAction }] : []),
  ];
  const routeLine = flatCoords.length >= 2 ? (flatCoords as [number, number][]) : undefined;
  const canSave = flatCoords.length >= 2 && !saving && !snapping;

  const undoLast = () => setChunks((prev) => prev.slice(0, -1));
  const clearAll = () => { setChunks([]); setWps([]); setDraft(null); };

  const onStopsTap = (lng: number, lat: number) => {
    if (!draft && wps.length >= MAX_WAYPOINTS) {
      Burnt.toast({ title: t('waypoint.max', { defaultValue: '{{count}} étapes maximum', count: MAX_WAYPOINTS }) });
      return;
    }
    setDraft(draftFromTap(draft, lng, lat, flatCoords));
  };

  // The line may have changed after the stops were placed (undo, more
  // points): every stop is snapped back onto the final line.
  const finalTrace = (): GeoJsonLineString => withWaypoints(
    { type: 'LineString', coordinates: flatCoords },
    wps.map((w) => ({ ...w, ...snapToLine(w.lng, w.lat, flatCoords) })),
  );

  const confirmSave = () => {
    const trimmed = name.trim();
    if (trimmed.length < 1 || saving || flatCoords.length < 2) return;
    onSave(trimmed, finalTrace());
  };

  return (
    <Modal visible={visible} animationType="slide" statusBarTranslucent onRequestClose={onClose}>
      <View style={styles.container}>
        <JuntoMapView
          center={center}
          pins={pins}
          routeLine={routeLine}
          waypoints={wps}
          onWaypointPress={mode === 'stops' ? (i) => setDraft(draftFromWaypoint(wps, i)) : undefined}
          onMapPress={mode === 'nav' ? addPoint : mode === 'stops' ? onStopsTap : undefined}
          surfaceView={false}
          mapViewRef={mapRef}
          scrollEnabled={mode !== 'draw'}
          zoomEnabled={mode !== 'draw'}
          rotateEnabled={mode !== 'draw'}
          pitchEnabled={mode !== 'draw'}
        />

        {mode === 'draw' && (
          <View style={styles.drawOverlay} {...panResponder.panHandlers}>
            <Svg style={StyleSheet.absoluteFill} pointerEvents="none">
              {livePtsRef.current.length >= 2 && (
                <Polyline
                  points={livePtsRef.current.map((p) => `${p.x},${p.y}`).join(' ')}
                  fill="none"
                  stroke={colors.cta}
                  strokeWidth={4}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                />
              )}
            </Svg>
          </View>
        )}

        <Pressable style={[styles.closeBtn, { top: insets.top + spacing.sm }]} onPress={onClose} hitSlop={8}>
          <X size={20} color={colors.textPrimary} strokeWidth={2.4} />
        </Pressable>
        <MapStyleButton scope="secondary" style={[styles.styleBtn, { top: insets.top + spacing.sm }]} />

        <View style={[styles.topBanner, { top: insets.top + spacing.sm + 44 }]} pointerEvents="none">
          <AppText style={styles.topBannerText}>
            {mode === 'draw'
              ? t('gpx.drawFreehandHint', { defaultValue: 'Trace au doigt · la carte est verrouillée' })
              : mode === 'stops'
                ? t('waypoint.drawHint', { defaultValue: 'Touche ta trace pour poser une étape · {{count}} étapes', count: wps.length })
              : anchors.length === 0
                ? t('gpx.drawHint', { defaultValue: 'Touche la carte pour poser des points' })
                : `${t('gpx.drawStats', { defaultValue: '{{n}} pts · {{km}} km', n: anchors.length, km: distanceKm.toFixed(1) })}`
                  + (gainM != null && gainM > 0 ? ` · D+ ${gainM} m` : '')
                  + (snapping ? ` · ${t('gpx.snapping', { defaultValue: 'snap…' })}` : '')
                  + (fallbackCount > 0 ? ` · ${t('gpx.offTrail', { defaultValue: '{{n}} hors sentier', n: fallbackCount, count: fallbackCount })}` : '')}
          </AppText>
        </View>

        {draft ? (
          <Animated.View style={[styles.stopPanel, imePadding]}>
            <WaypointDraftPanel
              draft={draft}
              onChange={setDraft}
              onCommit={() => { setWps(commitDraft(wps, draft, flatCoords)); setDraft(null); }}
              onRemove={() => { if (draft.index != null) setWps(wps.filter((_, i) => i !== draft.index)); setDraft(null); }}
              onCancel={() => setDraft(null)}
            />
          </Animated.View>
        ) : (
        <View style={[styles.toolbar, { bottom: insets.bottom + spacing.sm }]}>
          {/* Mode — segmented selector, active segment clearly filled so you
              always see which mode you're in (the old toggle showed the OTHER
              mode's label, which read backwards). */}
          <View style={styles.segmented}>
            <Pressable
              style={[styles.segment, styles.segmentFirst, mode === 'nav' && styles.segmentActive]}
              onPress={() => setMode('nav')}
            >
              <Waypoints size={17} color={mode === 'nav' ? '#FFFFFF' : colors.cta} strokeWidth={2.4} />
              <AppText style={[styles.segmentText, mode === 'nav' && styles.segmentTextActive]}>
                {t('gpx.modePoints', { defaultValue: 'Points' })}
              </AppText>
            </Pressable>
            <Pressable
              style={[styles.segment, mode === 'draw' && styles.segmentActive]}
              onPress={() => setMode('draw')}
            >
              <Pencil size={17} color={mode === 'draw' ? '#FFFFFF' : colors.cta} strokeWidth={2.4} />
              <AppText style={[styles.segmentText, mode === 'draw' && styles.segmentTextActive]}>
                {t('gpx.modeFreehand', { defaultValue: 'Main levée' })}
              </AppText>
            </Pressable>
            {/* Stops need a line to sit on. */}
            <Pressable
              style={[styles.segment, styles.segmentLast, mode === 'stops' && styles.segmentActive, flatCoords.length < 2 && styles.chipDisabled]}
              onPress={() => setMode('stops')}
              disabled={flatCoords.length < 2}
            >
              <MapPinned size={17} color={mode === 'stops' ? '#FFFFFF' : colors.cta} strokeWidth={2.4} />
              <AppText style={[styles.segmentText, mode === 'stops' && styles.segmentTextActive]}>
                {t('waypoint.modeStops', { defaultValue: 'Étapes' })}
              </AppText>
            </Pressable>
          </View>

          {/* One compact row: snap · undo · clear · validate. Snap only applies
              to Points mode → dims + disables in draw mode. */}
          <View style={styles.actionsRow}>
            <Pressable
              style={[styles.snapChip, snapVisualOn && styles.snapChipOn, mode === 'draw' && styles.chipDisabled]}
              onPress={() => setSnapEnabled((s) => !s)}
              disabled={mode === 'draw'}
              accessibilityLabel={t('gpx.snapLabel', { defaultValue: 'Coller au sentier' })}
            >
              <Magnet size={16} color={snapVisualOn ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.4} />
              <AppText style={[styles.snapChipText, snapVisualOn && styles.snapChipTextOn]}>
                {t('gpx.snapChip', { defaultValue: 'Sentier' })}
              </AppText>
            </Pressable>
            <Pressable
              style={[styles.iconBtn, chunks.length === 0 && styles.disabled]}
              disabled={chunks.length === 0}
              onPress={undoLast}
              accessibilityLabel={t('gpx.undo', { defaultValue: 'Annuler' })}
            >
              <Undo2 size={18} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
            <Pressable
              style={[styles.iconBtn, chunks.length === 0 && styles.disabled]}
              disabled={chunks.length === 0}
              onPress={clearAll}
              accessibilityLabel={t('gpx.clear', { defaultValue: 'Effacer' })}
            >
              <Trash2 size={18} color={colors.error} strokeWidth={2.2} />
            </Pressable>
            <Pressable
              style={[styles.saveBtn, !canSave && styles.saveDisabled]}
              disabled={!canSave}
              onPress={() => {
                if (askName) setNaming(true);
                else onSave('', finalTrace());
              }}
            >
              <AppText style={styles.saveText} numberOfLines={1}>
                {snapping
                  ? t('gpx.snappingWait', { defaultValue: 'Sentier…' })
                  : t('gpx.validate', { defaultValue: 'Valider' })}
              </AppText>
            </Pressable>
          </View>
        </View>
        )}

        {naming ? (
          <View style={styles.nameOverlay}>
            <View style={styles.nameCard}>
              <AppText style={styles.nameTitle}>{t('gpx.nameTitle', { defaultValue: 'Nom de la trace' })}</AppText>
              <AppTextInput
                style={styles.nameInput}
                value={name}
                onChangeText={setName}
                placeholder={t('gpx.namePlaceholder', { defaultValue: 'Ex. Boucle du lac' })}
                placeholderTextColor={colors.textMuted}
                maxLength={80}
                autoFocus
              />
              <View style={styles.nameActions}>
                <Pressable style={styles.nameCancel} onPress={() => setNaming(false)}>
                  <AppText style={styles.nameCancelText}>{t('common.cancel', { defaultValue: 'Annuler' })}</AppText>
                </Pressable>
                <Pressable
                  style={[styles.nameSave, (name.trim().length < 1 || saving) && styles.saveDisabled]}
                  disabled={name.trim().length < 1 || saving}
                  onPress={confirmSave}
                >
                  <AppText style={styles.nameSaveText}>
                    {saving ? t('gpx.saving', { defaultValue: 'Enregistrement…' }) : t('gpx.save', { defaultValue: 'Enregistrer' })}
                  </AppText>
                </Pressable>
              </View>
            </View>
          </View>
        ) : null}
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  drawOverlay: { ...StyleSheet.absoluteFillObject, zIndex: 5 },
  // Segmented mode selector — one glance shows the active mode.
  segmented: {
    flexDirection: 'row',
    borderRadius: radius.md,
    borderWidth: 1.5,
    borderColor: colors.cta,
    overflow: 'hidden',
  },
  segment: { borderWidth: 1, borderColor: colors.lineStrong,
    flex: 1,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    paddingVertical: spacing.sm,
    backgroundColor: colors.surfaceAlt,
  },
  segmentFirst: { borderRightWidth: 1.5, borderRightColor: colors.cta },
  segmentLast: { borderLeftWidth: 1.5, borderLeftColor: colors.cta },
  stopPanel: {
    position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 10,
    backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    paddingHorizontal: spacing.md, paddingTop: spacing.md,
    elevation: 8, shadowColor: '#000', shadowOpacity: 0.18, shadowRadius: 12, shadowOffset: { width: 0, height: -2 },
  },
  segmentActive: { backgroundColor: colors.cta },
  segmentText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '800' },
  segmentTextActive: { color: '#FFFFFF' },
  // Snap chip — compact, fills green when active.
  snapChip: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    paddingVertical: spacing.sm, paddingHorizontal: spacing.sm + 2,
    borderRadius: radius.md, borderWidth: 1, borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
  },
  snapChipOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  snapChipText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800' },
  snapChipTextOn: { color: '#FFFFFF' },
  chipDisabled: { opacity: 0.45 },
  iconBtn: {
    width: 42, height: 42, alignItems: 'center', justifyContent: 'center',
    borderRadius: radius.md, borderWidth: 1, borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
  },
  styleBtn: { position: 'absolute', right: 20, zIndex: 10 },
  closeBtn: {
    position: 'absolute', left: 20, width: 36, height: 36, borderRadius: radius.sm,
    backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center',
    zIndex: 10, borderWidth: 1, borderColor: colors.borderStrong,
  },
  topBanner: {
    position: 'absolute', alignSelf: 'center', zIndex: 10,
    backgroundColor: colors.background + 'F0', borderRadius: radius.full,
    paddingHorizontal: spacing.md, paddingVertical: spacing.xs,
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  topBannerText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  // Floating compact toolbar — sits over the map with margins + a soft shadow
  // so it reads as a light overlay, not a panel eating an eighth of the screen.
  toolbar: {
    position: 'absolute', left: spacing.md, right: spacing.md, zIndex: 10,
    padding: spacing.xs + 2, gap: spacing.xs + 2,
    borderRadius: radius.lg,
    backgroundColor: colors.background + 'F5',
    borderWidth: 1, borderColor: colors.borderMuted,
    elevation: 8,
    shadowColor: '#000', shadowOpacity: 0.18, shadowRadius: 12, shadowOffset: { width: 0, height: 4 },
  },
  actionsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 2 },
  disabled: { opacity: 0.4 },
  saveBtn: {
    flex: 1, height: 42,
    backgroundColor: colors.brand, borderRadius: radius.md,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.sm,
  },
  saveDisabled: { opacity: 0.5 },
  saveText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  nameOverlay: {
    ...StyleSheet.absoluteFillObject, zIndex: 20,
    backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  nameCard: {
    width: '100%', backgroundColor: colors.background, borderRadius: radius.lg,
    padding: spacing.lg, gap: spacing.md,
  },
  nameTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  nameInput: {
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    color: colors.textPrimary, fontSize: fontSizes.md, backgroundColor: colors.surface,
  },
  nameActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.sm },
  nameCancel: { paddingVertical: spacing.sm, paddingHorizontal: spacing.md },
  nameCancelText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '700' },
  nameSave: {
    backgroundColor: colors.brand, borderRadius: radius.md,
    paddingVertical: spacing.sm, paddingHorizontal: spacing.lg,
  },
  nameSaveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
