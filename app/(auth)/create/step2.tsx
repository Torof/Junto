import { useState, useMemo } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import * as DocumentPicker from 'expo-document-picker';
import { File } from 'expo-file-system';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { JuntoMapView } from '@/components/map-view';
import { useCreateStore } from '@/store/create-store';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { parseGpxToGeoJson, GpxParseError } from '@/utils/parse-gpx';

export default function CreateStep2() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();
  const { center } = useInitialLocation();
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);
  const [placingPin, setPlacingPin] = useState<'start' | 'meeting' | 'end' | 'objective' | null>('meeting');
  const [isLoadingTrace, setIsLoadingTrace] = useState(false);

  const handlePickTrace = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: '*/*',
        copyToCacheDirectory: true,
      });
      if (result.canceled) return;
      const file = result.assets[0];
      if (!file) return;
      if (file.size != null && file.size > 5 * 1024 * 1024) {
        Alert.alert(t('create.traceTooLarge'));
        return;
      }
      setIsLoadingTrace(true);
      const xml = await new File(file.uri).text();
      const geojson = parseGpxToGeoJson(xml);
      updateForm({ trace_geojson: geojson });
    } catch (err) {
      if (err instanceof GpxParseError) {
        Alert.alert(t('create.traceParseError'), err.message);
      } else {
        Alert.alert(t('auth.error'), err instanceof Error ? err.message : 'Unknown error');
      }
    } finally {
      setIsLoadingTrace(false);
    }
  };

  const handleClearTrace = () => {
    updateForm({ trace_geojson: null });
  };

  const handleMapPress = (lng: number, lat: number) => {
    if (placingPin === 'start') {
      updateForm({ location_start: { lng, lat } });
      setPlacingPin(null);
    } else if (placingPin === 'meeting') {
      updateForm({ location_meeting: { lng, lat } });
      setPlacingPin(null);
    } else if (placingPin === 'end') {
      updateForm({ location_end: { lng, lat } });
      setPlacingPin(null);
    } else if (placingPin === 'objective') {
      updateForm({ location_objective: { lng, lat } });
      setPlacingPin(null);
    }
  };

  const pins = [
    form.location_start && { id: 'start', coordinate: [form.location_start.lng, form.location_start.lat] as [number, number], color: colors.pinStart },
    form.location_meeting && { id: 'meeting', coordinate: [form.location_meeting.lng, form.location_meeting.lat] as [number, number], color: colors.pinMeeting },
    form.location_end && { id: 'end', coordinate: [form.location_end.lng, form.location_end.lat] as [number, number], color: colors.pinEnd },
    form.location_objective && { id: 'objective', coordinate: [form.location_objective.lng, form.location_objective.lat] as [number, number], color: colors.pinObjective },
  ].filter(Boolean) as { id: string; coordinate: [number, number]; color: string }[];

  const isValid = form.location_meeting && form.starts_at && (form.duration_hours > 0 || form.duration_minutes >= 15);

  return (
    <View style={styles.container}>
      <View style={styles.mapContainer}>
        <JuntoMapView
          center={form.location_meeting ? [form.location_meeting.lng, form.location_meeting.lat] : form.location_start ? [form.location_start.lng, form.location_start.lat] : center}
          zoom={12}
          onMapPress={handleMapPress}
          pins={pins}
          routeLine={(() => {
            if (form.trace_geojson) {
              return form.trace_geojson.coordinates.map((c) => [c[0]!, c[1]!] as [number, number]);
            }
            const start = form.location_start ?? form.location_meeting;
            if (start && form.location_end) return [[start.lng, start.lat], [form.location_end.lng, form.location_end.lat]] as [number, number][];
            return undefined;
          })()}
        />
        {placingPin && (
          <View style={styles.mapOverlay}>
            <Text style={styles.mapHint}>
              {placingPin === 'start' ? t('create.tapStart') : placingPin === 'meeting' ? t('create.tapMeeting') : placingPin === 'end' ? t('create.tapEnd') : t('create.tapObjective')}
            </Text>
          </View>
        )}
      </View>

      <ScrollView style={styles.controls} contentContainerStyle={styles.controlsContent}>
        <Text style={styles.stepLabel}>{t('create.step', { current: 2, total: 4 })}</Text>

        <View style={styles.pinButtons}>
          <Pressable
            style={[styles.pinButton, form.location_start && styles.pinSet]}
            onPress={() => {
              if (form.location_start) {
                updateForm({ location_start: null });
                if (placingPin === 'start') setPlacingPin(null);
              } else {
                setPlacingPin('start');
              }
            }}
          >
            <Text style={styles.pinText}>
              {form.location_start ? '✓ ' + t('create.startPoint') : t('create.setStart')}
            </Text>
          </Pressable>
          <Pressable
            style={[styles.pinButton, form.location_meeting && styles.pinSet]}
            onPress={() => {
              if (form.location_meeting) {
                updateForm({ location_meeting: null });
                if (placingPin === 'meeting') setPlacingPin(null);
              } else {
                setPlacingPin('meeting');
              }
            }}
          >
            <Text style={styles.pinText}>
              {form.location_meeting ? '✓ ' + t('create.meetingPoint') : t('create.setMeeting')}
            </Text>
          </Pressable>
          <Pressable
            style={[styles.pinButton, form.location_end && styles.pinSet]}
            onPress={() => {
              if (form.location_end) {
                updateForm({ location_end: null });
                if (placingPin === 'end') setPlacingPin(null);
              } else {
                setPlacingPin('end');
              }
            }}
          >
            <Text style={styles.pinText}>
              {form.location_end ? '✓ ' + t('create.endPoint') : t('create.setEnd')}
            </Text>
          </Pressable>
        </View>
        {form.location_start && (
          <TextInput
            style={styles.objectiveNameInput}
            placeholder={t('create.startName')}
            placeholderTextColor={colors.textSecondary}
            value={form.start_name}
            onChangeText={(text) => updateForm({ start_name: text })}
            maxLength={100}
          />
        )}
        <Pressable
          style={[styles.objectiveButton, form.location_objective && styles.objectiveSet]}
          onPress={() => {
            if (form.location_objective) {
              updateForm({ location_objective: null });
              if (placingPin === 'objective') setPlacingPin(null);
            } else {
              setPlacingPin('objective');
            }
          }}
        >
          <Text style={styles.objectiveText}>
            {form.location_objective ? '🎯 ' + t('create.objectiveSet') : '🎯 ' + t('create.setObjective')}
          </Text>
        </Pressable>
        {(placingPin === 'objective' || form.location_objective || (form.objective_name?.length ?? 0) > 0) && (
          <TextInput
            style={styles.objectiveNameInput}
            placeholder={t('create.objectiveName')}
            placeholderTextColor={colors.textSecondary}
            value={form.objective_name}
            onChangeText={(text) => updateForm({ objective_name: text })}
            maxLength={100}
          />
        )}

        {form.trace_geojson ? (
          <View style={styles.traceSetRow}>
            <Text style={styles.traceSetText}>
              {t('create.traceSet', { count: form.trace_geojson.coordinates.length })}
            </Text>
            <Pressable onPress={handleClearTrace} hitSlop={8}>
              <Text style={styles.traceClearText}>{t('create.traceRemove')}</Text>
            </Pressable>
          </View>
        ) : (
          <Pressable
            style={[styles.traceButton, isLoadingTrace && { opacity: 0.5 }]}
            onPress={handlePickTrace}
            disabled={isLoadingTrace}
          >
            <Text style={styles.traceButtonText}>
              {isLoadingTrace ? t('create.traceLoading') : '📍 ' + t('create.traceImport')}
            </Text>
          </Pressable>
        )}

        <Pressable style={styles.dateButton} onPress={() => setShowDatePicker(true)}>
          <Text style={styles.dateLabel}>{t('create.dateTime')}</Text>
          <Text style={styles.dateValue}>
            {form.starts_at ? dayjs(form.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm') : t('create.selectDateTime')}
          </Text>
        </Pressable>

        {showDatePicker && (
          <DateTimePicker
            value={form.starts_at ?? new Date()}
            mode="date"
            minimumDate={new Date()}
            onChange={(_e, date) => {
              setShowDatePicker(false);
              if (date) {
                const current = form.starts_at ?? new Date();
                date.setHours(current.getHours(), current.getMinutes());
                updateForm({ starts_at: date });
                setShowTimePicker(true);
              }
            }}
          />
        )}

        {showTimePicker && (
          <DateTimePicker
            value={form.starts_at ?? new Date()}
            mode="time"
            onChange={(_e, date) => {
              setShowTimePicker(false);
              if (date) updateForm({ starts_at: date });
            }}
          />
        )}

        <View style={styles.durationRow}>
          <Text style={styles.dateLabel}>{t('create.duration')}</Text>
          <View style={styles.durationPickers}>
            <Pressable style={styles.durationButton} onPress={() => updateForm({ duration_hours: Math.max(0, form.duration_hours - 1) })}>
              <Text style={styles.counterText}>-</Text>
            </Pressable>
            <Text style={styles.durationValue}>{form.duration_hours}h{form.duration_minutes > 0 ? form.duration_minutes : ''}</Text>
            <Pressable style={styles.durationButton} onPress={() => updateForm({ duration_hours: Math.min(24, form.duration_hours + 1) })}>
              <Text style={styles.counterText}>+</Text>
            </Pressable>
          </View>
        </View>

        <Pressable
          style={[styles.nextButton, !isValid && styles.buttonDisabled]}
          onPress={() => isValid && router.push('/(auth)/create/step3')}
          disabled={!isValid}
        >
          <Text style={styles.nextText}>{t('create.next')}</Text>
        </Pressable>
      </ScrollView>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  mapContainer: { flex: 1 },
  mapOverlay: { position: 'absolute', bottom: spacing.md, left: spacing.md, right: spacing.md, alignItems: 'center' },
  mapHint: { backgroundColor: colors.background, color: colors.cta, fontSize: fontSizes.md, fontWeight: 'bold', paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.full, borderWidth: 1, borderColor: colors.cta },
  controls: { flex: 1 },
  controlsContent: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.md },
  pinButtons: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  pinButton: { flex: 1, backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  pinSet: { borderColor: colors.success, borderWidth: 1 },
  pinText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  objectiveButton: { backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center', marginBottom: spacing.md },
  objectiveSet: { borderColor: colors.pinObjective, borderWidth: 1 },
  objectiveText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  objectiveNameInput: { backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: fontSizes.sm, marginBottom: spacing.md },
  dateButton: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  dateLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  dateValue: { color: colors.textPrimary, fontSize: fontSizes.md },
  durationRow: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  durationPickers: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, marginTop: spacing.sm },
  durationButton: { backgroundColor: colors.background, borderRadius: radius.full, width: 36, height: 36, alignItems: 'center', justifyContent: 'center' },
  counterText: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  durationValue: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', minWidth: 50, textAlign: 'center' },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  buttonDisabled: { opacity: 0.4 },
  nextText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  traceButton: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    borderWidth: 1, borderStyle: 'dashed', borderColor: colors.cta,
    paddingVertical: spacing.sm, alignItems: 'center', marginBottom: spacing.md,
  },
  traceButtonText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600' },
  traceSetRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: colors.cta + '15',
    borderWidth: 1, borderColor: colors.cta,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    marginBottom: spacing.md,
  },
  traceSetText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  traceClearText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '600' },
});
