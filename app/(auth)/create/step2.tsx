import { useState, useMemo } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import * as DocumentPicker from 'expo-document-picker';
import { File } from 'expo-file-system';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import {
  Flag, MapPin, Goal, Trophy, Route, Calendar, Clock, Check, Plus, Minus,
  type LucideIcon,
} from 'lucide-react-native';
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

  const startsAtInPast = form.starts_at !== null && form.starts_at <= new Date();
  const isValid = form.location_meeting
    && form.starts_at
    && !startsAtInPast
    && (form.duration_hours > 0 || form.duration_minutes >= 15);

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
          <View style={styles.mapOverlay} pointerEvents="none">
            <View style={[
              styles.mapHintPill,
              { backgroundColor:
                  placingPin === 'start' ? colors.pinStart :
                  placingPin === 'meeting' ? colors.pinMeeting :
                  placingPin === 'end' ? colors.pinEnd :
                  colors.pinObjective
              },
            ]}>
              <Text style={styles.mapHintText}>
                {placingPin === 'start' ? t('create.tapStart') : placingPin === 'meeting' ? t('create.tapMeeting') : placingPin === 'end' ? t('create.tapEnd') : t('create.tapObjective')}
              </Text>
            </View>
          </View>
        )}
      </View>

      <ScrollView style={styles.controls} contentContainerStyle={styles.controlsContent}>
        <Text style={styles.stepLabel}>{t('create.step', { current: 2, total: 4 })}</Text>

        <Text style={styles.sectionLabel}>{t('create.sectionLocations')}</Text>

        <View style={styles.pinButtons}>
          <PinButton
            kind="start"
            icon={Flag}
            label={t('create.startPoint')}
            isPlacing={placingPin === 'start'}
            isSet={!!form.location_start}
            tint={colors.pinStart}
            colors={colors}
            onPress={() => {
              if (form.location_start) {
                updateForm({ location_start: null });
                if (placingPin === 'start') setPlacingPin(null);
              } else {
                setPlacingPin('start');
              }
            }}
          />
          <PinButton
            kind="meeting"
            icon={MapPin}
            label={t('create.meetingPoint')}
            isPlacing={placingPin === 'meeting'}
            isSet={!!form.location_meeting}
            tint={colors.pinMeeting}
            colors={colors}
            onPress={() => {
              if (form.location_meeting) {
                updateForm({ location_meeting: null });
                if (placingPin === 'meeting') setPlacingPin(null);
              } else {
                setPlacingPin('meeting');
              }
            }}
          />
          <PinButton
            kind="end"
            icon={Goal}
            label={t('create.endPoint')}
            isPlacing={placingPin === 'end'}
            isSet={!!form.location_end}
            tint={colors.pinEnd}
            colors={colors}
            onPress={() => {
              if (form.location_end) {
                updateForm({ location_end: null });
                if (placingPin === 'end') setPlacingPin(null);
              } else {
                setPlacingPin('end');
              }
            }}
          />
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
          style={[
            styles.objectiveButton,
            { borderLeftColor: colors.pinObjective },
            placingPin === 'objective' && { backgroundColor: colors.pinObjective },
            form.location_objective && !placingPin && { borderColor: colors.pinObjective, borderWidth: 1 },
          ]}
          onPress={() => {
            if (form.location_objective) {
              updateForm({ location_objective: null });
              if (placingPin === 'objective') setPlacingPin(null);
            } else {
              setPlacingPin('objective');
            }
          }}
        >
          <Trophy
            size={16}
            color={placingPin === 'objective' ? colors.background : colors.pinObjective}
            strokeWidth={2.2}
          />
          <Text style={[
            styles.objectiveText,
            placingPin === 'objective' && { color: colors.background },
          ]}>
            {form.location_objective ? t('create.objectiveSet') : t('create.setObjective')}
          </Text>
          {form.location_objective && placingPin !== 'objective' && (
            <Check size={14} color={colors.pinObjective} strokeWidth={2.4} />
          )}
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
            <Route size={16} color={colors.cta} strokeWidth={2.2} />
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
            <Route size={16} color={colors.cta} strokeWidth={2.2} />
            <Text style={styles.traceButtonText}>
              {isLoadingTrace ? t('create.traceLoading') : t('create.traceImport')}
            </Text>
          </Pressable>
        )}

        <Text style={styles.sectionLabel}>{t('create.sectionTiming')}</Text>

        <Pressable style={styles.dateButton} onPress={() => setShowDatePicker(true)}>
          <Calendar size={18} color={colors.textSecondary} strokeWidth={2.2} />
          <View style={styles.dateContent}>
            <Text style={styles.dateLabel}>{t('create.dateTime')}</Text>
            <Text style={styles.dateValue}>
              {form.starts_at ? dayjs(form.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm') : t('create.selectDateTime')}
            </Text>
          </View>
        </Pressable>
        {startsAtInPast && (
          <Text style={styles.dateError}>{t('create.startsAtPast')}</Text>
        )}

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
            onChange={(_e, time) => {
              setShowTimePicker(false);
              if (time) {
                // Mirror the date picker pattern: preserve the date
                // portion of starts_at, only overwrite hours/minutes.
                // On Android mode='time' returns a Date with today's
                // date + the picked time, which would silently reset
                // any future date the user already chose.
                const next = new Date(form.starts_at ?? new Date());
                next.setHours(time.getHours(), time.getMinutes(), 0, 0);
                updateForm({ starts_at: next });
              }
            }}
          />
        )}

        <View style={styles.durationRow}>
          <View style={styles.durationHeader}>
            <Clock size={18} color={colors.textSecondary} strokeWidth={2.2} />
            <Text style={styles.dateLabel}>{t('create.duration')}</Text>
          </View>
          <View style={styles.durationPickers}>
            <Pressable
              style={styles.durationButton}
              onPress={() => updateForm({ duration_hours: Math.max(0, form.duration_hours - 1) })}
              hitSlop={8}
            >
              <Minus size={16} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
            <Text style={styles.durationValue}>{form.duration_hours}h{form.duration_minutes > 0 ? form.duration_minutes : ''}</Text>
            <Pressable
              style={styles.durationButton}
              onPress={() => updateForm({ duration_hours: Math.min(24, form.duration_hours + 1) })}
              hitSlop={8}
            >
              <Plus size={16} color={colors.textPrimary} strokeWidth={2.4} />
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

