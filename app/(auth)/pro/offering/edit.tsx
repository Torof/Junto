import { useState, useEffect, useMemo } from 'react';
import {
  View,
  Text,
  TextInput,
  Pressable,
  ScrollView,
  StyleSheet,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Modal,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams, Redirect } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Check, Trash2, MapPin } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { proOfferingService } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { useSports } from '@/hooks/use-sports';
import { getFriendlyError } from '@/utils/friendly-error';
import { LogoSpinner } from '@/components/logo-spinner';
import { JuntoMapView } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { SportDropdown } from '@/components/sport-dropdown';
import { LEVELS } from '@/types/activity-form';

// Single-screen form, mode keyed off the optional ?id= query param.
// New offering → empty form, calls create. Existing → pre-filled, calls
// update. Mirrors the pro/edit "register-or-update" pattern but for
// a per-row entity rather than the 1:1 pro_profiles row.
export default function ProOfferingEditScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { center } = useInitialLocation();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ id?: string }>();
  const offeringId = params.id;
  const isEdit = !!offeringId;

  const { data: sports } = useSports();

  // Guard: only pros can be here. If the user lost pro tier or never
  // had a pro profile, bounce back. Server enforces this too — this is
  // UX so a non-pro who lands on the URL doesn't sit on an infinite
  // spinner.
  const { data: pro, isLoading: isProLoading } = useQuery({
    queryKey: ['pro-profile-mine'],
    queryFn: () => proService.getMine(),
  });

  const { data: existing, isLoading } = useQuery({
    queryKey: ['pro-offering', offeringId],
    queryFn: () => proOfferingService.getById(offeringId!),
    enabled: isEdit,
  });

  const [sportId, setSportId] = useState<string>('');
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [level, setLevel] = useState<string>('');
  const [locationLng, setLocationLng] = useState<number | null>(null);
  const [locationLat, setLocationLat] = useState<number | null>(null);
  const [locationName, setLocationName] = useState('');
  const [durationHours, setDurationHours] = useState<string>('');
  const [durationMinutes, setDurationMinutes] = useState<string>('');
  const [maxParticipants, setMaxParticipants] = useState<string>('');
  const [scheduleText, setScheduleText] = useState('');
  const [distanceKm, setDistanceKm] = useState<string>('');
  const [elevationGainM, setElevationGainM] = useState<string>('');
  const [priceEur, setPriceEur] = useState<string>('');
  const [priceUnit, setPriceUnit] = useState<'person' | 'group'>('person');
  const [saving, setSaving] = useState(false);
  const [showMapPicker, setShowMapPicker] = useState(false);
  const [pickerPinLng, setPickerPinLng] = useState<number | null>(null);
  const [pickerPinLat, setPickerPinLat] = useState<number | null>(null);

  useEffect(() => {
    if (!existing) return;
    setSportId(existing.sport_id);
    setTitle(existing.title);
    setDescription(existing.description);
    setLevel(existing.level);
    setLocationLng(existing.lng);
    setLocationLat(existing.lat);
    setLocationName(existing.location_name);
    if (existing.duration) {
      // existing.duration is a Postgres interval serialized as e.g.
      // "02:30:00" or "1 day". For v1 we only support hh:mm so a
      // naive parser is enough; fancier interval support can come
      // when we surface "multi-day" offerings.
      const match = existing.duration.match(/^(\d+):(\d+):(\d+)/);
      if (match) {
        setDurationHours(match[1] ?? '');
        setDurationMinutes(match[2] ?? '');
      }
    }
    setMaxParticipants(existing.max_participants?.toString() ?? '');
    setScheduleText(existing.schedule_text ?? '');
    setDistanceKm(existing.distance_km?.toString() ?? '');
    setElevationGainM(existing.elevation_gain_m?.toString() ?? '');
    setPriceEur(existing.price_eur?.toString() ?? '');
    setPriceUnit(existing.price_unit ?? 'person');
  }, [existing]);

  const selectedSportKey = sports?.find((s) => s.id === sportId)?.key ?? '';

  const openMapPicker = () => {
    setPickerPinLng(locationLng);
    setPickerPinLat(locationLat);
    setShowMapPicker(true);
  };

  const confirmMapPick = () => {
    if (pickerPinLng !== null && pickerPinLat !== null) {
      setLocationLng(pickerPinLng);
      setLocationLat(pickerPinLat);
    }
    setShowMapPicker(false);
  };

  const handleDelete = () => {
    if (!offeringId) return;
    Alert.alert(
      t('proOffering.deleteConfirmTitle'),
      t('proOffering.deleteConfirmBody'),
      [
        { text: t('proOffering.cancel'), style: 'cancel' },
        {
          text: t('proOffering.delete'),
          style: 'destructive',
          onPress: async () => {
            try {
              await proOfferingService.remove(offeringId);
              await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
              router.back();
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
            }
          },
        },
      ],
    );
  };

  const parseDurationString = (): string | null => {
    const h = parseInt(durationHours, 10) || 0;
    const m = parseInt(durationMinutes, 10) || 0;
    if (h === 0 && m === 0) return null;
    return `${h} hours ${m} minutes`;
  };

  const canSubmit =
    sportId.length > 0 &&
    title.trim().length >= 3 &&
    description.length > 0 &&
    level.length > 0 &&
    locationLng !== null &&
    locationLat !== null &&
    locationName.trim().length >= 1 &&
    !saving;

  const handleSubmit = async () => {
    if (saving) return;
    // Incomplete → tell the user exactly what's missing instead of a dead button.
    if (!canSubmit || locationLng === null || locationLat === null) {
      const missing: string[] = [];
      if (!sportId) missing.push(t('proOffering.sport'));
      if (title.trim().length < 3) missing.push(t('proOffering.title'));
      if (description.length === 0) missing.push(t('proOffering.description'));
      if (level.length === 0) missing.push(t('proOffering.level'));
      if (locationLng === null || locationLat === null) {
        missing.push(t('proOffering.locationField', { defaultValue: 'Lieu sur la carte' }));
      }
      if (locationName.trim().length === 0) missing.push(t('proOffering.locationName'));
      Alert.alert(
        t('proOffering.incompleteTitle', { defaultValue: 'Informations manquantes' }),
        `${t('proOffering.incompleteBody', { defaultValue: 'À compléter avant de publier :' })}\n\n• ${missing.join('\n• ')}`,
      );
      return;
    }

    // Validate numeric fields client-side so an invalid value gets a clear
    // message instead of the DB's opaque generic rejection. Bounds mirror the
    // pro_offerings CHECK constraints (migration 00249).
    const parsedMax = maxParticipants ? parseInt(maxParticipants, 10) : null;
    const parsedDist = distanceKm ? parseFloat(distanceKm) : null;
    const parsedElev = elevationGainM ? parseInt(elevationGainM, 10) : null;
    if (parsedMax !== null && (!Number.isFinite(parsedMax) || parsedMax < 1 || parsedMax > 50)) {
      Alert.alert(t('auth.error'), t('proOffering.invalidParticipants', { defaultValue: 'Le nombre de participants doit être entre 1 et 50.' }));
      return;
    }
    if (parsedDist !== null && (!Number.isFinite(parsedDist) || parsedDist <= 0 || parsedDist > 9999)) {
      Alert.alert(t('auth.error'), t('proOffering.invalidDistance', { defaultValue: 'La distance doit être comprise entre 0 et 9999 km.' }));
      return;
    }
    if (parsedElev !== null && (!Number.isFinite(parsedElev) || parsedElev <= 0 || parsedElev > 99999)) {
      Alert.alert(t('auth.error'), t('proOffering.invalidElevation', { defaultValue: 'Le dénivelé doit être supérieur à 0.' }));
      return;
    }
    const parsedPrice = priceEur ? parseFloat(priceEur.replace(',', '.')) : null;
    if (parsedPrice !== null && (!Number.isFinite(parsedPrice) || parsedPrice <= 0 || parsedPrice > 99999)) {
      Alert.alert(t('auth.error'), t('proOffering.invalidPrice', { defaultValue: 'Le prix doit être compris entre 0 et 99 999 €.' }));
      return;
    }

    setSaving(true);
    try {
      const payload = {
        sport_id: sportId,
        title: title.trim(),
        description: description,
        level,
        location_lng: locationLng,
        location_lat: locationLat,
        location_name: locationName.trim(),
        duration: parseDurationString(),
        max_participants: parsedMax,
        schedule_text: scheduleText.trim() || null,
        distance_km: parsedDist,
        elevation_gain_m: parsedElev,
        // DB pairing constraint: both set or both NULL.
        price_eur: parsedPrice,
        price_unit: parsedPrice !== null ? priceUnit : null,
      };

      if (isEdit && offeringId) {
        await proOfferingService.update({ ...payload, offering_id: offeringId });
        await queryClient.invalidateQueries({ queryKey: ['pro-offering', offeringId] });
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        router.back();
      } else {
        const newId = await proOfferingService.create(payload);
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        // Land on the detail page so the freshly-created offering is
        // visible AND the user is one tap from the Photos tab where
        // they manage the gallery. (Edit-then-rewind-to-detail felt
        // longer than necessary.)
        router.replace(`/(auth)/pro/offering/${newId}`);
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setSaving(false);
    }
  };

  if (isProLoading) {
    return (
      <SafeAreaView style={styles.center}>
        <LogoSpinner />
      </SafeAreaView>
    );
  }
  if (!pro) {
    // Loaded but the user has no pro profile — they shouldn't be on
    // this screen. Bounce to the map; the create button on the pro
    // page is the canonical entry point.
    return <Redirect href="/(auth)/(tabs)/carte" />;
  }

  if (isEdit && isLoading) {
    return (
      <SafeAreaView style={styles.center}>
        <LogoSpinner />
      </SafeAreaView>
    );
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <Text style={styles.title}>
          {isEdit ? t('proOffering.editTitle') : t('proOffering.createTitle')}
        </Text>
        <Text style={styles.subtitle}>{t('proOffering.subtitle')}</Text>

        <Text style={styles.section}>{t('proOffering.sectionBasics')}</Text>

        <Field label={t('proOffering.sport')} styles={styles}>
          <SportDropdown
            selected={selectedSportKey}
            onSelect={(key) => {
              const s = sports?.find((sp) => sp.key === key);
              if (s) setSportId(s.id);
            }}
            label={t('proOffering.sport')}
          />
        </Field>

        <Field label={t('proOffering.title')} styles={styles}>
          <TextInput
            style={styles.input}
            value={title}
            onChangeText={setTitle}
            placeholder={t('proOffering.titlePlaceholder')}
            placeholderTextColor={colors.textMuted}
            maxLength={100}
          />
        </Field>

        <Field label={t('proOffering.description')} styles={styles}>
          <TextInput
            style={[styles.input, styles.textarea]}
            value={description}
            onChangeText={setDescription}
            placeholder={t('proOffering.descriptionPlaceholder')}
            placeholderTextColor={colors.textMuted}
            multiline
            maxLength={2000}
          />
        </Field>

        <Field label={t('proOffering.level')} styles={styles}>
          <View style={styles.levelRow}>
            {LEVELS.map((lvl) => (
              <Pressable
                key={lvl}
                style={[styles.levelChip, level === lvl && styles.levelChipActive]}
                onPress={() => setLevel(lvl)}
              >
                <Text style={[styles.levelChipText, level === lvl && styles.levelChipTextActive]}>
                  {lvl}
                </Text>
              </Pressable>
            ))}
          </View>
        </Field>

        <Text style={styles.section}>{t('proOffering.sectionLocation')}</Text>

        <Field label={t('proOffering.locationName')} styles={styles}>
          <TextInput
            style={styles.input}
            value={locationName}
            onChangeText={setLocationName}
            placeholder={t('proOffering.locationNamePlaceholder')}
            placeholderTextColor={colors.textMuted}
            maxLength={100}
          />
        </Field>

        <Field label={t('proOffering.locationField', { defaultValue: 'Lieu sur la carte' })} styles={styles}>
          <Pressable
            style={[
              styles.locationButton,
              locationLng !== null && locationLat !== null
                ? styles.locationButtonSet
                : styles.locationButtonRequired,
            ]}
            onPress={openMapPicker}
          >
            <View style={styles.locationButtonRow}>
              <MapPin
                size={18}
                color={locationLng !== null && locationLat !== null ? colors.success : colors.cta}
                strokeWidth={2.3}
              />
              <Text
                style={[
                  styles.locationButtonText,
                  (locationLng === null || locationLat === null) && styles.locationButtonTextRequired,
                ]}
              >
                {locationLng !== null && locationLat !== null
                  ? t('proOffering.locationPickAgain')
                  : t('proOffering.locationPick')}
              </Text>
              {locationLng !== null && locationLat !== null && (
                <Check size={18} color={colors.success} strokeWidth={2.6} style={styles.locationCheck} />
              )}
            </View>
            {locationLng !== null && locationLat !== null ? (
              <Text style={styles.locationCoords}>
                {locationLat.toFixed(4)}, {locationLng.toFixed(4)}
              </Text>
            ) : (
              <Text style={styles.locationHint}>
                {t('proOffering.locationRequired', { defaultValue: 'Obligatoire — touche pour placer le point' })}
              </Text>
            )}
          </Pressable>
        </Field>

        <Text style={styles.section}>{t('proOffering.sectionDetails')}</Text>

        <Field label={t('proOffering.schedule')} styles={styles}>
          <TextInput
            style={styles.input}
            value={scheduleText}
            onChangeText={setScheduleText}
            placeholder={t('proOffering.schedulePlaceholder')}
            placeholderTextColor={colors.textMuted}
            maxLength={100}
          />
          <Text style={styles.helper}>{t('proOffering.scheduleHelper')}</Text>
        </Field>

        <View style={styles.row2}>
          <Field label={t('proOffering.durationHours')} styles={styles}>
            <TextInput
              style={styles.input}
              value={durationHours}
              onChangeText={setDurationHours}
              placeholder="2"
              placeholderTextColor={colors.textMuted}
              keyboardType="number-pad"
              maxLength={2}
            />
          </Field>
          <Field label={t('proOffering.durationMinutes')} styles={styles}>
            <TextInput
              style={styles.input}
              value={durationMinutes}
              onChangeText={setDurationMinutes}
              placeholder="30"
              placeholderTextColor={colors.textMuted}
              keyboardType="number-pad"
              maxLength={2}
            />
          </Field>
        </View>

        <Field label={t('proOffering.maxParticipants')} styles={styles}>
          <TextInput
            style={styles.input}
            value={maxParticipants}
            onChangeText={setMaxParticipants}
            placeholder={t('proOffering.maxParticipantsPlaceholder')}
            placeholderTextColor={colors.textMuted}
            keyboardType="number-pad"
            maxLength={2}
          />
        </Field>

        <View style={styles.row2}>
          <Field label={t('proOffering.distance')} styles={styles}>
            <TextInput
              style={styles.input}
              value={distanceKm}
              onChangeText={setDistanceKm}
              placeholder="10"
              placeholderTextColor={colors.textMuted}
              keyboardType="decimal-pad"
              maxLength={6}
            />
          </Field>
          <Field label={t('proOffering.elevation')} styles={styles}>
            <TextInput
              style={styles.input}
              value={elevationGainM}
              onChangeText={setElevationGainM}
              placeholder="500"
              placeholderTextColor={colors.textMuted}
              keyboardType="number-pad"
              maxLength={5}
            />
          </Field>
        </View>

        <Field label={t('proOffering.price', { defaultValue: 'Prix indicatif (€)' })} styles={styles}>
          <View style={styles.priceRow}>
            <TextInput
              style={[styles.input, styles.priceInput]}
              value={priceEur}
              onChangeText={setPriceEur}
              placeholder="65"
              placeholderTextColor={colors.textMuted}
              keyboardType="decimal-pad"
              maxLength={6}
            />
            {(['person', 'group'] as const).map((unit) => (
              <Pressable
                key={unit}
                style={[styles.levelChip, priceEur !== '' && priceUnit === unit && styles.levelChipActive]}
                onPress={() => setPriceUnit(unit)}
                disabled={priceEur === ''}
              >
                <Text style={[styles.levelChipText, priceEur !== '' && priceUnit === unit && styles.levelChipTextActive]}>
                  {unit === 'person'
                    ? t('proOffering.pricePerPerson', { defaultValue: 'par pers.' })
                    : t('proOffering.pricePerGroup', { defaultValue: 'par groupe' })}
                </Text>
              </Pressable>
            ))}
          </View>
          <Text style={styles.helper}>
            {t('proOffering.priceHelper', { defaultValue: 'Affiché "À partir de X €". Laisse vide pour ne rien afficher.' })}
          </Text>
        </Field>

        <Pressable
          style={[styles.saveButton, !canSubmit && styles.saveButtonDisabled]}
          onPress={handleSubmit}
          disabled={saving}
        >
          <Text style={styles.saveButtonText}>
            {saving ? t('proOffering.saving') : isEdit ? t('proOffering.save') : t('proOffering.create')}
          </Text>
        </Pressable>

        {isEdit && (
          <Pressable style={styles.deleteButton} onPress={handleDelete}>
            <Trash2 size={16} color={colors.error} strokeWidth={2} />
            <Text style={styles.deleteButtonText}>{t('proOffering.delete')}</Text>
          </Pressable>
        )}
      </ScrollView>

      <Modal visible={showMapPicker} animationType="slide" onRequestClose={() => setShowMapPicker(false)}>
        <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
          <JuntoMapView
            center={
              pickerPinLng !== null && pickerPinLat !== null
                ? [pickerPinLng, pickerPinLat]
                : locationLng !== null && locationLat !== null
                  ? [locationLng, locationLat]
                  : center
            }
            zoom={12}
            onMapPress={(lng, lat) => {
              setPickerPinLng(lng);
              setPickerPinLat(lat);
            }}
            pins={
              pickerPinLng !== null && pickerPinLat !== null
                ? [{ id: 'offering-picker', coordinate: [pickerPinLng, pickerPinLat], color: colors.cta }]
                : []
            }
          />
          <Pressable
            style={styles.fullMapCloseBtn}
            onPress={() => setShowMapPicker(false)}
            hitSlop={8}
          >
            <Text style={styles.fullMapCloseText}>✕</Text>
          </Pressable>
          <Pressable
            style={[styles.fullMapConfirm, { bottom: insets.bottom + 24 }, pickerPinLng === null && styles.fullMapConfirmDisabled]}
            onPress={confirmMapPick}
            disabled={pickerPinLng === null}
          >
            <Check size={16} color={colors.textPrimary} strokeWidth={2.6} />
            <Text style={styles.fullMapConfirmText}>{t('proOffering.locationConfirm')}</Text>
          </Pressable>
        </SafeAreaView>
      </Modal>
    </KeyboardAvoidingView>
  );
}

