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
  Image,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Check, ImagePlus, Trash2 } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { proOfferingService } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { supabase } from '@/services/supabase';
import { getFriendlyError } from '@/utils/friendly-error';
import { LogoSpinner } from '@/components/logo-spinner';
import { JuntoMapView } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { SportDropdown } from '@/components/sport-dropdown';
import { LEVELS } from '@/types/activity-form';
import { pickAndUploadProOfferingImage, removeProOfferingImage } from '@/utils/pro-offering-image-upload';

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

  const { data: sports } = useQuery({
    queryKey: ['sports'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sports')
        .select('id, key, display_order')
        .order('display_order');
      if (error) throw error;
      return data ?? [];
    },
  });

  // Guard: only pros can be here. If the user lost pro tier or never
  // had a pro profile, bounce back. Server enforces this too.
  const { data: pro } = useQuery({
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
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [imageBusy, setImageBusy] = useState(false);
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
    setImageUrl(existing.image_url);
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

  const handlePickImage = async () => {
    if (imageBusy || !isEdit || !offeringId) {
      // Image upload requires an offering id (we upload under
      // {user_id}/offering/{id}/...). For create flow, defer image
      // upload until after save — the screen auto-redirects to edit
      // mode once the row exists.
      Alert.alert(
        t('proOffering.imageAfterSaveTitle'),
        t('proOffering.imageAfterSaveBody'),
      );
      return;
    }
    setImageBusy(true);
    try {
      const newUrl = await pickAndUploadProOfferingImage(offeringId);
      if (newUrl) {
        setImageUrl(newUrl);
        await queryClient.invalidateQueries({ queryKey: ['pro-offering', offeringId] });
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setImageBusy(false);
    }
  };

  const handleRemoveImage = async () => {
    if (imageBusy || !offeringId) return;
    setImageBusy(true);
    try {
      await removeProOfferingImage(offeringId);
      setImageUrl(null);
      await queryClient.invalidateQueries({ queryKey: ['pro-offering', offeringId] });
      await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setImageBusy(false);
    }
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
    if (!canSubmit || locationLng === null || locationLat === null) return;
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
        max_participants: maxParticipants ? parseInt(maxParticipants, 10) : null,
        schedule_text: scheduleText.trim() || null,
        distance_km: distanceKm ? parseFloat(distanceKm) : null,
        elevation_gain_m: elevationGainM ? parseInt(elevationGainM, 10) : null,
      };

      if (isEdit && offeringId) {
        await proOfferingService.update({ ...payload, offering_id: offeringId });
        await queryClient.invalidateQueries({ queryKey: ['pro-offering', offeringId] });
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        router.back();
      } else {
        const newId = await proOfferingService.create(payload);
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        // Redirect into edit mode for the newly-created row so the
        // image picker becomes available (it needs the row id to
        // namespace the upload path).
        router.replace(`/(auth)/pro/offering/edit?id=${newId}`);
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setSaving(false);
    }
  };

  if (!pro) {
    // Either still loading or not a pro. In either case nothing to
    // show; server enforces tier anyway so showing a spinner during
    // the brief loading window is safe.
    return (
      <SafeAreaView style={styles.center}>
        <LogoSpinner />
      </SafeAreaView>
    );
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

        {/* Banner image (edit mode only — needs the row id) */}
        {isEdit && (
          <View style={styles.bannerSection}>
            <Text style={styles.section}>{t('proOffering.image')}</Text>
            <Pressable
              style={styles.bannerSlot}
              onPress={handlePickImage}
              disabled={imageBusy}
            >
              {imageUrl ? (
                <Image source={{ uri: imageUrl }} style={styles.bannerImage} resizeMode="cover" />
              ) : (
                <View style={styles.bannerEmpty}>
                  <ImagePlus size={28} color={colors.textMuted} strokeWidth={2} />
                  <Text style={styles.bannerEmptyText}>{t('proOffering.imageAdd')}</Text>
                </View>
              )}
            </Pressable>
            {imageUrl && (
              <Pressable style={styles.bannerRemove} onPress={handleRemoveImage} disabled={imageBusy}>
                <Trash2 size={14} color={colors.error} strokeWidth={2} />
                <Text style={styles.bannerRemoveText}>{t('proOffering.imageRemove')}</Text>
              </Pressable>
            )}
          </View>
        )}

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

        <Pressable style={styles.locationButton} onPress={openMapPicker}>
          <Text style={styles.locationButtonText}>
            {locationLng !== null && locationLat !== null
              ? t('proOffering.locationPickAgain')
              : t('proOffering.locationPick')}
          </Text>
          {locationLng !== null && locationLat !== null && (
            <Text style={styles.locationCoords}>
              {locationLat.toFixed(4)}, {locationLng.toFixed(4)}
            </Text>
          )}
        </Pressable>

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

        <Pressable
          style={[styles.saveButton, !canSubmit && styles.saveButtonDisabled]}
          onPress={handleSubmit}
          disabled={!canSubmit}
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
  bannerSection: { marginBottom: spacing.md },
  bannerSlot: {
    aspectRatio: 3,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    overflow: 'hidden',
    backgroundColor: colors.surface,
  },
  bannerImage: { width: '100%', height: '100%' },
  bannerEmpty: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  bannerEmptyText: { color: colors.textMuted, fontSize: fontSizes.sm, marginTop: spacing.xs },
  bannerRemove: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    alignSelf: 'flex-start',
    marginTop: spacing.xs,
  },
  bannerRemoveText: { color: colors.error, fontSize: fontSizes.xs, fontWeight: '600' },
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
  locationButtonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  locationCoords: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: 2 },
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
