import { useState, useMemo, useCallback, useEffect, useRef } from 'react';
import { View, Text, Pressable, Modal, TextInput, StyleSheet, PanResponder } from 'react-native';
import Svg, { Polyline } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { X, Undo2, Trash2, Pencil, Hand } from 'lucide-react-native';
import { JuntoMapView, type MapPin, type JuntoMapRef, type JuntoCameraRef } from './map-view';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { distanceMeters } from '@/utils/geo';
import { simplifyRDP, type Pt } from '@/utils/simplify-path';
import { useInitialLocation } from '@/hooks/use-initial-location';
import type { GeoJsonLineString } from '@/services/activity-service';

// Two-finger gesture bookkeeping: measured px→geo scale + accumulating camera
// state, so the overlay can drive the (locked) map's camera itself.
interface PanState {
  ready: boolean;
  startLngPerPx: number;
  startLatPerPx: number;
  centerLng: number;
  centerLat: number;
  startZoom: number;
  startDist: number;
  lastCx: number;
  lastCy: number;
}

function centroidOf(touches: readonly { locationX: number; locationY: number }[]) {
  const a = touches[0]!;
  const b = touches[1]!;
  return {
    cx: (a.locationX + b.locationX) / 2,
    cy: (a.locationY + b.locationY) / 2,
    dist: Math.hypot(a.locationX - b.locationX, a.locationY - b.locationY) || 1,
  };
}

interface Props {
  visible: boolean;
  saving?: boolean;
  // When false, "Valider" attaches the trace straight away (no name step) —
  // used when drawing to attach to an activity rather than to the library.
  askName?: boolean;
  onClose: () => void;
  onSave: (name: string, geojson: GeoJsonLineString) => void;
}

