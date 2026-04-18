import { useState, useEffect } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet, Alert } from 'react-native';
import Slider from '@react-native-community/slider';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import { useRouter, Stack } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { alertService } from '@/services/alert-service';
import { SportDropdown } from '@/components/sport-dropdown';
import { JuntoMapView } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useTutorialStore } from '@/store/tutorial-store';
import { TutorialTooltip } from '@/components/tutorial-tooltip';
import { getFriendlyError } from '@/utils/friendly-error';
import { LEVELS } from '@/types/activity-form';

export default function CreateAlertScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { center } = useInitialLocation();

  const [sportKey, setSportKey] = useState<string>('');
  const [levels, setLevels] = useState<string[]>([]);
  const [radiusKm, setRadiusKm] = useState<number>(25);
  const [location, setLocation] = useState<{ lng: number; lat: number } | null>(null);
  const [showMap, setShowMap] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [startsOn, setStartsOn] = useState<Date | null>(null);
  const [endsOn, setEndsOn] = useState<Date | null>(null);
  const [showStartsPicker, setShowStartsPicker] = useState(false);
  const [showEndsPicker, setShowEndsPicker] = useState(false);
  const tutorialStep = useTutorialStore((s) => s.step);
  const setTutorialStep = useTutorialStore((s) => s.setStep);

  // Tutorial: on entering alert screen, advance to set_radius step
  useEffect(() => {
    if (tutorialStep === 'click_alert') {
      // Auto-fill location to user center so they can't fail
      if (!location) setLocation({ lng: center[0], lat: center[1] });
      setTutorialStep('set_radius');
    }
  }, [tutorialStep, location, center, setTutorialStep]);

  // When radius reaches max, advance
  useEffect(() => {
    if (tutorialStep === 'set_radius' && radiusKm >= 200) {
      setTutorialStep('validate_alert');
    }
  }, [tutorialStep, radiusKm, setTutorialStep]);

  const toggleLevel = (l: string) => {
    setLevels((prev) => prev.includes(l) ? prev.filter((x) => x !== l) : [...prev, l]);
  };

  const { data: alerts } = useQuery({
    queryKey: ['alerts'],
    queryFn: () => alertService.getAll(),
  });

  const handleCreate = async () => {
    if (!location) return;
    setIsSaving(true);
    try {
      await alertService.create(
        location.lng,
        location.lat,
        radiusKm,
        sportKey || undefined,
        levels.length > 0 ? levels : undefined,
        startsOn ? dayjs(startsOn).format('YYYY-MM-DD') : undefined,
        endsOn ? dayjs(endsOn).format('YYYY-MM-DD') : undefined,
      );
      await queryClient.invalidateQueries({ queryKey: ['alerts'] });
      Burnt.toast({ title: t('alerts.created'), preset: 'done' });
      setSportKey('');
      setLevels([]);
      setLocation(null);
      setStartsOn(null);
      setEndsOn(null);

      if (tutorialStep === 'validate_alert') {
        setTutorialStep('create_activity_hint');
        router.back();
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'createAlert'));
    } finally {
      setIsSaving(false);
    }
  };

  const handleDelete = async (alertId: string) => {
    await alertService.delete(alertId);
    await queryClient.invalidateQueries({ queryKey: ['alerts'] });
    Burnt.toast({ title: t('alerts.deleted') });
  };

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ headerTitle: t('alerts.title') }} />
      {tutorialStep === 'set_radius' && (
        <TutorialTooltip
          text={t('tutorial.setRadius')}
          position="bottom"
          anchor={{ top: 240, left: 24, right: 24 }}
        />
      )}
      {tutorialStep === 'validate_alert' && (
        <TutorialTooltip
          text={t('tutorial.validate')}
          position="bottom"
          anchor={{ bottom: 145, left: 24, right: 24 }}
        />
      )}
      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.headerBlock}>
          <Text style={styles.screenSubtitle}>{t('alerts.subtitle')}</Text>
        </View>
        {/* Map preview — tap to open fullscreen */}
        <Pressable style={styles.mapPreview} onPress={() => setShowMap(true)}>
          <JuntoMapView
            center={location ? [location.lng, location.lat] : center}
            zoom={10}
            pins={location ? [{ id: 'alert-center', coordinate: [location.lng, location.lat], color: '#F4642A' }] : []}
          />
          {/* Overlay blocks map touches, shows hint */}
          <View style={styles.mapPreviewOverlay}>
            <Text style={styles.mapHintText}>
              {location ? '✓ ' + t('alerts.locationSet') : t('alerts.tapMap')}
            </Text>
          </View>
        </Pressable>

        {/* Radius */}
        <View style={styles.radiusHeader}>
          <Text style={styles.labelInline}>{t('alerts.radius')}</Text>
          <Text style={styles.radiusValue}>{radiusKm} km</Text>
        </View>
        <View style={styles.sliderWrap}>
          <Slider
            minimumValue={5}
            maximumValue={200}
            step={5}
            value={radiusKm}
            onValueChange={setRadiusKm}
            minimumTrackTintColor={colors.cta}
            maximumTrackTintColor={colors.surface}
            thumbTintColor={colors.cta}
          />
          <View style={styles.sliderBounds}>
            <Text style={styles.sliderBoundText}>5 km</Text>
            <Text style={styles.sliderBoundText}>200 km</Text>
          </View>
        </View>

        {/* Sport (optional) */}
        <Text style={styles.label}>{t('alerts.sport')}</Text>
        <View style={styles.fieldPad}>
          <SportDropdown
            selected={sportKey}
            onSelect={(key) => setSportKey(sportKey === key ? '' : key)}
            label={t('alerts.anySport')}
          />
        </View>

        {/* Levels (optional, multi-select) */}
        <Text style={styles.label}>{t('alerts.level')}</Text>
        <View style={styles.chipRow}>
          {LEVELS.map((l) => {
            const active = levels.includes(l);
            return (
              <Pressable
                key={l}
                style={[styles.chip, active && styles.chipActive]}
                onPress={() => toggleLevel(l)}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>{l}</Text>
              </Pressable>
            );
          })}
        </View>

        {/* Period (optional) */}
        <Text style={styles.label}>{t('alerts.period')}</Text>
        <View style={styles.chipRow}>
          <Pressable style={[styles.chip, startsOn && styles.chipActive]} onPress={() => setShowStartsPicker(true)}>
            <Text style={[styles.chipText, startsOn && styles.chipTextActive]}>
              {startsOn ? dayjs(startsOn).format('D MMM YYYY') : t('alerts.from')}
            </Text>
          </Pressable>
          <Pressable style={[styles.chip, endsOn && styles.chipActive]} onPress={() => setShowEndsPicker(true)}>
            <Text style={[styles.chipText, endsOn && styles.chipTextActive]}>
              {endsOn ? dayjs(endsOn).format('D MMM YYYY') : t('alerts.to')}
            </Text>
          </Pressable>
          {(startsOn || endsOn) && (
            <Pressable style={styles.chip} onPress={() => { setStartsOn(null); setEndsOn(null); }}>
              <Text style={styles.chipText}>{t('alerts.clearPeriod')}</Text>
            </Pressable>
          )}
        </View>
        {showStartsPicker && (
          <DateTimePicker value={startsOn ?? new Date()} mode="date" minimumDate={new Date()} onChange={(_e, date) => {
            setShowStartsPicker(false);
            if (date) setStartsOn(date);
          }} />
        )}
        {showEndsPicker && (
          <DateTimePicker value={endsOn ?? startsOn ?? new Date()} mode="date" minimumDate={startsOn ?? new Date()} onChange={(_e, date) => {
            setShowEndsPicker(false);
            if (date) setEndsOn(date);
          }} />
        )}

        {/* Create button */}
        <Pressable
          style={[styles.createButton, (!location || isSaving) && styles.buttonDisabled]}
          onPress={handleCreate}
          disabled={!location || isSaving}
        >
          <Text style={styles.createText}>{isSaving ? '...' : t('alerts.create')}</Text>
        </Pressable>

        {/* Existing alerts */}
        {(alerts ?? []).length > 0 && (
          <View style={styles.alertsList}>
            <Text style={styles.label}>{t('alerts.existing')}</Text>
            {(alerts ?? []).map((alert) => (
              <View key={alert.id} style={styles.alertCard}>
                <View style={styles.alertInfo}>
                  <Text style={styles.alertText}>
                    {alert.sport_key ? t(`sports.${alert.sport_key}`, alert.sport_key) : t('alerts.anySport')}
                    {' · '}{alert.radius_km} km
                    {alert.levels && alert.levels.length > 0 ? ` · ${alert.levels.join(', ')}` : ''}
                    {alert.starts_on || alert.ends_on
                      ? ` · ${alert.starts_on ? dayjs(alert.starts_on).format('D MMM') : '…'}→${alert.ends_on ? dayjs(alert.ends_on).format('D MMM') : '…'}`
                      : ''}
                  </Text>
                </View>
                <Pressable onPress={() => handleDelete(alert.id)}>
                  <Text style={styles.deleteText}>✕</Text>
                </Pressable>
              </View>
            ))}
          </View>
        )}
      </ScrollView>

      {/* Fullscreen map modal */}
      <Modal visible={showMap} animationType="slide">
        <SafeAreaView style={styles.mapContainer} edges={['top', 'bottom']}>
          <JuntoMapView
            center={location ? [location.lng, location.lat] : center}
            zoom={10}
            pins={location ? [{ id: 'alert-center', coordinate: [location.lng, location.lat], color: '#F4642A' }] : []}
            onMapPress={(lng, lat) => setLocation({ lng, lat })}
          />

          {/* Hint overlay */}
          <View style={styles.mapHintBar} pointerEvents="none">
            <Text style={styles.mapHintText}>
              {location ? '✓ ' + t('alerts.locationSet') : t('alerts.tapMap')}
            </Text>
          </View>

          {/* Close button */}
          <Pressable style={styles.mapClose} onPress={() => setShowMap(false)}>
            <Text style={styles.mapCloseText}>✕</Text>
          </Pressable>

          {/* Confirm button */}
          {location && (
            <Pressable style={styles.mapConfirm} onPress={() => setShowMap(false)}>
              <Text style={styles.mapConfirmText}>✓ {t('alerts.confirmLocation')}</Text>
            </Pressable>
          )}
        </SafeAreaView>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { paddingBottom: spacing.xl + 32 },
  headerBlock: { paddingHorizontal: spacing.lg, paddingTop: spacing.md, paddingBottom: spacing.sm },
  screenSubtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  radiusHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', paddingHorizontal: spacing.lg, marginTop: spacing.md, marginBottom: spacing.sm },
  labelInline: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold', letterSpacing: 0.5, textTransform: 'uppercase' },
  radiusValue: { color: colors.cta, fontSize: fontSizes.md, fontWeight: 'bold' },
  sliderWrap: { paddingHorizontal: spacing.lg },
  sliderBounds: { flexDirection: 'row', justifyContent: 'space-between', marginTop: -4 },
  sliderBoundText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  label: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold', letterSpacing: 0.5, textTransform: 'uppercase', marginBottom: spacing.sm, marginTop: spacing.md, paddingHorizontal: spacing.lg },
  mapPreview: {
    height: 200, borderRadius: radius.lg, overflow: 'hidden', marginHorizontal: spacing.lg,
    elevation: 3, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.25, shadowRadius: 4,
  },
  mapPreviewOverlay: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.15)', alignItems: 'center', justifyContent: 'center' },
  fieldPad: { paddingHorizontal: spacing.lg },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs, paddingHorizontal: spacing.lg },
  chip: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  createButton: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xl, marginHorizontal: spacing.lg },
  buttonDisabled: { opacity: 0.4 },
  createText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  alertsList: { marginTop: spacing.xl, paddingHorizontal: spacing.lg },
  alertCard: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: colors.surface, borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.sm,
    elevation: 3, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.25, shadowRadius: 4,
  },
  alertInfo: { flex: 1 },
  alertText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  deleteText: { color: colors.error, fontSize: 16, fontWeight: 'bold', paddingHorizontal: spacing.sm },
  // Fullscreen map modal
  mapContainer: { flex: 1, backgroundColor: colors.background },
  mapHintBar: { position: 'absolute', bottom: 150, left: spacing.md, right: spacing.md, alignItems: 'center' },
  mapHintText: { backgroundColor: colors.background + 'E6', color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold', paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.full },
  mapClose: { position: 'absolute', top: spacing.xl + spacing.md, left: spacing.md, backgroundColor: colors.surface, borderRadius: radius.full, width: 36, height: 36, alignItems: 'center', justifyContent: 'center' },
  mapCloseText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  mapConfirm: { position: 'absolute', bottom: spacing.xl + 40, left: spacing.lg, right: spacing.lg, backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.md, alignItems: 'center' },
  mapConfirmText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