interface PinButtonProps {
  kind: 'start' | 'meeting' | 'end';
  icon: LucideIcon;
  label: string;
  isPlacing: boolean;
  isSet: boolean;
  tint: string;
  colors: AppColors;
  onPress: () => void;
}

function PinButton({ icon: Icon, label, isPlacing, isSet, tint, colors, onPress }: PinButtonProps) {
  const styles = createPinButtonStyles(colors, tint, isPlacing, isSet);
  const iconColor = isPlacing ? colors.background : tint;
  const labelColor = isPlacing ? colors.background : (isSet ? tint : colors.textPrimary);
  return (
    <Pressable style={styles.button} onPress={onPress}>
      <Icon size={18} color={iconColor} strokeWidth={2.2} />
      <Text style={[styles.label, { color: labelColor }]} numberOfLines={1}>
        {label}
      </Text>
      {isSet && !isPlacing && <Check size={12} color={tint} strokeWidth={2.6} />}
    </Pressable>
  );
}

const createPinButtonStyles = (colors: AppColors, tint: string, isPlacing: boolean, isSet: boolean) =>
  StyleSheet.create({
    button: {
      flex: 1,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
      paddingVertical: spacing.sm + 2,
      paddingHorizontal: spacing.sm,
      borderRadius: radius.md,
      borderLeftWidth: 4,
      borderLeftColor: tint,
      backgroundColor: isPlacing ? tint : colors.surface,
      borderTopWidth: isSet && !isPlacing ? 1 : 0,
      borderRightWidth: isSet && !isPlacing ? 1 : 0,
      borderBottomWidth: isSet && !isPlacing ? 1 : 0,
      borderTopColor: tint,
      borderRightColor: tint,
      borderBottomColor: tint,
    },
    label: {
      fontSize: fontSizes.xs,
      fontWeight: '600',
    },
  });

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  mapContainer: { flex: 3 },
  mapOverlay: { position: 'absolute', bottom: spacing.md, left: spacing.md, right: spacing.md, alignItems: 'center' },
  mapHintPill: {
    paddingHorizontal: spacing.md + 2,
    paddingVertical: spacing.sm,
    borderRadius: radius.full,
    shadowColor: '#000',
    shadowOpacity: 0.18,
    shadowOffset: { width: 0, height: 2 },
    shadowRadius: 4,
    elevation: 3,
  },
  mapHintText: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '600',
    letterSpacing: 0.2,
  },
  controls: { flex: 2 },
  controlsContent: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  stepLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '500', marginBottom: spacing.md },
  sectionLabel: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginTop: spacing.md,
    marginBottom: spacing.sm,
  },
  pinButtons: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  objectiveButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderLeftWidth: 4,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    marginBottom: spacing.md,
  },
  objectiveText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  objectiveNameInput: { backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, fontSize: fontSizes.sm, marginBottom: spacing.md },
  dateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  dateContent: { flex: 1 },
  dateLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  dateValue: { color: colors.textPrimary, fontSize: fontSizes.md },
  dateError: { color: colors.error, fontSize: fontSizes.xs, marginTop: -spacing.sm, marginBottom: spacing.md },
  durationRow: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  durationHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  durationPickers: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, marginTop: spacing.sm },
  durationButton: { backgroundColor: colors.background, borderRadius: radius.full, width: 36, height: 36, alignItems: 'center', justifyContent: 'center' },
  durationValue: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', minWidth: 50, textAlign: 'center' },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  buttonDisabled: { opacity: 0.4 },
  nextText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  traceButton: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm,
    backgroundColor: colors.surface, borderRadius: radius.md,
    borderWidth: 1, borderStyle: 'dashed', borderColor: colors.cta,
    paddingVertical: spacing.sm + 2, marginBottom: spacing.md,
  },
  traceButtonText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600' },
  traceSetRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.cta + '15',
    borderWidth: 1, borderColor: colors.cta,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 2,
    marginBottom: spacing.md,
  },
  traceSetText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  traceClearText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '600' },
});
