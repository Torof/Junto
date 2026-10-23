import { useState, useMemo, useRef, useEffect } from 'react';
import { View, Pressable, StyleSheet, Alert } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';
import { KeyboardDoneBar } from '@/components/keyboard-done-bar';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import DateTimePicker from '@react-native-community/datetimepicker';
import * as DocumentPicker from 'expo-document-picker';
import { File } from 'expo-file-system';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import {
  MapPin, Goal, Trophy, Route, Calendar, Clock, Check, Plus, Minus,
  Upload, Library, Pencil,
  type LucideIcon,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { JuntoMapView } from '@/components/map-view';
import { useCreateStore } from '@/store/create-store';
import { useSports } from '@/hooks/use-sports';
import { sportHasDistance, sportHasElevation } from '@/constants/sport-levels';
import { formatTraceStats } from '@/utils/trace-stats';
import { getFriendlyError } from '@/utils/friendly-error';
import { geocodeService } from '@/services/geocode-service';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { parseGpxToGeoJson, GpxParseError } from '@/utils/parse-gpx';
import { enrichTraceElevation } from '@/utils/trace-elevation';
import { activityService, type GeoJsonLineString } from '@/services/activity-service';
import { TracePickerModal } from '@/components/trace-picker-modal';
import { TraceDrawModal } from '@/components/trace-draw-modal';

export default function CreateStep2() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const { form, updateForm } = useCreateStore();
  const { center } = useInitialLocation();
  // Distance / D+ fields sit right under the trace that produces them, for the
  // sports that use them (same gating as the cards).
  const { data: sports } = useSports();
  const selectedSportKey = sports?.find((s) => s.id === form.sport_id)?.key ?? '';
  const showDistance = sportHasDistance(selectedSportKey);
  const showElevation = sportHasElevation(selectedSportKey);
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showTimePicker, setShowTimePicker] = useState(false);
  // Default to 'meeting' placement only if no meeting is prefilled — when the
  // user came in via the on-map tap-to-create flow, the chosen pin is already
  // set and we'd otherwise show the corresponding button as 'currently placing'
  // (visual lie). Falling back to 'meeting' covers the cold-start case where
  // meeting is the next required action.
  const [placingPin, setPlacingPin] = useState<'meeting' | 'end' | 'objective' | null>(
    () => form.location_meeting ? null : 'meeting',
  );
  const [isLoadingTrace, setIsLoadingTrace] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [drawOpen, setDrawOpen] = useState(false);
  // Distance / D+ the server reads off the trace (mig 00452) — shown under the
  // trace row and written into the two fields just below it (Scott 2026-10-16:
  // setting a trace FILLS the fields, typed or not; the organiser corrects
  // after). A trace without altitudes leaves the D+ field as it is.
  const [traceStats, setTraceStats] = useState<{ distance_km: number | null; elevation_gain_m: number | null } | null>(null);
  const [traceStatsPending, setTraceStatsPending] = useState(false);

  const applyTrace = async (geojson: GeoJsonLineString) => {
    updateForm({ trace_geojson: geojson });
    setTraceStats(null);
    setTraceStatsPending(true);
    try {
      // Drawn traces have no altitudes: fetch them (IGN) so D+ can be derived.
      const enriched = await enrichTraceElevation(geojson);
      if (enriched !== geojson) updateForm({ trace_geojson: enriched });
      const stats = await activityService.computeTraceStats(enriched);
      setTraceStats(stats);
      const patch: { distance_km?: number; elevation_gain_m?: number } = {};
      if (stats.distance_km != null && stats.distance_km > 0) patch.distance_km = stats.distance_km;
      if (stats.elevation_gain_m != null && stats.elevation_gain_m > 0) patch.elevation_gain_m = stats.elevation_gain_m;
      if (Object.keys(patch).length > 0) updateForm(patch);
    } catch {
      // Best effort — the trace itself is set; the figures stay editable by hand.
    } finally {
      setTraceStatsPending(false);
    }
  };

  const traceStatsLabel = useMemo(
    () => (traceStats ? formatTraceStats(traceStats.distance_km, traceStats.elevation_gain_m, i18n.language) : null),
    [traceStats, i18n.language],
  );

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
      void applyTrace(geojson);
    } catch (err) {
      if (err instanceof GpxParseError) {
        Alert.alert(t('create.traceParseError'), err.message);
      } else {
        Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
      }
    } finally {
      setIsLoadingTrace(false);
    }
  };

  const handleClearTrace = () => {
    updateForm({ trace_geojson: null });
    setTraceStats(null);
  };

  // Locality lookup for the meeting pin (mig 00441): fire-and-forget, the
  // previous request is cancelled when the pin moves, and a failure simply
  // leaves the field null — the creation flow never waits on Photon.
  const localityAbort = useRef<AbortController | null>(null);
  const lookupLocality = (lng: number, lat: number) => {
    localityAbort.current?.abort();
    const ctrl = new AbortController();
    localityAbort.current = ctrl;
    geocodeService.reverseLocality(lat, lng, ctrl.signal)
      .then((locality) => { if (!ctrl.signal.aborted) updateForm({ meeting_locality: locality }); })
      .catch(() => {});
  };
  useEffect(() => () => localityAbort.current?.abort(), []);

  const handleMapPress = (lng: number, lat: number) => {
    if (placingPin === 'meeting') {
      updateForm({ location_meeting: { lng, lat }, meeting_locality: null });
      setPlacingPin(null);
      lookupLocality(lng, lat);
    } else if (placingPin === 'end') {
      updateForm({ location_end: { lng, lat } });
      setPlacingPin(null);
    } else if (placingPin === 'objective') {
      updateForm({ location_objective: { lng, lat } });
      setPlacingPin(null);
    }
  };

  const pins = [
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
          center={form.location_meeting ? [form.location_meeting.lng, form.location_meeting.lat] : center}
          zoom={12}
          onMapPress={handleMapPress}
          pins={pins}
          routeLine={(() => {
            if (form.trace_geojson) {
              return form.trace_geojson.coordinates
                .filter((c) => c.length >= 2 && c[0] != null && c[1] != null)
                .map((c) => [c[0]!, c[1]!] as [number, number]);
            }
            const start = form.location_meeting;
            if (start && form.location_end) return [[start.lng, start.lat], [form.location_end.lng, form.location_end.lat]] as [number, number][];
            return undefined;
          })()}
        />
        {placingPin && (
          <View style={styles.mapOverlay} pointerEvents="none">
            <View style={[
              styles.mapHintPill,
              { backgroundColor:
                  placingPin === 'meeting' ? colors.pinMeeting :
                  placingPin === 'end' ? colors.pinEnd :
                  colors.pinObjective
              },
            ]}>
              <AppText style={styles.mapHintText}>
                {placingPin === 'meeting' ? t('create.tapMeeting') : placingPin === 'end' ? t('create.tapEnd') : t('create.tapObjective')}
              </AppText>
            </View>
          </View>
        )}
      </View>

      <KeyboardAwareScrollView style={styles.controls} contentContainerStyle={styles.controlsContent}>
        <AppText style={styles.stepLabel}>{t('create.step', { current: 2, total: 4 })}</AppText>

        <AppText style={styles.sectionLabel}>{t('create.sectionLocations')}</AppText>

        <View style={styles.pinButtons}>
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
                localityAbort.current?.abort();
                updateForm({ location_meeting: null, meeting_locality: null });
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
        {form.location_meeting && form.meeting_locality && (
          <AppText style={styles.localityHint}>{t('create.meetingLocality', { place: form.meeting_locality })}</AppText>
        )}
        {(placingPin === 'meeting' || form.location_meeting || (form.meeting_name?.length ?? 0) > 0) && (
          <AppTextInput
            style={styles.objectiveNameInput}
            placeholder={t('create.meetingName')}
            placeholderTextColor={colors.textSecondary}
            value={form.meeting_name}
            onChangeText={(text) => updateForm({ meeting_name: text })}
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
          <AppText style={[
            styles.objectiveText,
            placingPin === 'objective' && { color: colors.background },
          ]}>
            {form.location_objective ? t('create.objectiveSet') : t('create.setObjective')}
          </AppText>
          {form.location_objective && placingPin !== 'objective' && (
            <Check size={14} color={colors.pinObjective} strokeWidth={2.4} />
          )}
        </Pressable>
        <AppTextInput
          style={styles.objectiveNameInput}
          placeholder={t('create.objectiveName')}
          placeholderTextColor={colors.textSecondary}
          value={form.objective_name}
          onChangeText={(text) => updateForm({ objective_name: text })}
          maxLength={100}
        />
        {/* Objective label is independently useful (e.g. "Mont Blanc")
            even without a pin on the map — keep the input always visible.
            The Trophy button above adds an optional pin location for it. */}

        <AppText style={styles.sectionLabel}>{t('create.sectionRoute')}</AppText>

        {form.trace_geojson ? (
          <View style={styles.traceSetRow}>
            <Route size={16} color={colors.cta} strokeWidth={2.2} />
            <View style={{ flex: 1 }}>
              <AppText style={styles.traceSetText}>
                {t('create.traceSet', { count: form.trace_geojson.coordinates.length })}
              </AppText>
              {(traceStatsLabel || traceStatsPending) && (
                <AppText style={styles.traceStatsText}>
                  {traceStatsLabel ?? t('create.traceStatsPending')}
                </AppText>
              )}
            </View>
            <Pressable onPress={handleClearTrace} hitSlop={8}>
              <AppText style={styles.traceClearText}>{t('create.traceRemove')}</AppText>
            </Pressable>
          </View>
        ) : (
          <View style={styles.traceOptions}>
            <Pressable
              style={[styles.traceButton, { marginBottom: 0 }, isLoadingTrace && { opacity: 0.5 }]}
              onPress={handlePickTrace}
              disabled={isLoadingTrace}
            >
              <Upload size={16} color={colors.cta} strokeWidth={2.2} />
              <AppText style={styles.traceButtonText}>
                {isLoadingTrace ? t('create.traceLoading') : t('create.traceImport')}
              </AppText>
            </Pressable>
            <Pressable
              style={[styles.traceButton, { marginBottom: 0 }]}
              onPress={() => setPickerOpen(true)}
            >
              <Library size={16} color={colors.cta} strokeWidth={2.2} />
              <AppText style={styles.traceButtonText}>{t('create.traceFromLibrary', { defaultValue: 'Ma bibliothèque' })}</AppText>
            </Pressable>
            <Pressable
              style={[styles.traceButton, { marginBottom: 0 }]}
              onPress={() => setDrawOpen(true)}
            >
              <Pencil size={16} color={colors.cta} strokeWidth={2.2} />
              <AppText style={styles.traceButtonText}>{t('create.traceDraw', { defaultValue: 'Dessiner' })}</AppText>
            </Pressable>
          </View>
        )}

        <TracePickerModal
          visible={pickerOpen}
          onClose={() => setPickerOpen(false)}
          onSelect={(geojson) => {
            void applyTrace(geojson);
            setPickerOpen(false);
          }}
        />

        <TraceDrawModal
          visible={drawOpen}
          askName={false}
          onClose={() => setDrawOpen(false)}
          onSave={(_name, geojson) => {
            void applyTrace(geojson);
            setDrawOpen(false);
          }}
        />

        {(showDistance || showElevation) && (
          <View style={styles.metricRow}>
            {showDistance && (
              <View style={styles.metricField}>
                <AppText style={styles.metricLabel}>{t('create.distance')}</AppText>
                <AppTextInput
                  style={styles.metricInput}
                  placeholder="25"
                  placeholderTextColor={colors.textSecondary}
                  value={form.distance_km != null ? String(form.distance_km) : ''}
                  onChangeText={(text) => {
                    const cleaned = text.replace(',', '.').replace(/[^0-9.]/g, '');
                    const num = cleaned === '' ? null : Number(cleaned);
                    updateForm({ distance_km: num && !isNaN(num) && num > 0 ? num : null });
                  }}
                  keyboardType="decimal-pad"
                  maxLength={6}
                />
              </View>
            )}
            {showElevation && (
              <View style={styles.metricField}>
                <AppText style={styles.metricLabel}>{t('create.elevation')}</AppText>
                <AppTextInput
                  style={styles.metricInput}
                  placeholder="1400"
                  placeholderTextColor={colors.textSecondary}
                  value={form.elevation_gain_m != null ? String(form.elevation_gain_m) : ''}
                  onChangeText={(text) => {
                    const cleaned = text.replace(/[^0-9]/g, '');
                    const num = cleaned === '' ? null : Number(cleaned);
                    updateForm({ elevation_gain_m: num && !isNaN(num) && num > 0 ? num : null });
                  }}
                  keyboardType="number-pad"
                  maxLength={5}
                />
              </View>
            )}
          </View>
        )}

        <AppText style={styles.sectionLabel}>{t('create.sectionTiming')}</AppText>

        <View style={styles.timingRow}>
          <Pressable style={[styles.dateButton, styles.timingItem]} onPress={() => setShowDatePicker(true)}>
            <Calendar size={18} color={colors.textSecondary} strokeWidth={2.2} />
            <View style={styles.dateContent}>
              <AppText style={styles.dateLabel}>{t('create.dateTime')}</AppText>
              <AppText style={styles.dateValue} numberOfLines={1}>
                {form.starts_at ? dayjs(form.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm') : t('create.selectDateTime')}
              </AppText>
            </View>
          </Pressable>

          <View style={[styles.durationRow, styles.timingItem]}>
            <View style={styles.durationHeader}>
              <Clock size={18} color={colors.textSecondary} strokeWidth={2.2} />
              <AppText style={styles.dateLabel}>{t('create.duration')}</AppText>
            </View>
            <View style={styles.durationPickers}>
              <Pressable
                style={styles.durationButton}
                onPress={() => updateForm({ duration_hours: Math.max(0, form.duration_hours - 1) })}
                hitSlop={8}
              >
                <Minus size={16} color={colors.textPrimary} strokeWidth={2.4} />
              </Pressable>
              <AppText style={styles.durationValue}>{form.duration_hours}h{form.duration_minutes > 0 ? form.duration_minutes : ''}</AppText>
              <Pressable
                style={styles.durationButton}
                onPress={() => updateForm({ duration_hours: Math.min(24, form.duration_hours + 1) })}
                hitSlop={8}
              >
                <Plus size={16} color={colors.textPrimary} strokeWidth={2.4} />
              </Pressable>
            </View>
          </View>
        </View>
        {startsAtInPast && (
          <AppText style={styles.dateError}>{t('create.startsAtPast')}</AppText>
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

        <Pressable
          style={[styles.nextButton, !isValid && styles.buttonDisabled]}
          onPress={() => isValid && router.push('/(auth)/create/step3')}
          disabled={!isValid}
        >
          <AppText style={styles.nextText}>{t('create.next')}</AppText>
        </Pressable>
      </KeyboardAwareScrollView>
      <KeyboardDoneBar />
    </View>
  );
}

interface PinButtonProps {
  kind: 'meeting' | 'end';
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
      <AppText style={[styles.label, { color: labelColor }]} numberOfLines={1}>
        {label}
      </AppText>
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
      borderRadius: radius.sm,
      backgroundColor: isPlacing ? tint : 'transparent',
      // Full outline so the button shape reads on any background.
      // Left edge always carries the color-coded 4px tint; the other
      // three edges go borderMuted (visible-but-quiet) when empty,
      // and tint when isSet (matches the colored left stripe).
      borderTopWidth: 1,
      borderRightWidth: 1,
      borderBottomWidth: 1,
      borderLeftWidth: 4,
      borderLeftColor: tint,
      borderTopColor: isSet && !isPlacing ? tint : colors.borderMuted,
      borderRightColor: isSet && !isPlacing ? tint : colors.borderMuted,
      borderBottomColor: isSet && !isPlacing ? tint : colors.borderMuted,
    },
    label: {
      fontSize: fontSizes.xs,
      fontWeight: '600',
    },
  });

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  mapContainer: { flex: 1 },
  mapOverlay: { position: 'absolute', bottom: spacing.md, left: spacing.md, right: spacing.md, alignItems: 'center' },
  mapHintPill: {
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderStrong,
  },
  mapHintText: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: 0.2,
  },
  controls: { flex: 1 },
  controlsContent: { padding: spacing.md, paddingBottom: spacing.xl + 32 },
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
    backgroundColor: 'transparent',
    borderRadius: radius.sm,
    borderTopWidth: 1,
    borderRightWidth: 1,
    borderBottomWidth: 1,
    borderTopColor: colors.borderMuted,
    borderRightColor: colors.borderMuted,
    borderBottomColor: colors.borderMuted,
    borderLeftWidth: 4,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    marginBottom: spacing.md,
  },
  objectiveText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  localityHint: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '600',
    marginBottom: spacing.xs, paddingHorizontal: 2,
  },
  objectiveNameInput: {
    backgroundColor: colors.background, color: colors.textPrimary,
    borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm, fontSize: fontSizes.sm,
    marginBottom: spacing.md,
  },
  metricRow: { flexDirection: 'row', gap: spacing.md, marginBottom: spacing.md },
  metricField: { flex: 1 },
  metricLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '600', marginBottom: spacing.xs },
  metricInput: {
    backgroundColor: colors.background, color: colors.textPrimary,
    borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm, fontSize: fontSizes.sm,
  },
  timingRow: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  timingItem: { flex: 1, marginBottom: 0 },
  dateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: 'transparent',
    borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    padding: spacing.sm + 2,
    marginBottom: spacing.md,
  },
  dateContent: { flex: 1, minWidth: 0 },
  dateLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  dateValue: { color: colors.textPrimary, fontSize: fontSizes.sm },
  dateError: { color: colors.error, fontSize: fontSizes.xs, marginTop: -spacing.sm, marginBottom: spacing.md },
  durationRow: {
    backgroundColor: 'transparent',
    borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
    padding: spacing.sm + 2, marginBottom: spacing.md,
  },
  durationHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  durationPickers: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.sm },
  durationButton: {
    borderWidth: 1, borderColor: colors.borderStrong,
    borderRadius: radius.sm,
    width: 32, height: 32,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: 'transparent',
  },
  durationValue: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', textAlign: 'center', flex: 1 },
  nextButton: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 4, alignItems: 'center', marginTop: spacing.md },
  buttonDisabled: { opacity: 0.4 },
  nextText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  traceOptions: { flexDirection: 'column', gap: spacing.sm, marginBottom: spacing.md },
  traceButton: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm,
    backgroundColor: 'transparent', borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.cta,
    paddingVertical: spacing.sm + 2, marginBottom: spacing.md,
  },
  traceButtonText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  traceSetRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.cta + '15',
    borderWidth: 1, borderColor: colors.cta,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm + 2,
    marginBottom: spacing.md,
  },
  traceSetText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  traceStatsText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '600', marginTop: 2 },
  traceClearText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '700' },
});
