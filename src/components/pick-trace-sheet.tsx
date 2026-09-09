import { useMemo } from 'react';
import { View, Text, Modal, Pressable, FlatList, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Route as RouteIcon, Upload } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { gpxTraceService, type GpxTrace } from '@/services/gpx-trace-service';
import { LogoSpinner } from './logo-spinner';

interface Props {
  visible: boolean;
  onClose: () => void;
  onPick: (trace: GpxTrace) => void;
  onImportFile: () => void;
}

// Pick a trace from MY in-app GPX library (table gpx_traces) to share into a
// conversation. An "import a .gpx file" row falls back to the phone file picker.
export function PickTraceSheet({ visible, onClose, onPick, onImportFile }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: traces, isLoading } = useQuery({
    queryKey: ['gpx-traces'], queryFn: () => gpxTraceService.list(), enabled: visible,
  });

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('messagerie.shareTraceTitle', { defaultValue: 'Partager une trace GPX' })}</Text>

          <Pressable style={styles.importRow} onPress={() => { onClose(); onImportFile(); }}>
            <View style={styles.importIcon}><Upload size={18} color={colors.cta} strokeWidth={2.2} /></View>
            <Text style={styles.importText}>{t('messagerie.traceImportFile', { defaultValue: 'Importer un fichier .gpx' })}</Text>
          </Pressable>

          {isLoading ? (
            <View style={styles.center}><LogoSpinner /></View>
          ) : (traces ?? []).length === 0 ? (
            <Text style={styles.empty}>{t('messagerie.traceLibraryEmpty', { defaultValue: 'Aucune trace enregistrée. Importe un fichier .gpx pour commencer.' })}</Text>
          ) : (
            <FlatList
              data={traces}
              keyExtractor={(item) => item.id}
              style={styles.list}
              renderItem={({ item }) => (
                <Pressable style={styles.row} onPress={() => { onPick(item); onClose(); }}>
                  <View style={styles.square}><RouteIcon size={20} color={colors.cta} strokeWidth={2.2} /></View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.name} numberOfLines={1}>{item.name}</Text>
                    {item.distance_km != null && (
                      <Text style={styles.sub} numberOfLines={1}>
                        {t('messagerie.traceDistance', { defaultValue: '{{km}} km', km: Math.round(item.distance_km) })}
                      </Text>
                    )}
                  </View>
                </Pressable>
              )}
            />
          )}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '80%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  importRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm, marginBottom: spacing.xs, borderBottomWidth: 1, borderBottomColor: colors.line, paddingBottom: spacing.md },
  importIcon: { width: 44, height: 44, borderRadius: radius.md, backgroundColor: colors.cta + '18', alignItems: 'center', justifyContent: 'center' },
  importText: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '800' },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl },
  center: { paddingVertical: spacing.xl, alignItems: 'center' },
  list: { maxHeight: 420 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
  square: { width: 44, height: 44, borderRadius: radius.md, backgroundColor: colors.surfaceAlt, alignItems: 'center', justifyContent: 'center' },
  name: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  sub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
});
