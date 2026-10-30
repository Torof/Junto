import { useState, useEffect, useMemo } from 'react';
import {
  View,
  Pressable,
  ScrollView,
  StyleSheet,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Modal,
} from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams, Redirect } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { Check, Trash2, MapPin, ChevronDown, ChevronUp, Plus } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius, shadows, glow } from '@/constants/theme';
import { proOfferingService } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { useSports } from '@/hooks/use-sports';
import { getFriendlyError } from '@/utils/friendly-error';
import { LogoSpinner } from '@/components/logo-spinner';
import { JuntoMapView } from '@/components/map-view';
import { MapStyleButton } from '@/components/map-style-button';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { PressableScale } from '@/components/pressable-scale';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { SportDropdown } from '@/components/sport-dropdown';
import { OFFERING_LEVELS } from '@/types/pro-offering-form';
import { OPEN_LEVEL } from '@/constants/sport-levels';

// Single-screen form, mode keyed off the optional ?id= query param.
// New offering → empty form, calls create. Existing → pre-filled, calls
// update. Mirrors the pro/edit "register-or-update" pattern but for
// a per-row entity rather than the 1:1 pro_profiles row.
//
// Lot 2 pro (mockup validated 2026-10-15): two tempos on one screen —
// « L'essentiel » (sport, titre, deux lignes, lieu pré-rempli avec l'adresse
// du pro, durée en chips cohérentes avec matin / après-midi, prix) is enough
// to publish; « Détails » are collapsed groups, each openable, never blocking.

