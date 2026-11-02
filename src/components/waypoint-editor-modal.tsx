import { useEffect, useMemo, useState } from 'react';
import { View, Pressable, Modal, StyleSheet, ScrollView } from 'react-native';
import Animated from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { X as XIcon, Trash2 } from 'lucide-react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { JuntoMapView } from '@/components/map-view';
import { useColors } from '@/hooks/use-theme';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { GeoJsonLineString, TraceWaypoint, TraceWaypointKind } from '@/services/activity-service';
import {
  MAX_WAYPOINTS, WAYPOINT_KINDS, WAYPOINT_NAME_MAX, cleanWaypointName, snapToLine, sortAlongTrace,
} from '@/utils/trace-waypoints';

interface Props {
  visible: boolean;
  trace: GeoJsonLineString | null;
  saving?: boolean;
  onClose: () => void;
  onSave: (waypoints: TraceWaypoint[]) => void;
}

// Waypoints editor (Scott 2026-11-02, option 2): the trace already exists —
// drawn or imported — and a tap on the map drops a stop on the nearest point
// of the line. Tap a stop to change or remove it.
export function WaypointEditorModal({ visible, trace, saving = false, onClose, onSave }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const imePadding = useKeyboardDockPadding(insets.bottom + spacing.md);

  const [wps, setWps] = useState<TraceWaypoint[]>([]);
  // The stop being placed or edited: a new point (index null) or an existing one.
  const [draft, setDraft] = useState<{ index: number | null; lng: number; lat: number; kind: TraceWaypointKind; name: string } | null>(null);

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

  const placeAt = (lng: number, lat: number) => {
    if (coords.length < 2) return;
    if (draft) { setDraft({ ...draft, ...snapToLine(lng, lat, coords) }); return; }
    if (wps.length >= MAX_WAYPOINTS) {
      Burnt.toast({ title: t('waypoint.max', { defaultValue: '30 étapes maximum', count: MAX_WAYPOINTS }) });
      return;
    }
    setDraft({ index: null, ...snapToLine(lng, lat, coords), kind: 'refuge', name: '' });
  };

  const editAt = (index: number) => {
    const w = wps[index];
    if (w) setDraft({ index, lng: w.lng, lat: w.lat, kind: w.kind, name: w.name ?? '' });
  };

  const commitDraft = () => {
    if (!draft) return;
    const name = cleanWaypointName(draft.name);
    const wp: TraceWaypoint = name ? { lng: draft.lng, lat: draft.lat, kind: draft.kind, name } : { lng: draft.lng, lat: draft.lat, kind: draft.kind };
    const next = draft.index === null ? [...wps, wp] : wps.map((w, i) => (i === draft.index ? wp : w));
    setWps(sortAlongTrace(next, coords));
    setDraft(null);
  };

  const removeDraft = () => {
    if (draft?.index != null) setWps(wps.filter((_, i) => i !== draft.index));
    setDraft(null);
  };

  return (
    <Modal visible={visible} animationType="slide" statusBarTranslucent onRequestClose={onClose}>
      <View style={styles.container}>
        <JuntoMapView
          center={center}
          zoom={zoom}
          routeLine={routeLine}
          waypoints={wps}
          onWaypointPress={editAt}
          pins={draft ? [{ id: 'wp-draft', coordinate: [draft.lng, draft.lat], color: colors.mapAction }] : []}
          onMapPress={placeAt}
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
            <>
              <AppText style={styles.panelTitle}>
                {draft.index === null
                  ? t('waypoint.newTitle', { defaultValue: 'Nouvelle étape' })
                  : t('waypoint.editTitle', { defaultValue: 'Modifier l’étape' })}
              </AppText>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.kinds} keyboardShouldPersistTaps="handled">
                {WAYPOINT_KINDS.map(({ kind, Icon }) => {
                  const on = draft.kind === kind;
                  return (
                    <Pressable
                      key={kind}
                      style={[styles.kind, on && { borderColor: colors.mapAction, backgroundColor: colors.mapAction + '1A' }]}
                      onPress={() => setDraft({ ...draft, kind })}
                      accessibilityState={{ selected: on }}
                    >
                      <Icon size={16} color={on ? colors.mapAction : colors.textSecondary} strokeWidth={2.2} />
                      <AppText style={[styles.kindText, on && { color: colors.mapAction }]}>{t(`waypoint.kind.${kind}`)}</AppText>
                    </Pressable>
                  );
                })}
              </ScrollView>
              <AppTextInput
                style={styles.input}
                value={draft.name}
                onChangeText={(name) => setDraft({ ...draft, name })}
                placeholder={t('waypoint.namePlaceholder', { defaultValue: 'Nom (facultatif) — ex. Refuge des Bans' })}
                placeholderTextColor={colors.textMuted}
                maxLength={WAYPOINT_NAME_MAX}
              />
              <View style={styles.row}>
                {draft.index !== null ? (
                  <Pressable style={styles.iconBtn} onPress={removeDraft} accessibilityLabel={t('waypoint.remove', { defaultValue: 'Supprimer l’étape' })}>
                    <Trash2 size={18} color={colors.error} strokeWidth={2.2} />
                  </Pressable>
                ) : null}
                <Pressable style={[styles.btn, styles.btnGhost]} onPress={() => setDraft(null)}>
                  <AppText style={styles.btnGhostText}>{t('common.cancel', { defaultValue: 'Annuler' })}</AppText>
                </Pressable>
                <Pressable style={[styles.btn, styles.btnPrimary]} onPress={commitDraft}>
                  <AppText style={styles.btnPrimaryText}>
                    {draft.index === null ? t('waypoint.add', { defaultValue: 'Ajouter' }) : t('common.save', { defaultValue: 'Enregistrer' })}
                  </AppText>
                </Pressable>
              </View>
            </>
          ) : (
            <View style={styles.row}>
              <AppText style={styles.count}>
                {t('waypoint.count', { defaultValue: '{{count}} étapes', count: wps.length })}
              </AppText>
              <Pressable style={[styles.btn, styles.btnPrimary, saving && { opacity: 0.6 }]} onPress={() => onSave(wps)} disabled={saving}>
                <AppText style={styles.btnPrimaryText}>{t('waypoint.done', { defaultValue: 'Valider les étapes' })}</AppText>
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
    paddingHorizontal: spacing.md, paddingTop: spacing.md, gap: spacing.sm + 2, ...shadows.card,
  },
  panelTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  kinds: { gap: spacing.sm, paddingRight: spacing.md },
  kind: {
    flexDirection: 'row', alignItems: 'center', gap: 6, borderWidth: 1, borderColor: colors.lineStrong,
    borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm,
  },
  kindText: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  input: {
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3, color: colors.textPrimary, fontSize: fontSizes.sm,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  count: { flex: 1, color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  btn: { borderRadius: radius.full, paddingVertical: spacing.sm + 3, paddingHorizontal: spacing.md, alignItems: 'center', justifyContent: 'center' },
  btnPrimary: { flex: 1, backgroundColor: colors.cta },
  btnPrimaryText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  btnGhost: { borderWidth: 1, borderColor: colors.lineStrong },
  btnGhostText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  iconBtn: {
    width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: colors.lineStrong,
  },
});
