import { useMemo } from 'react';
import { View, Pressable, StyleSheet, ScrollView } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Trash2 } from 'lucide-react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { TraceWaypoint, TraceWaypointKind } from '@/services/activity-service';
import { WAYPOINT_KINDS, WAYPOINT_NAME_MAX, cleanWaypointName, snapToLine, sortAlongTrace } from '@/utils/trace-waypoints';

// The stop being placed (index null) or edited on a trace.
export interface WaypointDraft { index: number | null; lng: number; lat: number; kind: TraceWaypointKind; name: string }

// Map-tap logic shared by the draw modal and the waypoints editor: a tap moves
// the open draft along the line, or starts a new stop snapped onto it.
export function draftFromTap(
  draft: WaypointDraft | null, lng: number, lat: number, coords: number[][],
): WaypointDraft | null {
  if (coords.length < 2) return draft;
  const at = snapToLine(lng, lat, coords);
  return draft ? { ...draft, ...at } : { index: null, ...at, kind: 'refuge', name: '' };
}

export function draftFromWaypoint(wps: TraceWaypoint[], index: number): WaypointDraft | null {
  const w = wps[index];
  return w ? { index, lng: w.lng, lat: w.lat, kind: w.kind, name: w.name ?? '' } : null;
}

// Applies the draft to the list (add or replace), in route order.
export function commitDraft(wps: TraceWaypoint[], draft: WaypointDraft, coords: number[][]): TraceWaypoint[] {
  const name = cleanWaypointName(draft.name);
  const wp: TraceWaypoint = name ? { lng: draft.lng, lat: draft.lat, kind: draft.kind, name } : { lng: draft.lng, lat: draft.lat, kind: draft.kind };
  const next = draft.index === null ? [...wps, wp] : wps.map((w, i) => (i === draft.index ? wp : w));
  return sortAlongTrace(next, coords);
}

// Kind chips + optional name + Supprimer / Annuler / Ajouter.
export function WaypointDraftPanel({ draft, onChange, onCommit, onRemove, onCancel }: {
  draft: WaypointDraft;
  onChange: (d: WaypointDraft) => void;
  onCommit: () => void;
  onRemove: () => void;
  onCancel: () => void;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();

  return (
    <View style={styles.wrap}>
      <AppText style={styles.title}>
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
              onPress={() => onChange({ ...draft, kind })}
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
        onChangeText={(name) => onChange({ ...draft, name })}
        placeholder={t('waypoint.namePlaceholder', { defaultValue: 'Nom (facultatif) — ex. Refuge des Bans' })}
        placeholderTextColor={colors.textMuted}
        maxLength={WAYPOINT_NAME_MAX}
      />
      <View style={styles.row}>
        {draft.index !== null ? (
          <Pressable style={styles.iconBtn} onPress={onRemove} accessibilityLabel={t('waypoint.remove', { defaultValue: 'Supprimer l’étape' })}>
            <Trash2 size={18} color={colors.error} strokeWidth={2.2} />
          </Pressable>
        ) : null}
        <Pressable style={[styles.btn, styles.btnGhost]} onPress={onCancel}>
          <AppText style={styles.btnGhostText}>{t('common.cancel', { defaultValue: 'Annuler' })}</AppText>
        </Pressable>
        <Pressable style={[styles.btn, styles.btnPrimary]} onPress={onCommit}>
          <AppText style={styles.btnPrimaryText}>
            {draft.index === null ? t('waypoint.add', { defaultValue: 'Ajouter' }) : t('common.save', { defaultValue: 'Enregistrer' })}
          </AppText>
        </Pressable>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrap: { gap: spacing.sm + 2 },
  title: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
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