type DurationPreset = 'half' | 'day' | 'h2' | 'h3' | 'other';
const PRESET_MINUTES: Record<Exclude<DurationPreset, 'other'>, number> = { half: 240, day: 480, h2: 120, h3: 180 };
type DetailKey = 'level' | 'places' | 'gear' | 'form' | 'route';

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

  // Guard: only approved pros can be here (create_pro_offering requires
  // tier='pro', which only approve_pro grants). Server enforces this too —
  // this is UX so a non-pro who lands on the URL doesn't sit on a spinner.
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
  const [level, setLevel] = useState<string>(isEdit ? '' : OPEN_LEVEL);
  const [locationLng, setLocationLng] = useState<number | null>(null);
  const [locationLat, setLocationLat] = useState<number | null>(null);
  const [locationName, setLocationName] = useState('');
  const [durationPreset, setDurationPreset] = useState<DurationPreset | null>(null);
  const [durationHours, setDurationHours] = useState<string>('');
  const [durationMinutes, setDurationMinutes] = useState<string>('');
  const [minParticipants, setMinParticipants] = useState<string>('');
  const [maxParticipants, setMaxParticipants] = useState<string>('');
  const [scheduleText, setScheduleText] = useState('');
  const [distanceKm, setDistanceKm] = useState<string>('');
  const [elevationGainM, setElevationGainM] = useState<string>('');
  const [priceEur, setPriceEur] = useState<string>('');
  const [priceUnit, setPriceUnit] = useState<'person' | 'group'>('person');
  const [saving, setSaving] = useState(false);
  // Chantiers A+B (00422) : matériel + fiche participant demandée.
  const [equipProvided, setEquipProvided] = useState<string[]>([]);
  const [equipRequired, setEquipRequired] = useState<string[]>([]);
  const [equipProvidedDraft, setEquipProvidedDraft] = useState('');
  const [equipRequiredDraft, setEquipRequiredDraft] = useState('');
  const [pStd, setPStd] = useState<string[]>([]);
  const [pCustom, setPCustom] = useState<string[]>([]);
  const [pCustomDraft, setPCustomDraft] = useState('');
  const [showMapPicker, setShowMapPicker] = useState(false);
  const [pickerPinLng, setPickerPinLng] = useState<number | null>(null);
  const [pickerPinLat, setPickerPinLat] = useState<number | null>(null);
  const [openDetails, setOpenDetails] = useState<Record<DetailKey, boolean>>({
    level: false, places: false, gear: false, form: false, route: false,
  });
  const toggleDetail = (k: DetailKey) => setOpenDetails((o) => ({ ...o, [k]: !o[k] }));

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
      // Postgres serializes the interval as "02:30:00", "1 day", or
      // "1 day 02:00:00" (≥ 24 h, e.g. seeded in SQL). Fold days into hours.
      const days = existing.duration.match(/(\d+)\s+days?/);
      const hms = existing.duration.match(/(\d+):(\d+):(\d+)/);
      const hours = (days ? parseInt(days[1] ?? '0', 10) * 24 : 0) + (hms ? parseInt(hms[1] ?? '0', 10) : 0);
      const minutes = hms ? parseInt(hms[2] ?? '0', 10) : 0;
      const total = hours * 60 + minutes;
      const preset = (Object.keys(PRESET_MINUTES) as Exclude<DurationPreset, 'other'>[]).find((k) => PRESET_MINUTES[k] === total);
      if (preset) setDurationPreset(preset);
      else if (total > 0) {
        setDurationPreset('other');
        setDurationHours(hours > 0 ? String(hours) : '');
        setDurationMinutes(minutes > 0 ? String(minutes) : '');
      }
    }
    setMinParticipants(existing.min_participants?.toString() ?? '');
    setMaxParticipants(existing.max_participants?.toString() ?? '');
    setScheduleText(existing.schedule_text ?? '');
    setDistanceKm(existing.distance_km?.toString() ?? '');
    setElevationGainM(existing.elevation_gain_m?.toString() ?? '');
    setPriceEur(existing.price_eur?.toString() ?? '');
    setPriceUnit(existing.price_unit ?? 'person');
    setEquipProvided(existing.equipment_provided ?? []);
    setEquipRequired(existing.equipment_required ?? []);
    setPStd(existing.participant_fields?.std ?? []);
    setPCustom(existing.participant_fields?.custom ?? []);
  }, [existing]);

  // New outing: the meeting place defaults to the pro's own address — most
  // outings leave from the shop, and the pro can retype or drag otherwise.
  useEffect(() => {
    if (isEdit || !pro || locationLng !== null) return;
    setLocationLng(pro.primary_lng);
    setLocationLat(pro.primary_lat);
    setLocationName((cur) => cur || pro.primary_location_name);
  }, [isEdit, pro, locationLng]);

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
              // back() landed on the deleted offering's page (« introuvable »,
              // second back needed). Unwind to the pro page instead.
              if (pro?.user_id) router.dismissTo(`/(auth)/pro/${pro.user_id}`);
              else router.back();
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
            }
          },
        },
      ],
    );
  };

  const durationMinutesTotal = (): number => {
    if (durationPreset && durationPreset !== 'other') return PRESET_MINUTES[durationPreset];
    if (durationPreset === 'other') {
      return (parseInt(durationHours, 10) || 0) * 60 + (parseInt(durationMinutes, 10) || 0);
    }
    return 0;
  };
  const parseDurationString = (): string | null => {
    const total = durationMinutesTotal();
    if (total === 0) return null;
    return `${Math.floor(total / 60)} hours ${total % 60} minutes`;
  };

  // Tag inputs commit on the keyboard's "done", on blur and on the « + »
  // button — Android often shows "→" instead of "OK", and a tap elsewhere
  // used to lose the draft.
  const commitProvided = () => {
    const v = equipProvidedDraft.trim();
    if (v && equipProvided.length < 15) { setEquipProvided([...equipProvided, v]); setEquipProvidedDraft(''); }
  };
  const commitRequired = () => {
    const v = equipRequiredDraft.trim();
    if (v && equipRequired.length < 15) { setEquipRequired([...equipRequired, v]); setEquipRequiredDraft(''); }
  };
  const commitCustom = () => {
    const v = pCustomDraft.trim();
    if (v && pCustom.length < 3) { setPCustom([...pCustom, v]); setPCustomDraft(''); }
  };

  const canSubmit =
    sportId.length > 0 &&
    title.trim().length >= 3 &&
    description.trim().length > 0 &&
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
      if (description.trim().length === 0) missing.push(t('proOffering.descShort', { defaultValue: 'En deux lignes' }));
      if (level.length === 0) missing.push(t('proOffering.level'));
      if (locationLng === null || locationLat === null || locationName.trim().length === 0) {
        missing.push(t('proOffering.meetingPlace', { defaultValue: 'Lieu de rendez-vous' }));
      }
      Alert.alert(
        t('proOffering.incompleteTitle', { defaultValue: 'Informations manquantes' }),
        `${t('proOffering.incompleteBody', { defaultValue: 'À compléter avant de publier :' })}\n\n• ${missing.join('\n• ')}`,
      );
      return;
    }

    // Validate numeric fields client-side so an invalid value gets a clear
    // message instead of the DB's opaque generic rejection. Bounds mirror the
    // pro_offerings CHECK constraints (migration 00249).
    const parsedMin = minParticipants ? parseInt(minParticipants, 10) : null;
    const parsedMax = maxParticipants ? parseInt(maxParticipants, 10) : null;
    const parsedDist = distanceKm ? parseFloat(distanceKm) : null;
    const parsedElev = elevationGainM ? parseInt(elevationGainM, 10) : null;
    if (parsedMax !== null && (!Number.isFinite(parsedMax) || parsedMax < 1 || parsedMax > 50)) {
      Alert.alert(t('auth.error'), t('proOffering.invalidParticipants', { defaultValue: 'Le nombre de participants doit être entre 1 et 50.' }));
      return;
    }
    if (parsedMin !== null && (!Number.isFinite(parsedMin) || parsedMin < 1 || parsedMin > 50)) {
      Alert.alert(t('auth.error'), t('proOffering.invalidParticipants', { defaultValue: 'Le nombre de participants doit être entre 1 et 50.' }));
      return;
    }
    if (parsedMin !== null && parsedMax !== null && parsedMin > parsedMax) {
      Alert.alert(t('auth.error'), t('proOffering.invalidMinMax', { defaultValue: 'Le minimum ne peut pas dépasser le maximum.' }));
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
    if (durationPreset === 'other' && (parseInt(durationMinutes, 10) || 0) > 59) {
      Alert.alert(t('auth.error'), t('proOffering.invalidDuration', { defaultValue: 'Les minutes vont de 0 à 59.' }));
      return;
    }

    // Flush the tag drafts the pro typed without validating.
    const finalProvided = equipProvidedDraft.trim() && equipProvided.length < 15
      ? [...equipProvided, equipProvidedDraft.trim()] : equipProvided;
    const finalRequired = equipRequiredDraft.trim() && equipRequired.length < 15
      ? [...equipRequired, equipRequiredDraft.trim()] : equipRequired;
    const finalCustom = pCustomDraft.trim() && pCustom.length < 3
      ? [...pCustom, pCustomDraft.trim()] : pCustom;

    setSaving(true);
    try {
      const payload = {
        sport_id: sportId,
        title: title.trim(),
        description: description.trim(),
        level,
        location_lng: locationLng,
        location_lat: locationLat,
        location_name: locationName.trim(),
        duration: parseDurationString(),
        min_participants: parsedMin,
        max_participants: parsedMax,
        schedule_text: scheduleText.trim() || null,
        distance_km: parsedDist,
        elevation_gain_m: parsedElev,
        // DB pairing constraint: both set or both NULL.
        price_eur: parsedPrice,
        price_unit: parsedPrice !== null ? priceUnit : null,
      };

      // Two RPCs (offer, then equipment/participant form). If the second
      // fails the offer already exists: never leave the pro on the form with
      // an error — a second « Publier » duplicated the offer. Land on the
      // offer and say what did not save.
      const saveDetails = async (id: string) => {
        try {
          await proOfferingService.setDetails(id, finalProvided, finalRequired, pStd, finalCustom);
        } catch {
          Burnt.toast({
            title: t('proOffering.detailsNotSaved', { defaultValue: 'Offre enregistrée, mais pas le matériel / la fiche — réessaie depuis Modifier.' }),
            preset: 'error',
          });
        }
      };
      if (isEdit && offeringId) {
        await proOfferingService.update({ ...payload, offering_id: offeringId });
        await saveDetails(offeringId);
        await queryClient.invalidateQueries({ queryKey: ['pro-offering', offeringId] });
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        router.back();
      } else {
        const newId = await proOfferingService.create(payload);
        await saveDetails(newId);
        await queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        // Land on the detail page so the freshly-created offering is
        // visible AND the user is one tap from the Photos tab.
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
  if (!pro || pro.status !== 'approved') {
    return <Redirect href="/(auth)/(tabs)/carte" />;
  }

  if (isEdit && isLoading) {
    return (
      <SafeAreaView style={styles.center}>
        <LogoSpinner />
      </SafeAreaView>
    );
  }

  // Summaries shown on collapsed detail rows (the current value, readable).
  const levelSummary = level || OPEN_LEVEL;
  const placesSummary = minParticipants && maxParticipants
    ? t('proOffering.placesRange', { defaultValue: '{{min}} à {{max}}', min: minParticipants, max: maxParticipants })
    : maxParticipants
      ? t('proOffering.placesUpTo', { defaultValue: 'jusqu’à {{count}}', count: Number(maxParticipants) })
      : t('proOffering.placesAny', { defaultValue: 'Sans limite' });
  const gearSummary = equipProvided.length + equipRequired.length > 0
    ? `${equipProvided.length + equipRequired.length}`
    : '—';
  const formSummary = pStd.length + pCustom.length > 0 ? `${pStd.length + pCustom.length}` : '—';
  const routeSummary = [distanceKm && `${distanceKm} km`, elevationGainM && `${elevationGainM} m D+`, scheduleText.trim()]
    .filter(Boolean).join(' · ') || '—';

  const DetailRow = ({ k, label, summary }: { k: DetailKey; label: string; summary: string }) => (
    <Pressable style={styles.detailRow} onPress={() => toggleDetail(k)} accessibilityRole="button">
      <AppText style={styles.detailLabel}>{label}</AppText>
      <AppText style={styles.detailSummary} numberOfLines={1}>{summary}</AppText>
      {openDetails[k]
        ? <ChevronUp size={18} color={colors.textMuted} strokeWidth={2.2} />
        : <ChevronDown size={18} color={colors.textMuted} strokeWidth={2.2} />}
    </Pressable>
  );

  const TagList = ({ items, onRemove, tint }: { items: string[]; onRemove: (i: number) => void; tint: boolean }) => (
    <View style={styles.tagsWrap}>
      {items.map((it, i) => (
        <Pressable key={`${it}${i}`} style={[styles.tag, tint && styles.tagTint]} onPress={() => onRemove(i)}>
          <AppText style={styles.tagText}>{it}</AppText>
          <AppText style={styles.tagX}>✕</AppText>
        </Pressable>
      ))}
    </View>
  );

  // Plain render helper, NOT a component: a component defined in render is
  // remounted at every keystroke and the TextInput loses focus.
  const renderTagInput = ({ value, onChange, onCommit, placeholder, label, primary }: {
    value: string; onChange: (v: string) => void; onCommit: () => void; placeholder: string; label: string; primary: boolean;
  }) => (
    <View style={styles.tagInputRow}>
      <AppTextInput
        style={[styles.input, { flex: 1 }]}
        value={value}
        onChangeText={onChange}
        placeholder={placeholder}
        placeholderTextColor={colors.textMuted}
        maxLength={80}
        onSubmitEditing={onCommit}
        onBlur={onCommit}
        blurOnSubmit={false}
        returnKeyType="done"
        accessibilityLabel={label}
      />
      <Pressable
        style={[styles.addBtn, primary && styles.addBtnPrimary]}
        onPress={onCommit}
        accessibilityLabel={t('proOffering.addTag', { defaultValue: 'Ajouter' })}
      >
        <Plus size={18} color={primary ? colors.onCta : colors.textPrimary} strokeWidth={2.8} />
      </Pressable>
    </View>
  );

  const durationChips: { key: DurationPreset; label: string }[] = [
    { key: 'half', label: t('proOffering.durHalf', { defaultValue: 'Demi-journée' }) },
    { key: 'day', label: t('proOffering.durDay', { defaultValue: 'Journée' }) },
    { key: 'h2', label: t('proOffering.dur2h', { defaultValue: '2 h' }) },
    { key: 'h3', label: t('proOffering.dur3h', { defaultValue: '3 h' }) },
    { key: 'other', label: t('proOffering.durOther', { defaultValue: 'Autre…' }) },
  ];

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <AppText style={styles.title}>
          {isEdit
            ? t('proOffering.editOutingTitle', { defaultValue: 'Modifier la sortie' })
            : t('proOffering.newOutingTitle', { defaultValue: 'Nouvelle sortie' })}
        </AppText>
        <AppText style={styles.subtitle}>
          {t('proOffering.essentialsHint', { defaultValue: 'L’essentiel suffit pour publier. Les détails sont optionnels.' })}
        </AppText>

        {/* ---------- L'essentiel ---------- */}
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
          <AppTextInput
            style={styles.input}
            value={title}
            onChangeText={setTitle}
            placeholder={t('proOffering.titlePlaceholder')}
            placeholderTextColor={colors.textMuted}
            maxLength={100}
          />
        </Field>

        <Field label={t('proOffering.descShort', { defaultValue: 'En deux lignes' })} styles={styles}>
          <AppTextInput
            style={[styles.input, styles.textarea]}
            value={description}
            onChangeText={setDescription}
            placeholder={t('proOffering.descShortPlaceholder', { defaultValue: 'Ce qu’on fait, pour qui, ce qui est fourni.' })}
            placeholderTextColor={colors.textMuted}
            multiline
            maxLength={2000}
          />
        </Field>

        <Field label={t('proOffering.meetingPlace', { defaultValue: 'Lieu de rendez-vous' })} styles={styles}>
          <PlaceSearchBar
            bias={pro ? { lat: pro.primary_lat, lng: pro.primary_lng } : null}
            onSelect={(place) => {
              setLocationLng(place.lng);
              setLocationLat(place.lat);
              setLocationName([place.label, place.sublabel.split(', ')[0]].filter((x): x is string => !!x).join(', ').slice(0, 100));
            }}
          />
          <View style={styles.placeRow}>
            <MapPin size={16} color={locationLng !== null ? colors.cta : colors.textMuted} strokeWidth={2.4} />
            <AppTextInput
              style={[styles.input, { flex: 1 }]}
              value={locationName}
              onChangeText={setLocationName}
              placeholder={t('proOffering.locationNamePlaceholder')}
              placeholderTextColor={colors.textMuted}
              maxLength={100}
            />
            <Pressable style={styles.adjustBtn} onPress={openMapPicker} hitSlop={6}>
              <AppText style={styles.adjustBtnText}>{t('proOffering.adjustOnMap', { defaultValue: 'Carte' })}</AppText>
            </Pressable>
          </View>
          <AppText style={styles.helper}>
            {isEdit
              ? t('proOffering.meetingPlaceHintEdit', { defaultValue: 'Tape un lieu pour changer, ou ajuste sur la carte.' })
              : t('proOffering.meetingPlaceHint', { defaultValue: 'Ton adresse, par défaut. Tape pour changer, ou ajuste sur la carte.' })}
          </AppText>
        </Field>

        <Field label={t('proOffering.duration', { defaultValue: 'Durée' })} styles={styles}>
          <View style={styles.chipRow}>
            {durationChips.map((c) => {
              const on = durationPreset === c.key;
              return (
                <Pressable key={c.key} style={[styles.chip, on && styles.chipOn]} onPress={() => setDurationPreset(on ? null : c.key)}>
                  <AppText style={[styles.chipText, on && styles.chipTextOn]}>{c.label}</AppText>
                </Pressable>
              );
            })}
          </View>
          {durationPreset === 'other' && (
            <View style={[styles.row2, { marginTop: spacing.sm }]}>
              <AppTextInput
                style={[styles.input, { flex: 1 }]}
                value={durationHours}
                onChangeText={setDurationHours}
                placeholder={t('proOffering.durationHours')}
                placeholderTextColor={colors.textMuted}
                keyboardType="number-pad"
                maxLength={2}
              />
              <AppTextInput
                style={[styles.input, { flex: 1 }]}
                value={durationMinutes}
                onChangeText={setDurationMinutes}
                placeholder={t('proOffering.durationMinutes')}
                placeholderTextColor={colors.textMuted}
                keyboardType="number-pad"
                maxLength={2}
              />
            </View>
          )}
        </Field>

        <Field label={`${t('proOffering.price', { defaultValue: 'Prix indicatif (€)' })} ${t('proOffering.optionalMark', { defaultValue: '· optionnel' })}`} styles={styles}>
          <View style={styles.priceRow}>
            <AppTextInput
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
                style={[styles.chip, priceEur !== '' && priceUnit === unit && styles.chipOn]}
                onPress={() => setPriceUnit(unit)}
                disabled={priceEur === ''}
              >
                <AppText style={[styles.chipText, priceEur !== '' && priceUnit === unit && styles.chipTextOn]}>
                  {unit === 'person'
                    ? t('proOffering.pricePerPerson', { defaultValue: 'par pers.' })
                    : t('proOffering.pricePerGroup', { defaultValue: 'par groupe' })}
                </AppText>
              </Pressable>
            ))}
          </View>
        </Field>

        {/* ---------- Détails (repliés) ---------- */}
        <AppText style={styles.section}>{t('proOffering.detailsTitle', { defaultValue: 'Détails' })}</AppText>
        <AppText style={styles.helper}>{t('proOffering.detailsHint', { defaultValue: 'Tout est optionnel · ouvre ce qui te sert' })}</AppText>

        <DetailRow k="level" label={t('proOffering.level')} summary={levelSummary} />
        {openDetails.level && (
          <View style={styles.detailBody}>
            <View style={styles.chipRow}>
              {OFFERING_LEVELS.map((lvl) => (
                <Pressable key={lvl} style={[styles.chip, level === lvl && styles.chipOn]} onPress={() => setLevel(lvl)}>
                  <AppText style={[styles.chipText, level === lvl && styles.chipTextOn]}>{lvl}</AppText>
                </Pressable>
              ))}
            </View>
          </View>
        )}

        <DetailRow k="places" label={t('proOffering.secPlaces', { defaultValue: 'Places' })} summary={placesSummary} />
        {openDetails.places && (
          <View style={styles.detailBody}>
            <View style={styles.row2}>
              <Field label={t('proOffering.minParticipants', { defaultValue: 'Participants min' })} styles={styles}>
                <AppTextInput style={styles.input} value={minParticipants} onChangeText={setMinParticipants} placeholder="4" placeholderTextColor={colors.textMuted} keyboardType="number-pad" maxLength={2} />
              </Field>
              <Field label={t('proOffering.maxParticipants')} styles={styles}>
                <AppTextInput style={styles.input} value={maxParticipants} onChangeText={setMaxParticipants} placeholder={t('proOffering.maxParticipantsPlaceholder')} placeholderTextColor={colors.textMuted} keyboardType="number-pad" maxLength={2} />
              </Field>
            </View>
          </View>
        )}

        <DetailRow k="gear" label={t('proOffering.sectionEquipment', { defaultValue: 'Matériel' })} summary={gearSummary} />
        {openDetails.gear && (
          <View style={styles.detailBody}>
            <AppText style={styles.fieldLabel}>{t('proOffering.equipProvided', { defaultValue: 'Fourni par toi' })}</AppText>
            <TagList items={equipProvided} onRemove={(i) => setEquipProvided(equipProvided.filter((_, j) => j !== i))} tint />
            {renderTagInput({ value: equipProvidedDraft, onChange: setEquipProvidedDraft, onCommit: commitProvided, placeholder: t('proOffering.equipAddPlaceholderShort', { defaultValue: 'Ex. : baudrier' }), label: t('proOffering.equipProvided', { defaultValue: 'Fourni par toi' }), primary: true })}
            <AppText style={[styles.fieldLabel, { marginTop: spacing.md }]}>{t('proOffering.equipRequired', { defaultValue: 'À apporter par le client' })}</AppText>
            <TagList items={equipRequired} onRemove={(i) => setEquipRequired(equipRequired.filter((_, j) => j !== i))} tint={false} />
            {renderTagInput({ value: equipRequiredDraft, onChange: setEquipRequiredDraft, onCommit: commitRequired, placeholder: t('proOffering.equipAddPlaceholderReq', { defaultValue: 'Ex. : gants' }), label: t('proOffering.equipRequired', { defaultValue: 'À apporter par le client' }), primary: false })}
            <AppText style={styles.helper}>{t('proOffering.equipHelper', { defaultValue: 'Affiché sur l’offre et rappelé au client sur sa réservation.' })}</AppText>
          </View>
        )}

        <DetailRow k="form" label={t('proOffering.sectionParticipantForm', { defaultValue: 'Fiche participant' })} summary={formSummary} />
        {openDetails.form && (
          <View style={styles.detailBody}>
            <AppText style={styles.helper}>
              {t('proOffering.participantFormHelper', { defaultValue: 'Ce que tu dois savoir sur chaque participant. Le client remplit après confirmation.' })}
            </AppText>
            {([['shoe_size', t('booking.fShoe', { defaultValue: 'Pointure' })],
               ['height', t('booking.fHeight', { defaultValue: 'Taille' })],
               ['weight', t('booking.fWeight', { defaultValue: 'Poids' })],
               ['age', t('booking.fAge', { defaultValue: 'Âge' })],
               ['level', t('booking.fLevel', { defaultValue: 'Niveau' })]] as const).map(([code, label]) => {
              const on = pStd.includes(code);
              return (
                <Pressable
                  key={code}
                  style={styles.checkRow}
                  onPress={() => setPStd(on ? pStd.filter((c) => c !== code) : [...pStd, code])}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: on }}
                >
                  <View style={[styles.checkBox, on && styles.checkBoxOn]}>
                    {on ? <AppText style={styles.checkMark}>✓</AppText> : null}
                  </View>
                  <AppText style={styles.checkLabel}>{label}</AppText>
                </Pressable>
              );
            })}
            {pCustom.map((q, i) => (
              <Pressable key={`${q}${i}`} style={styles.checkRow} onPress={() => setPCustom(pCustom.filter((_, j) => j !== i))}>
                <View style={[styles.checkBox, styles.checkBoxOn]}><AppText style={styles.checkMark}>✓</AppText></View>
                <AppText style={styles.checkLabel} numberOfLines={1}>{q}</AppText>
                <AppText style={styles.tagX}>✕</AppText>
              </Pressable>
            ))}
            {pCustom.length < 3 ? (
              renderTagInput({ value: pCustomDraft, onChange: setPCustomDraft, onCommit: commitCustom, placeholder: t('proOffering.customQuestionPlaceholderShort', { defaultValue: 'Question libre — ex. : « Sais-tu nager 25 m ? »' }), label: t('proOffering.sectionParticipantForm', { defaultValue: 'Fiche participant' }), primary: false })
            ) : null}
          </View>
        )}

        <DetailRow k="route" label={t('proOffering.secRoute', { defaultValue: 'Parcours et horaires' })} summary={routeSummary} />
        {openDetails.route && (
          <View style={styles.detailBody}>
            <View style={styles.row2}>
              <Field label={t('proOffering.distance')} styles={styles}>
                <AppTextInput style={styles.input} value={distanceKm} onChangeText={setDistanceKm} placeholder="10" placeholderTextColor={colors.textMuted} keyboardType="decimal-pad" maxLength={6} />
              </Field>
              <Field label={t('proOffering.elevation')} styles={styles}>
                <AppTextInput style={styles.input} value={elevationGainM} onChangeText={setElevationGainM} placeholder="500" placeholderTextColor={colors.textMuted} keyboardType="number-pad" maxLength={5} />
              </Field>
            </View>
            <Field label={t('proOffering.schedule')} styles={styles}>
              <AppTextInput style={styles.input} value={scheduleText} onChangeText={setScheduleText} placeholder={t('proOffering.schedulePlaceholder')} placeholderTextColor={colors.textMuted} maxLength={100} />
              <AppText style={styles.helper}>{t('proOffering.scheduleHelper')}</AppText>
            </Field>
          </View>
        )}

        {isEdit && (
          <Pressable style={styles.deleteButton} onPress={handleDelete}>
            <Trash2 size={16} color={colors.error} strokeWidth={2} />
            <AppText style={styles.deleteButtonText}>{t('proOffering.delete')}</AppText>
          </Pressable>
        )}
      </ScrollView>

      {/* Sticky primary action — always one thumb away. */}
      <View style={[styles.ctaBar, { paddingBottom: Math.max(insets.bottom, spacing.sm) + spacing.sm }]}>
        <PressableScale
          style={[styles.cta, !canSubmit && styles.ctaDisabled, canSubmit && glow(colors.brand)]}
          onPress={handleSubmit}
          disabled={saving}
        >
          <AppText style={styles.ctaText}>
            {saving
              ? t('proOffering.saving')
              : isEdit
                ? t('proOffering.save')
                : t('proOffering.publish', { defaultValue: 'Publier la sortie' })}
          </AppText>
        </PressableScale>
      </View>

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
            <AppText style={styles.fullMapCloseText}>✕</AppText>
          </Pressable>
          <MapStyleButton scope="secondary" style={styles.fullMapStyleButton} />
          <Pressable
            style={[styles.fullMapConfirm, { bottom: insets.bottom + 24 }, pickerPinLng === null && styles.fullMapConfirmDisabled]}
            onPress={confirmMapPick}
            disabled={pickerPinLng === null}
          >
            <Check size={16} color={colors.onCta} strokeWidth={2.6} />
            <AppText style={styles.fullMapConfirmText}>{t('proOffering.locationConfirm')}</AppText>
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
      <AppText style={styles.fieldLabel}>{label}</AppText>
      {children}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl * 3 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontFamily: fonts.title, marginBottom: spacing.xs },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.lg },
  section: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '800',
    marginTop: spacing.lg,
  },
  helper: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.xs },
  field: { marginBottom: spacing.md, flex: 1 },
  fieldLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm - 1,
    fontWeight: '700',
    marginBottom: spacing.xs + 2,
  },
  input: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.lineStrong,
    borderRadius: radius.card - 4,
    paddingHorizontal: spacing.sm + 6,
    paddingVertical: spacing.sm + 4,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
  },
  textarea: { minHeight: 72, textAlignVertical: 'top' },
  row2: { flexDirection: 'row', gap: spacing.sm },
  placeRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginTop: spacing.sm },
  adjustBtn: { paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm + 2, borderRadius: radius.full, backgroundColor: colors.surfaceAlt },
  adjustBtnText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  chip: {
    paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.sm + 6,
    borderRadius: radius.full, backgroundColor: colors.surfaceAlt,
  },
  chipOn: { backgroundColor: colors.cta },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  chipTextOn: { color: colors.onCta, fontWeight: '700' },
  priceRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  priceInput: { width: 96 },
  detailRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    minHeight: 56, borderBottomWidth: 1, borderBottomColor: colors.line,
  },
  detailLabel: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '600' },
  detailSummary: { color: colors.textSecondary, fontSize: fontSizes.sm, maxWidth: 160 },
  detailBody: { paddingVertical: spacing.md, borderBottomWidth: 1, borderBottomColor: colors.line },
  tagsWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2, marginBottom: spacing.sm },
  tag: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 7,
  },
  tagTint: { backgroundColor: colors.cta + '1F' },
  tagText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600', maxWidth: 240 },
  tagX: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800' },
  tagInputRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  addBtn: {
    width: 44, height: 44, borderRadius: radius.card - 4, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center',
  },
  addBtnPrimary: { backgroundColor: colors.cta },
  checkRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    paddingVertical: spacing.sm + 1, borderBottomWidth: 1, borderBottomColor: colors.line,
  },
  checkBox: {
    width: 20, height: 20, borderRadius: 6, borderWidth: 1.5, borderColor: colors.textMuted,
    alignItems: 'center', justifyContent: 'center',
  },
  checkBoxOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  checkMark: { color: colors.onCta, fontSize: fontSizes.xs, fontWeight: '800' },
  checkLabel: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '600' },
  deleteButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    marginTop: spacing.lg,
  },
  deleteButtonText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '600' },
  ctaBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    paddingHorizontal: spacing.md, paddingTop: spacing.sm,
    backgroundColor: colors.background, borderTopWidth: 1, borderTopColor: colors.line,
  },
  cta: {
    backgroundColor: colors.brand, borderRadius: radius.full, paddingVertical: spacing.sm + 6, alignItems: 'center',
  },
  ctaDisabled: { opacity: 0.5 },
  ctaText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  fullMapStyleButton: { position: 'absolute', top: spacing.sm + 2, left: spacing.md, zIndex: 10 },
  fullMapCloseBtn: { borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card,
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
  fullMapCloseText: { color: colors.textPrimary, fontSize: fontSizes.lg + 2 },
  fullMapConfirm: {
    position: 'absolute',
    left: spacing.lg,
    right: spacing.lg,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm + 4,
    borderRadius: radius.full,
    backgroundColor: colors.brand,
  },
  fullMapConfirmDisabled: { opacity: 0.5 },
  fullMapConfirmText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
});
