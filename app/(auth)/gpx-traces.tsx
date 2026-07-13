import { useState, useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView, Alert, TextInput, Modal, ActivityIndicator } from 'react-native';
import { Stack } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Plus, Share2, Pencil, Trash2, Route as RouteIcon, X } from 'lucide-react-native';
import * as Sharing from 'expo-sharing';
import { File, Paths } from 'expo-file-system';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { JuntoMapView } from '@/components/map-view';
import { TraceDrawModal } from '@/components/trace-draw-modal';
import { TraceShareSheet } from '@/components/trace-share-sheet';
import { useGpxTraces, useCreateGpxTrace, useRenameGpxTrace, useDeleteGpxTrace } from '@/hooks/use-gpx-traces';
import type { GpxTrace } from '@/services/gpx-trace-service';
import { geoJsonLineStringToGpx } from '@/utils/geojson-to-gpx';
import { getFriendlyError } from '@/utils/friendly-error';

export default function GpxTracesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();

  const { data: traces, isLoading } = useGpxTraces();
  const createMutation = useCreateGpxTrace();
  const renameMutation = useRenameGpxTrace();
  const deleteMutation = useDeleteGpxTrace();

  const [drawOpen, setDrawOpen] = useState(false);
  const [preview, setPreview] = useState<GpxTrace | null>(null);
  const [renaming, setRenaming] = useState<{ id: string; name: string } | null>(null);
  const [shareOpen, setShareOpen] = useState(false);
  const shareTraceRef = useRef<GpxTrace | null>(null);

  const handleSaveNew = (name: string, geojson: GpxTrace['geojson']) => {
    createMutation.mutate(
      { name, geojson },
      {
        onSuccess: () => setDrawOpen(false),
        onError: (e) => Alert.alert(getFriendlyError(e)),
      },
    );
  };

  const handleNativeShare = async (trace: GpxTrace) => {
    try {
      const gpxXml = geoJsonLineStringToGpx(trace.geojson, trace.name);
      const safeName = trace.name.replace(/[^a-zA-Z0-9._-]/g, '_').replace(/\.gpx$/i, '') + '.gpx';
      const tmp = new File(Paths.cache, safeName);
      tmp.create({ overwrite: true });
      tmp.write(gpxXml);
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(tmp.uri, {
          mimeType: 'application/gpx+xml',
          dialogTitle: trace.name,
          UTI: 'com.topografix.gpx',
        });
      }
    } catch {
      Alert.alert(t('gpx.shareError', { defaultValue: 'Impossible de partager la trace.' }));
    }
  };

  const handleDelete = (trace: GpxTrace) => {
    Alert.alert(
      t('gpx.deleteTitle', { defaultValue: 'Supprimer la trace ?' }),
      t('gpx.deleteMessage', { defaultValue: '« {{name}} » sera définitivement supprimée.', name: trace.name }),
      [
        { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
        {
          text: t('gpx.delete', { defaultValue: 'Supprimer' }),
          style: 'destructive',
          onPress: () => deleteMutation.mutate(trace.id, { onError: (e) => Alert.alert(getFriendlyError(e)) }),
        },
      ],
    );
  };

  const submitRename = () => {
    if (!renaming || renaming.name.trim().length < 1) return;
    renameMutation.mutate(
      { id: renaming.id, name: renaming.name.trim() },
      { onSuccess: () => setRenaming(null), onError: (e) => Alert.alert(getFriendlyError(e)) },
    );
  };

  const list = traces ?? [];

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ headerTitle: t('gpx.title', { defaultValue: 'Mes traces GPX' }) }} />

      <ScrollView contentContainerStyle={[styles.scroll, { paddingBottom: insets.bottom + 96 }]}>
        <Text style={styles.subtitle}>
          {t('gpx.subtitle', { defaultValue: 'Dessine tes itinéraires et réutilise-les sur tes sorties.' })}
        </Text>

        {isLoading ? (
          <ActivityIndicator color={colors.cta} style={{ marginTop: spacing.xl }} />
        ) : list.length === 0 ? (
          <View style={styles.empty}>
            <RouteIcon size={40} color={colors.textMuted} strokeWidth={1.6} />
            <Text style={styles.emptyText}>
              {t('gpx.empty', { defaultValue: 'Aucune trace pour le moment. Crée ta première trace !' })}
            </Text>
          </View>
        ) : (
          list.map((trace) => (
            <View key={trace.id} style={styles.row}>
              <Pressable style={styles.rowMain} onPress={() => setPreview(trace)}>
                <View style={styles.rowIcon}>
                  <RouteIcon size={20} color={colors.cta} strokeWidth={2.2} />
                </View>
                <View style={styles.rowInfo}>
                  <Text style={styles.rowName} numberOfLines={1}>{trace.name}</Text>
                  <Text style={styles.rowMeta}>
                    {Number(trace.distance_km).toFixed(1)} km · {dayjs(trace.created_at).locale('fr').format('D MMM YYYY')}
                  </Text>
                </View>
              </Pressable>
              <View style={styles.rowActions}>
                <Pressable style={styles.actionBtn} hitSlop={6} onPress={() => { shareTraceRef.current = trace; setShareOpen(true); }}>
                  <Share2 size={18} color={colors.textSecondary} strokeWidth={2.2} />
                </Pressable>
                <Pressable style={styles.actionBtn} hitSlop={6} onPress={() => setRenaming({ id: trace.id, name: trace.name })}>
                  <Pencil size={18} color={colors.textSecondary} strokeWidth={2.2} />
                </Pressable>
                <Pressable style={styles.actionBtn} hitSlop={6} onPress={() => handleDelete(trace)}>
                  <Trash2 size={18} color={colors.error} strokeWidth={2.2} />
                </Pressable>
              </View>
            </View>
          ))
        )}
      </ScrollView>

      <Pressable
        style={[styles.fab, { bottom: insets.bottom + spacing.lg }]}
        onPress={() => setDrawOpen(true)}
      >
        <Plus size={20} color="#FFFFFF" strokeWidth={2.6} />
        <Text style={styles.fabText}>{t('gpx.create', { defaultValue: 'Créer une trace' })}</Text>
      </Pressable>

      <TraceDrawModal
        visible={drawOpen}
        saving={createMutation.isPending}
        onClose={() => setDrawOpen(false)}
        onSave={handleSaveNew}
      />

      <TraceShareSheet
        visible={shareOpen}
        geojson={shareTraceRef.current?.geojson ?? null}
        name={shareTraceRef.current?.name ?? ''}
        onClose={() => setShareOpen(false)}
        onExternalShare={() => { if (shareTraceRef.current) handleNativeShare(shareTraceRef.current); }}
      />

      {/* Read-only preview */}
      <Modal visible={preview !== null} animationType="slide" statusBarTranslucent onRequestClose={() => setPreview(null)}>
        <View style={styles.previewContainer}>
          {preview ? (
            <JuntoMapView
              center={midpoint(preview.geojson.coordinates)}
              zoom={11}
              routeLine={preview.geojson.coordinates as [number, number][]}
              surfaceView={false}
            />
          ) : null}
          <Pressable style={[styles.closeBtn, { top: insets.top + spacing.sm }]} onPress={() => setPreview(null)} hitSlop={8}>
            <X size={20} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>
          {preview ? (
            <View style={[styles.previewBanner, { top: insets.top + spacing.sm }]} pointerEvents="none">
              <Text style={styles.previewName} numberOfLines={1}>{preview.name}</Text>
              <Text style={styles.previewMeta}>{Number(preview.distance_km).toFixed(1)} km</Text>
            </View>
          ) : null}
        </View>
      </Modal>

      {/* Rename */}
      <Modal visible={renaming !== null} transparent animationType="fade" onRequestClose={() => setRenaming(null)}>
        <View style={styles.nameOverlay}>
          <View style={styles.nameCard}>
            <Text style={styles.nameTitle}>{t('gpx.renameTitle', { defaultValue: 'Renommer la trace' })}</Text>
            <TextInput
              style={styles.nameInput}
              value={renaming?.name ?? ''}
              onChangeText={(v) => setRenaming((r) => (r ? { ...r, name: v } : r))}
              placeholder={t('gpx.namePlaceholder', { defaultValue: 'Ex. Boucle du lac' })}
              placeholderTextColor={colors.textMuted}
              maxLength={80}
              autoFocus
            />
            <View style={styles.nameActions}>
              <Pressable style={styles.nameCancel} onPress={() => setRenaming(null)}>
                <Text style={styles.nameCancelText}>{t('common.cancel', { defaultValue: 'Annuler' })}</Text>
              </Pressable>
              <Pressable
                style={[styles.nameSave, ((renaming?.name.trim().length ?? 0) < 1 || renameMutation.isPending) && styles.disabled]}
                disabled={(renaming?.name.trim().length ?? 0) < 1 || renameMutation.isPending}
                onPress={submitRename}
              >
                <Text style={styles.nameSaveText}>{t('gpx.save', { defaultValue: 'Enregistrer' })}</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function midpoint(coords: number[][]): [number, number] {
  const mid = coords[Math.floor(coords.length / 2)];
  const lng = mid?.[0];
  const lat = mid?.[1];
  if (lng === undefined || lat === undefined) return [6.6323, 44.8967];
  return [lng, lat];
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, gap: spacing.sm },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.xs, lineHeight: 20 },
  empty: { alignItems: 'center', gap: spacing.md, marginTop: spacing.xl * 1.5, paddingHorizontal: spacing.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', lineHeight: 22 },
  row: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.borderMuted,
    paddingLeft: spacing.md, paddingRight: spacing.sm, paddingVertical: spacing.sm,
    ...shadows.card,
  },
  rowMain: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: 2 },
  rowIcon: { width: 30, alignItems: 'center' },
  rowInfo: { flex: 1, minWidth: 0 },
  rowName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  rowMeta: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2 },
  rowActions: { flexDirection: 'row', alignItems: 'center' },
  actionBtn: { padding: spacing.sm },
  fab: {
    position: 'absolute', alignSelf: 'center',
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingHorizontal: spacing.lg, paddingVertical: spacing.sm + 2,
    ...shadows.raised,
  },
  fabText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  previewContainer: { flex: 1, backgroundColor: colors.background },
  closeBtn: {
    position: 'absolute', left: 20, width: 36, height: 36, borderRadius: radius.sm,
    backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center',
    zIndex: 10, borderWidth: 1, borderColor: colors.borderStrong,
  },
  previewBanner: {
    position: 'absolute', alignSelf: 'center', zIndex: 10, alignItems: 'center',
    backgroundColor: colors.background + 'F0', borderRadius: radius.full,
    paddingHorizontal: spacing.md, paddingVertical: spacing.xs,
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  previewName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800' },
  previewMeta: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '600' },
  nameOverlay: {
    flex: 1, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: spacing.lg,
  },
  nameCard: { width: '100%', backgroundColor: colors.background, borderRadius: radius.lg, padding: spacing.lg, gap: spacing.md },
  nameTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  nameInput: {
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    color: colors.textPrimary, fontSize: fontSizes.md, backgroundColor: colors.surface,
  },
  nameActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.sm },
  nameCancel: { paddingVertical: spacing.sm, paddingHorizontal: spacing.md },
  nameCancelText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '700' },
  nameSave: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm, paddingHorizontal: spacing.lg },
  nameSaveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  disabled: { opacity: 0.5 },
});
