import { useState, useEffect, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet, Alert } from 'react-native';
import Slider from '@react-native-community/slider';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import { useRouter, Stack } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as Burnt from 'burnt';
import { X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { alertService } from '@/services/alert-service';
import { SportDropdown } from '@/components/sport-dropdown';
import { JuntoMapView } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useTutorialStore } from '@/store/tutorial-store';
import { TutorialTooltip } from '@/components/tutorial-tooltip';
import { getFriendlyError } from '@/utils/friendly-error';
import { LEVELS } from '@/types/activity-form';

export default function CreateAlertScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { center } = useInitialLocation();

  const [sportKeys, setSportKeys] = useState<string[]>([]);
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

  useEffect(() => {
    if (tutorialStep === 'click_alert') {
      if (!location) setLocation({ lng: center[0], lat: center[1] });
      setTutorialStep('set_radius');
    }
  }, [tutorialStep, location, center, setTutorialStep]);

  useEffect(() => {
    if (tutorialStep === 'set_radius' && radiusKm >= 200) {
      setTutorialStep('validate_alert');
    }
  }, [tutorialStep, radiusKm, setTutorialStep]);

  const toggleLevel = (l: string) => {
    setLevels((prev) => prev.includes(l) ? prev.filter((x) => x !== l) : [...prev, l]);
  };

  const toggleSport = (key: string) => {
    setSportKeys((prev) => prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key]);
  };

  const { data: alerts } = useQuery({
    queryKey: ['activity-alerts'],
    queryFn: () => alertService.getAll(),
  });

  const handleCreate = async () => {
    if (!location) return;
    setIsSaving(true);
    try {
      const startsStr = startsOn ? dayjs(startsOn).format('YYYY-MM-DD') : undefined;
      const endsStr = endsOn ? dayjs(endsOn).format('YYYY-MM-DD') : undefined;
      const lvls = levels.length > 0 ? levels : undefined;

      // 0 sports → one alert covering all sports.
      // N sports → one alert per sport (backend takes a single sport_key
      // per row, so multi-select is a fan-out at create time).
      if (sportKeys.length === 0) {
        await alertService.create(location.lng, location.lat, radiusKm, undefined, lvls, startsStr, endsStr);
      } else {
        await Promise.all(
          sportKeys.map((key) =>
            alertService.create(location.lng, location.lat, radiusKm, key, lvls, startsStr, endsStr),
          ),
        );
      }

      await queryClient.invalidateQueries({ queryKey: ['activity-alerts'] });
      Burnt.toast({ title: t('alerts.created'), preset: 'done' });
      setSportKeys([]);
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
    await queryClient.invalidateQueries({ queryKey: ['activity-alerts'] });
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

        <Pressable style={styles.mapPreview} onPress={() => setShowMap(true)}>
          <JuntoMapView
            center={location ? [location.lng, location.lat] : center}
            zoom={10}
            pins={location ? [{ id: 'alert-center', coordinate: [location.lng, location.lat], color: colors.cta }] : []}
          />
          <View style={styles.mapPreviewOverlay}>
            <Text style={styles.mapHintText}>
              {location ? '✓ ' + t('alerts.locationSet') : t('alerts.tapMap')}
            </Text>
          </View>
        </Pressable>

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
            maximumTrackTintColor={colors.borderMuted}
            thumbTintColor={colors.cta}
          />
          <View style={styles.sliderBounds}>
            <Text style={styles.sliderBoundText}>5 km</Text>
            <Text style={styles.sliderBoundText}>200 km</Text>
          </View>
        </View>

        <Text style={styles.label}>{t('alerts.sport')}</Text>
        <View style={styles.fieldPad}>
          <SportDropdown
            selected={sportKeys}
            onSelect={toggleSport}
            multiSelect
            label={t('alerts.anySport')}
          />
        </View>

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

        <Pressable
          style={[styles.createButton, (!location || isSaving) && styles.buttonDisabled]}
          onPress={handleCreate}
          disabled={!location || isSaving}
        >
          <Text style={styles.createText}>{isSaving ? '...' : t('alerts.create')}</Text>
        </Pressable>

        {(alerts ?? []).length > 0 && (
          <View style={styles.alertsList}>
            <Text style={styles.label}>{t('alerts.existing')}</Text>
            {(alerts ?? []).map((alert) => (
              <View key={alert.id} style={styles.alertRow}>
                <View style={styles.alertInfo}>
                  <Text style={styles.alertText} numberOfLines={2}>
                    {alert.sport_key ? t(`sports.${alert.sport_key}`, alert.sport_key) : t('alerts.anySport')}
                    {' · '}{alert.radius_km} km
                    {alert.levels && alert.levels.length > 0 ? ` · ${alert.levels.join(', ')}` : ''}
                    {alert.starts_on || alert.ends_on
                      ? ` · ${alert.starts_on ? dayjs(alert.starts_on).format('D MMM') : '…'}→${alert.ends_on ? dayjs(alert.ends_on).format('D MMM') : '…'}`
                      : ''}
                  </Text>
                </View>
                <Pressable onPress={() => handleDelete(alert.id)} hitSlop={6} style={styles.alertDeleteBtn}>
                  <X size={16} color={colors.error} strokeWidth={2.4} />
                </Pressable>
              </View>
            ))}
          </View>
        )}
      </ScrollView>

      <Modal visible={showMap} animationType="slide">
        <SafeAreaView style={styles.mapContainer} edges={['top', 'bottom']}>
          <JuntoMapView
            center={location ? [location.lng, location.lat] : center}
            zoom={10}
            pins={location ? [{ id: 'alert-center', coordinate: [location.lng, location.lat], color: colors.cta }] : []}
            onMapPress={(lng, lat) => setLocation({ lng, lat })}
          />

          {location ? (
            <Pressable style={styles.mapHintBar} onPress={() => setShowMap(false)}>
              <Text style={styles.mapHintBarText}>✓ {t('alerts.locationSet')}</Text>
            </Pressable>
          ) : (
            <View style={styles.mapHintBar} pointerEvents="none">
              <Text style={styles.mapHintBarText}>{t('alerts.tapMap')}</Text>
            </View>
          )}

          <Pressable style={styles.mapClose} onPress={() => setShowMap(false)}>
            <X size={18} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>
        </SafeAreaView>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { paddingBottom: spacing.xl + 32 },
  headerBlock: { paddingHorizontal: spacing.md, paddingTop: spacing.md, paddingBottom: spacing.sm },
  screenSubtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },

  // Map preview — flat, no shadow, bordered
  mapPreview: {
    height: 200,
    borderRadius: radius.sm,
    overflow: 'hidden',
    marginHorizontal: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  mapPreviewOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  mapHintText: {
    backgroundColor: colors.background,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderStrong,
  },

  // Radius
  radiusHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    paddingHorizontal: spacing.md,
    marginTop: spacing.md,
    marginBottom: spacing.sm,
  },
  labelInline: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  radiusValue: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '700' },
  sliderWrap: { paddingHorizontal: spacing.md },
  sliderBounds: { flexDirection: 'row', justifyContent: 'space-between', marginTop: -4 },
  sliderBoundText: { color: colors.textSecondary, fontSize: fontSizes.xs },

  // Section labels
  label: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    marginTop: spacing.md,
    paddingHorizontal: spacing.md,
  },

  fieldPad: { paddingHorizontal: spacing.md },

  // Brutalist outlined chips
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs + 2,
    paddingHorizontal: spacing.md,
  },
  chip: {
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    backgroundColor: 'transparent',
  },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  chipTextActive: { color: '#FFFFFF', fontWeight: '700' },

  // Create button
  createButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
    marginTop: spacing.lg,
    marginHorizontal: spacing.md,
  },
  buttonDisabled: { opacity: 0.4 },
  createText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },

  // Existing alerts — flat row pattern
  alertsList: { marginTop: spacing.lg, paddingHorizontal: spacing.md },
  alertRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  alertInfo: { flex: 1 },
  alertText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  alertDeleteBtn: {
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
  },

  // Fullscreen map modal
  mapContainer: { flex: 1, backgroundColor: colors.background },
  mapHintBar: {
    position: 'absolute',
    bottom: 150,
    left: spacing.md,
    right: spacing.md,
    alignItems: 'center',
  },
  mapHintBarText: {
    backgroundColor: colors.background,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderStrong,
  },
  mapClose: {
    position: 'absolute',
    top: spacing.xl + spacing.md,
    left: spacing.md,
    backgroundColor: colors.background,
    borderRadius: radius.sm,
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.borderStrong,
  },
  mapConfirm: {
    position: 'absolute',
    bottom: spacing.xl + 40,
    left: spacing.md,
    right: spacing.md,
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
  },
  mapConfirmText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});