// Reusable trace-drawing tool: tap the map to drop points connected by straight
// segments (Junto is an organiser, not a precise-topo editor — no snap-to-trail).
// v1 = append + undo-last + clear; no mid-line editing. Returns a GeoJSON
// LineString, the same shape as an imported GPX. Used by the library now, and
// (Phase 2/3) activity creation + the activity map.
export function TraceDrawModal({ visible, saving = false, askName = true, onClose, onSave }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const { center } = useInitialLocation();

  const [points, setPoints] = useState<[number, number][]>([]);
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState('');

  // Reset whenever the modal is hidden so a reopen starts blank (the parent
  // closes on save success without calling our internal reset).
  useEffect(() => {
    if (!visible) {
      setPoints([]);
      setNaming(false);
      setName('');
    }
  }, [visible]);

  const addPoint = useCallback((lng: number, lat: number) => {
    setPoints((prev) => [...prev, [lng, lat]]);
  }, []);

  // Freehand mode: 'nav' = pan/zoom + tap-to-place (default); 'draw' = the map
  // is locked and the finger traces a line.
  const [mode, setMode] = useState<'nav' | 'draw'>('nav');
  const mapRef = useRef<JuntoMapRef>(null);
  const cameraRef = useRef<JuntoCameraRef>(null);
  const livePtsRef = useRef<Pt[]>([]);        // current stroke, in screen px
  const [, setLiveTick] = useState(0);         // forces re-render of the live SVG
  // One finger draws; two fingers drive the (locked) camera. Kind is latched at
  // gesture start and once a gesture involves 2 fingers it stays a map gesture.
  const gestureKindRef = useRef<'none' | 'draw' | 'map'>('none');
  const panRef = useRef<PanState | null>(null);

  useEffect(() => { if (!visible) setMode('nav'); }, [visible]);

  // On stroke end: thin the finger path (RDP, px) then convert only the kept
  // points screen→geo in ONE batch (getCoordinateFromView is async), and append
  // to the trace. Screen-space preview + deferred conversion = no drawing lag.
  const commitStroke = useCallback(async () => {
    const raw = livePtsRef.current;
    livePtsRef.current = [];
    setLiveTick((t) => t + 1);
    const map = mapRef.current;
    if (raw.length < 2 || !map) return;
    const thinned = simplifyRDP(raw, 3);
    try {
      const coords = await Promise.all(thinned.map((p) => map.getCoordinateFromView([p.x, p.y])));
      const geo = coords
        .filter((c): c is number[] => Array.isArray(c) && typeof c[0] === 'number' && typeof c[1] === 'number')
        .map((c) => [c[0]!, c[1]!] as [number, number]);
      if (geo.length >= 1) setPoints((prev) => [...prev, ...geo]);
    } catch {
      /* rare conversion failure — drop this stroke silently */
    }
  }, []);

  // Two-finger START: measure the map's real px→geo scale at the centroid (2
  // getCoordinateFromView probes) + read center/zoom, so subsequent moves can
  // pan/zoom the camera synchronously (no per-frame async).
  const startPan = useCallback(async (cx: number, cy: number, dist: number) => {
    const map = mapRef.current;
    if (!map) return;
    panRef.current = {
      ready: false, startLngPerPx: 0, startLatPerPx: 0,
      centerLng: 0, centerLat: 0, startZoom: 0, startDist: dist, lastCx: cx, lastCy: cy,
    };
    try {
      const [g0, gx, gy, center, zoom] = await Promise.all([
        map.getCoordinateFromView([cx, cy]),
        map.getCoordinateFromView([cx + 50, cy]),
        map.getCoordinateFromView([cx, cy + 50]),
        map.getCenter(),
        map.getZoom(),
      ]);
      const p = panRef.current;
      if (!p) return;
      p.startLngPerPx = (gx[0]! - g0[0]!) / 50;
      p.startLatPerPx = (gy[1]! - g0[1]!) / 50; // negative (screen y grows downward)
      p.centerLng = center[0]!;
      p.centerLat = center[1]!;
      p.startZoom = zoom;
      p.ready = true;
    } catch {
      panRef.current = null; // measurement failed → skip pan this gesture
    }
  }, []);

  // Two-finger MOVE (sync): apply centroid translation (pan) + pinch ratio (zoom).
  const applyPan = useCallback((cx: number, cy: number, dist: number) => {
    const p = panRef.current;
    const cam = cameraRef.current;
    if (!p || !p.ready || !cam) return;
    const ratio = dist / p.startDist;
    const lngPerPx = p.startLngPerPx / ratio;
    const latPerPx = p.startLatPerPx / ratio;
    p.centerLng -= (cx - p.lastCx) * lngPerPx;
    p.centerLat -= (cy - p.lastCy) * latPerPx;
    p.lastCx = cx;
    p.lastCy = cy;
    cam.setCamera({
      centerCoordinate: [p.centerLng, p.centerLat],
      zoomLevel: p.startZoom + Math.log2(ratio),
      animationDuration: 0,
    });
  }, []);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: (e) => {
        const touches = e.nativeEvent.touches;
        if (touches.length >= 2) {
          gestureKindRef.current = 'map';
          const { cx, cy, dist } = centroidOf(touches);
          void startPan(cx, cy, dist);
        } else {
          gestureKindRef.current = 'draw';
          livePtsRef.current = [{ x: e.nativeEvent.locationX, y: e.nativeEvent.locationY }];
          setLiveTick((t) => t + 1);
        }
      },
      onPanResponderMove: (e) => {
        const touches = e.nativeEvent.touches;
        if (touches.length >= 2) {
          const { cx, cy, dist } = centroidOf(touches);
          if (gestureKindRef.current !== 'map') {
            // a 1-finger stroke just gained a 2nd finger → drop it, become a map gesture
            gestureKindRef.current = 'map';
            livePtsRef.current = [];
            setLiveTick((t) => t + 1);
            void startPan(cx, cy, dist);
          } else {
            applyPan(cx, cy, dist);
          }
          return;
        }
        if (gestureKindRef.current !== 'draw') return; // one finger after a pinch → ignore
        const { locationX: x, locationY: y } = e.nativeEvent;
        const last = livePtsRef.current[livePtsRef.current.length - 1];
        if (!last || Math.hypot(x - last.x, y - last.y) >= 2) {
          livePtsRef.current.push({ x, y });
          setLiveTick((t) => t + 1);
        }
      },
      onPanResponderRelease: () => {
        if (gestureKindRef.current === 'draw') void commitStroke();
        gestureKindRef.current = 'none';
        panRef.current = null;
      },
      onPanResponderTerminate: () => {
        if (gestureKindRef.current === 'draw') void commitStroke();
        gestureKindRef.current = 'none';
        panRef.current = null;
      },
    }),
  ).current;

  const distanceKm = useMemo(() => {
    let m = 0;
    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1]!;
      const b = points[i]!;
      m += distanceMeters(a[1], a[0], b[1], b[0]);
    }
    return m / 1000;
  }, [points]);

  const pins: MapPin[] = points.map((p, i) => ({ id: `pt-${i}`, coordinate: p, color: colors.cta }));
  const routeLine = points.length >= 2 ? points : undefined;
  const canSave = points.length >= 2 && !saving;

  const confirmSave = () => {
    const trimmed = name.trim();
    if (trimmed.length < 1 || saving) return;
    onSave(trimmed, { type: 'LineString', coordinates: points });
  };

  return (
    <Modal visible={visible} animationType="slide" statusBarTranslucent onRequestClose={onClose}>
      <View style={styles.container}>
        <JuntoMapView
          center={center}
          pins={pins}
          routeLine={routeLine}
          onMapPress={mode === 'nav' ? addPoint : undefined}
          surfaceView={false}
          mapViewRef={mapRef}
          mapCameraRef={cameraRef}
          scrollEnabled={mode === 'nav'}
          zoomEnabled={mode === 'nav'}
          rotateEnabled={mode === 'nav'}
          pitchEnabled={mode === 'nav'}
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

        <View style={[styles.topBanner, { top: insets.top + spacing.sm }]} pointerEvents="none">
          <Text style={styles.topBannerText}>
            {mode === 'draw'
              ? t('gpx.drawFreehandHint', { defaultValue: '1 doigt pour tracer · 2 doigts pour bouger la carte' })
              : points.length === 0
                ? t('gpx.drawHint', { defaultValue: 'Touche la carte pour poser des points' })
                : t('gpx.drawStats', { defaultValue: '{{n}} pts · {{km}} km', n: points.length, km: distanceKm.toFixed(1) })}
          </Text>
        </View>

        <View style={[styles.bottomBar, { paddingBottom: insets.bottom + spacing.md }]}>
          <Pressable
            style={[styles.modeBtn, mode === 'draw' && styles.modeBtnActive]}
            onPress={() => setMode((m) => (m === 'nav' ? 'draw' : 'nav'))}
          >
            {mode === 'nav'
              ? <Pencil size={18} color={colors.cta} strokeWidth={2.4} />
              : <Hand size={18} color="#FFFFFF" strokeWidth={2.4} />}
            <Text style={[styles.modeBtnText, mode === 'draw' && styles.modeBtnTextActive]}>
              {mode === 'nav'
                ? t('gpx.drawFreehand', { defaultValue: 'Dessiner à main levée' })
                : t('gpx.drawNavigate', { defaultValue: 'Naviguer · placer des points' })}
            </Text>
          </Pressable>
          <View style={styles.actionsRow}>
            <Pressable
              style={[styles.secondaryBtn, points.length === 0 && styles.disabled]}
              disabled={points.length === 0}
              onPress={() => setPoints((prev) => prev.slice(0, -1))}
            >
              <Undo2 size={18} color={colors.textPrimary} strokeWidth={2.2} />
              <Text style={styles.secondaryText}>{t('gpx.undo', { defaultValue: 'Annuler le point' })}</Text>
            </Pressable>
            <Pressable
              style={[styles.secondaryBtn, points.length === 0 && styles.disabled]}
              disabled={points.length === 0}
              onPress={() => setPoints([])}
            >
              <Trash2 size={18} color={colors.error} strokeWidth={2.2} />
              <Text style={[styles.secondaryText, { color: colors.error }]}>{t('gpx.clear', { defaultValue: 'Effacer' })}</Text>
            </Pressable>
          </View>
          <Pressable
            style={[styles.saveBtn, !canSave && styles.saveDisabled]}
            disabled={!canSave}
            onPress={() => {
              if (askName) setNaming(true);
              else onSave('', { type: 'LineString', coordinates: points });
            }}
          >
            <Text style={styles.saveText}>{t('gpx.validate', { defaultValue: 'Valider la trace' })}</Text>
          </Pressable>
        </View>

        {naming ? (
          <View style={styles.nameOverlay}>
            <View style={styles.nameCard}>
              <Text style={styles.nameTitle}>{t('gpx.nameTitle', { defaultValue: 'Nom de la trace' })}</Text>
              <TextInput
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
                  <Text style={styles.nameCancelText}>{t('common.cancel', { defaultValue: 'Annuler' })}</Text>
                </Pressable>
                <Pressable
                  style={[styles.nameSave, (name.trim().length < 1 || saving) && styles.saveDisabled]}
                  disabled={name.trim().length < 1 || saving}
                  onPress={confirmSave}
                >
                  <Text style={styles.nameSaveText}>
                    {saving ? t('gpx.saving', { defaultValue: 'Enregistrement…' }) : t('gpx.save', { defaultValue: 'Enregistrer' })}
                  </Text>
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
  modeBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    paddingVertical: spacing.sm, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.cta, backgroundColor: colors.surface,
  },
  modeBtnActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  modeBtnText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '800' },
  modeBtnTextActive: { color: '#FFFFFF' },
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
  bottomBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 10,
    paddingHorizontal: spacing.md, paddingTop: spacing.md, gap: spacing.sm,
    backgroundColor: colors.background + 'F5',
    borderTopWidth: 1, borderTopColor: colors.borderMuted,
  },
  actionsRow: { flexDirection: 'row', gap: spacing.sm },
  secondaryBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    paddingVertical: spacing.sm, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.borderMuted, backgroundColor: colors.surface,
  },
  secondaryText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  disabled: { opacity: 0.4 },
  saveBtn: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.sm + 2, alignItems: 'center',
  },
  saveDisabled: { opacity: 0.5 },
  saveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
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
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.sm, paddingHorizontal: spacing.lg,
  },
  nameSaveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