function Field({
  label,
  children,
  styles,
}: {
  label: string;
  children: React.ReactNode;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      {children}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontFamily: fonts.title, marginBottom: spacing.xs },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.lg },
  section: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginTop: spacing.md,
    marginBottom: spacing.sm,
  },
  helper: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.xs },
  field: { marginBottom: spacing.md },
  fieldLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    marginBottom: spacing.xs,
  },
  input: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    padding: spacing.sm,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
  },
  textarea: { minHeight: 100, textAlignVertical: 'top' },
  row2: { flexDirection: 'row', gap: spacing.sm },
  levelRow: { flexDirection: 'row', gap: spacing.xs, flexWrap: 'wrap' },
  levelChip: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  levelChipActive: { borderColor: colors.cta, borderWidth: 2 },
  priceRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  priceInput: {
    flex: 1,
  },
  levelChipText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  levelChipTextActive: { color: colors.cta, fontWeight: '700' },
  locationButton: {
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    backgroundColor: colors.surface,
    marginBottom: spacing.md,
  },
  locationButtonRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  locationButtonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  locationButtonTextRequired: { color: colors.cta, fontWeight: '700' },
  locationButtonRequired: { borderColor: colors.cta, borderWidth: 1.5, backgroundColor: colors.cta + '12' },
  locationButtonSet: { borderColor: colors.success, backgroundColor: colors.success + '12' },
  locationCheck: { marginLeft: 'auto' },
  locationHint: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '600', marginTop: 4 },
  locationCoords: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: 4 },
  saveButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
    marginTop: spacing.lg,
  },
  saveButtonDisabled: { opacity: 0.5 },
  saveButtonText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
  deleteButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    marginTop: spacing.md,
  },
  deleteButtonText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '600' },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  fullMapCloseBtn: {
    position: 'absolute',
    top: spacing.sm + 4,
    right: spacing.md,
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fullMapCloseText: { color: colors.textPrimary, fontSize: 20 },
  fullMapConfirm: {
    position: 'absolute',
    left: spacing.lg,
    right: spacing.lg,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.sm,
    backgroundColor: colors.cta,
  },
  fullMapConfirmDisabled: { opacity: 0.5 },
  fullMapConfirmText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});
