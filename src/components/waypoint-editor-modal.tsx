import { useEffect, useMemo, useState } from 'react';
import { View, Pressable, Modal, StyleSheet } from 'react-native';
import Animated from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { X as XIcon } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { JuntoMapView } from '@/components/map-view';
import { WaypointDraftPanel, commitDraft, draftFromTap, draftFromWaypoint, type WaypointDraft } from '@/components/waypoint-draft-panel';
import { useColors } from '@/hooks/use-theme';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { GeoJsonLineString, TraceWaypoint } from '@/services/activity-service';
import { MAX_WAYPOINTS } from '@/utils/trace-waypoints';

interface Props {
  visible: boolean;
  trace: GeoJsonLineString | null;
  saving?: boolean;
  onClose: () => void;
  onSave: (waypoints: TraceWaypoint[]) => void;
}

// Waypoints editor for an EXISTING trace (Scott 2026-11-02, option 2): an
// imported or saved trace — a tap drops a stop on the nearest point of the
// line; tap a stop to change or remove it. A trace being drawn has the same
// tool as its « Étapes » mode (trace-draw-modal).
export function WaypointEditorModal({ visible, trace, saving = false, onClose, onSave }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const imePadding = useKeyboardDockPadding(insets.bottom + spacing.md);

  const [wps, setWps] = useState<TraceWaypoint[]>([]);
  const [draft, setDraft] = useState<WaypointDraft | null>(null);

  useEffect(() => {
    if (visible) { setWps(trace?.waypoints ?? []); setDraft(null); }
  }, [visible, trace]);

  const coords = useMemo(() => trace?.coordinates ?? [], [trace]);
  const routeLine = useMemo(() => coords.map((c) => [c[0]!, c[1]!] as [number, number]), [coords]);
  const center = useMemo<[number, number]>(() => {
    if (coords.length === 0) return [6.6, 44.9];
    const lngs = coords.map((c) => c[0]!);
    const lats = coords.map((c) => c[1]!);
    return [(Math.min(...lngs) + Math.max(...lngs)) / 2, (Math.min(...lats) + Math.max(...lats)) / 2];
  }, [coords]);
  const zoom = useMemo(() => {
    if (coords.length === 0) return 12;
    const spread = Math.max(
      Math.max(...coords.map((c) => c[0]!)) - Math.min(...coords.map((c) => c[0]!)),
      Math.max(...coords.map((c) => c[1]!)) - Math.min(...coords.map((c) => c[1]!)),
    );
    return spread > 0.3 ? 9 : spread > 0.1 ? 10 : spread > 0.03 ? 12 : 13;
  }, [coords]);

  const onMapTap = (lng: number, lat: number) => {
    if (!draft && wps.length >= MAX_WAYPOINTS) {
      Burnt.toast({ title: t('waypoint.max', { defaultValue: '{{count}} étapes maximum', count: MAX_WAYPOINTS }) });
      return;
    }
    setDraft(draftFromTap(draft, lng, lat, coords));
  };

  return (
    <Modal visible={visible} animationType="slide" statusBarTranslucent onRequestClose={onClose}>
      <View style={styles.container}>
        <JuntoMapView
          center={center}
          zoom={zoom}
          routeLine={routeLine}
          waypoints={wps}
          onWaypointPress={(i) => setDraft(draftFromWaypoint(wps, i))}
          pins={draft ? [{ id: 'wp-draft', coordinate: [draft.lng, draft.lat], color: colors.mapAction }] : []}
          onMapPress={onMapTap}
          surfaceView={false}
        />

        <View style={[styles.topBar, { top: insets.top + spacing.sm }]}>
          <Pressable style={styles.closeBtn} onPress={onClose} hitSlop={8} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
            <XIcon size={18} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>
          <View style={styles.topTitle}>
            <AppText style={styles.topTitleText}>{t('waypoint.title', { defaultValue: 'Étapes du parcours' })}</AppText>
            <AppText style={styles.topHint} numberOfLines={2}>
              {draft
                ? t('waypoint.hintMove', { defaultValue: 'Touche la carte pour déplacer l’étape sur la trace.' })
                : t('waypoint.hintAdd', { defaultValue: 'Touche la trace pour ajouter une étape. Touche une étape pour la modifier.' })}
            </AppText>
          </View>
        </View>

        <Animated.View style={[styles.panel, imePadding]}>
          {draft ? (
            <WaypointDraftPanel
              draft={draft}
              onChange={setDraft}
              onCommit={() => { setWps(commitDraft(wps, draft, coords)); setDraft(null); }}
              onRemove={() => { if (draft.index != null) setWps(wps.filter((_, i) => i !== draft.index)); setDraft(null); }}
              onCancel={() => setDraft(null)}
            />
          ) : (
            <View style={styles.row}>
              <AppText style={styles.count}>
                {t('waypoint.count', { defaultValue: '{{count}} étapes', count: wps.length })}
              </AppText>
              <Pressable style={[styles.doneBtn, saving && { opacity: 0.6 }]} onPress={() => onSave(wps)} disabled={saving}>
                <AppText style={styles.doneText}>{t('waypoint.done', { defaultValue: 'Valider les étapes' })}</AppText>
              </Pressable>
            </View>
          )}
        </Animated.View>
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  topBar: { position: 'absolute', left: spacing.md, right: spacing.md, flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
  closeBtn: {
    width: 36, height: 36, borderRadius: radius.sm, backgroundColor: colors.background,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.borderStrong,
  },
  topTitle: {
    flex: 1, backgroundColor: colors.background + 'F2', borderRadius: radius.lg,
    paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm, ...shadows.card,
  },
  topTitleText: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  topHint: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 2 },
  panel: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    paddingHorizontal: spacing.md, paddingTop: spacing.md, ...shadows.card,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  count: { flex: 1, color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  doneBtn: {
    flex: 1, backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.sm + 3, alignItems: 'center', justifyContent: 'center',
  },
  doneText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
});
