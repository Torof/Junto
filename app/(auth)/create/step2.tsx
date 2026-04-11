import { useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { JuntoMapView } from '@/components/map-view';
import { useCreateStore } from '@/store/create-store';
import { useInitialLocation } from '@/hooks/use-initial-location';

export default function CreateStep2() {
  const { t } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();
  const { center } = useInitialLocation();
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);
  const [placingPin, setPlacingPin] = useState<'start' | 'meeting' | null>('start');

  const handleMapPress = (lng: number, lat: number) => {
    if (placingPin === 'start') {
      updateForm({ location_start: { lng, lat } });
      setPlacingPin(null);
    } else if (placingPin === 'meeting') {
      updateForm({ location_meeting: { lng, lat } });
      setPlacingPin(null);
    }
  };

  const isValid = form.location_start && form.starts_at && (form.duration_hours > 0 || form.duration_minutes >= 15);

  return (
    <View style={styles.container}>
      <View style={styles.mapContainer}>
        <JuntoMapView
          center={form.location_start ? [form.location_start.lng, form.location_start.lat] : center}
          zoom={12}
          onMapPress={handleMapPress}
        />
        {placingPin && (
          <View style={styles.mapOverlay}>
            <Text style={styles.mapHint}>
              {placingPin === 'start' ? t('create.tapStart') : t('create.tapMeeting')}
            </Text>
          </View>
        )}
      </View>

      <View style={styles.controls}>
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
        </View>

        <Pressable style={styles.dateButton} onPress={() => setShowDatePicker(true)}>
          <Text style={styles.dateLabel}>{t('create.dateTime')}</Text>
          <Text style={styles.dateValue}>
            {form.starts_at ? dayjs(form.starts_at).format('ddd D MMM · HH:mm') : t('create.selectDateTime')}
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
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  mapContainer: { height: 250 },
  mapOverlay: { position: 'absolute', bottom: spacing.md, left: spacing.md, right: spacing.md, alignItems: 'center' },
  mapHint: { backgroundColor: colors.background + 'E6', color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold', paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.full },
  controls: { flex: 1, padding: spacing.lg },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.md },
  pinButtons: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  pinButton: { flex: 1, backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  pinSet: { borderColor: colors.success, borderWidth: 1 },
  pinText: { color: colors.textPrimary, fontSize: fontSizes.sm },
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
