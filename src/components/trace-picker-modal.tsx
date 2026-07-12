import { useMemo } from 'react';
import { View, Text, Pressable, Modal, StyleSheet, ScrollView, ActivityIndicator, Dimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Route as RouteIcon, X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useGpxTraces } from '@/hooks/use-gpx-traces';
import type { GeoJsonLineString } from '@/services/activity-service';

interface Props {
  visible: boolean;
  onClose: () => void;
  onSelect: (geojson: GeoJsonLineString, name: string) => void;
}

// Bottom-sheet picker over the user's GPX library. Selecting a trace hands its
// geojson back so the caller can attach a COPY (an activity keeps its own
// snapshot — deleting the library original never breaks the activity).
export function TracePickerModal({ visible, onClose, onSelect }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const { data: traces, isLoading } = useGpxTraces();
  const list = traces ?? [];

  return (
    <Modal visible={visible} transparent animationType="slide" statusBarTranslucent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={[styles.sheet, { paddingBottom: insets.bottom + spacing.md }]}>
        <View style={styles.header}>
          <Text style={styles.title}>{t('gpx.pickTitle', { defaultValue: 'Choisir une trace' })}</Text>
          <Pressable onPress={onClose} hitSlop={8}>
            <X size={20} color={colors.textSecondary} strokeWidth={2.2} />
          </Pressable>
        </View>

        {isLoading ? (
          <ActivityIndicator color={colors.cta} style={{ marginVertical: spacing.lg }} />
        ) : list.length === 0 ? (
          <Text style={styles.empty}>
            {t('gpx.pickEmpty', { defaultValue: 'Ta bibliothèque est vide. Crée une trace depuis le menu « Mes traces GPX ».' })}
          </Text>
        ) : (
          <ScrollView style={{ maxHeight: Dimensions.get('window').height * 0.5 }}>
            {list.map((tr) => (
              <Pressable key={tr.id} style={styles.row} onPress={() => onSelect(tr.geojson, tr.name)}>
                <RouteIcon size={20} color={colors.cta} strokeWidth={2.2} />
                <View style={styles.info}>
                  <Text style={styles.name} numberOfLines={1}>{tr.name}</Text>
                  <Text style={styles.meta}>{Number(tr.distance_km).toFixed(1)} km</Text>
                </View>
              </Pressable>
            ))}
          </ScrollView>
        )}
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.4)' },
  sheet: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    paddingHorizontal: spacing.lg, paddingTop: spacing.md,
    ...shadows.sheet,
  },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  empty: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, paddingVertical: spacing.lg },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderBottomWidth: 1, borderBottomColor: colors.line,
  },
  info: { flex: 1, minWidth: 0 },
  name: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  meta: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2 },
});
