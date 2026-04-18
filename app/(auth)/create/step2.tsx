import { useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { JuntoMapView } from '@/components/map-view';
import { useCreateStore } from '@/store/create-store';
import { useInitialLocation } from '@/hooks/use-initial-location';

export default function CreateStep2() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();
  const { center } = useInitialLocation();
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);
  const [placingPin, setPlacingPin] = useState<'start' | 'meeting' | 'end' | 'objective' | null>('meeting');

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
    form.location_start && { id: 'start', coordinate: [form.location_start.lng, form.location_start.lat] as [number, number], color: '#22c55e' },
    form.location_meeting && { id: 'meeting', coordinate: [form.location_meeting.lng, form.location_meeting.lat] as [number, number], color: '#3b82f6' },
    form.location_end && { id: 'end', coordinate: [form.location_end.lng, form.location_end.lat] as [number, number], color: '#ef4444' },
    form.location_objective && { id: 'objective', coordinate: [form.location_objective.lng, form.location_objective.lat] as [number, number], color: '#F5A623' },
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
            onPress={() => setPlacingPin('start')}
          >
            <Text style={styles.pinText}>
              {form.location_start ? '✓ ' + t('create.startPoint') : t('create.setStart')}
            </Text>
          </Pressable>
          <Pressable
            style={[styles.pinButton, form.location_meeting && styles.pinSet]}
            onPress={() => setPlacingPin('meeting')}
          >
            <Text style={styles.pinText}>
              {form.location_meeting ? '✓ ' + t('create.meetingPoint') : t('create.setMeeting')}
            </Text>
          </Pressable>
          <Pressable
            style={[styles.pinButton, form.location_end && styles.pinSet]}
            onPress={() => setPlacingPin('end')}
          >
            <Text style={styles.pinText}>
              {form.location_end ? '✓ ' + t('create.endPoint') : t('create.setEnd')}
            </Text>
          </Pressable>
        </View>
        <Pressable
          style={[styles.objectiveButton, form.location_objective && styles.objectiveSet]}
          onPress={() => setPlacingPin('objective')}
        >
          <Text style={styles.objectiveText}>
            {form.location_objective ? '🎯 ' + t('create.objectiveSet') : '🎯 ' + t('create.setObjective')}
          </Text>
        </Pressable>

        <Pressable style={styles.dateButton} onPress={() => setShowDatePicker(true)}>
          <Text style={styles.dateLabel}>{t('create.dateTime')}</Text>
          <Text style={styles.dateValue}>
            {form.starts_at ? dayjs(form.starts_at).locale(i18n.language).format('ddd D MMM · HH:mm') : t('create.selectDateTime')}
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

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  mapContainer: { flex: 1 },
  mapOverlay: { position: 'absolute', bottom: spacing.md, left: spacing.md, right: spacing.md, alignItems: 'center' },
  mapHint: { backgroundColor: colors.background + 'E6', color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold', paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.full },
  controls: { flex: 1 },
  controlsContent: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.md },
  pinButtons: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  pinButton: { flex: 1, backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  pinSet: { borderColor: colors.success, borderWidth: 1 },
  pinText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  objectiveButton: { backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center', marginBottom: spacing.md },
  objectiveSet: { borderColor: '#F5A623', borderWidth: 1 },
  objectiveText: { color: colors.textPrimary, fontSize: fontSizes.sm },
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
});
