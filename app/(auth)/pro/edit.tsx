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
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { Check } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { proService } from '@/services/pro-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { LogoSpinner } from '@/components/logo-spinner';
import { JuntoMapView } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { ProPin } from '@/components/pro-pin';
import { PRO_PIN_ICONS } from '@/constants/pro-pin-icons';

export default function ProEditScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { center } = useInitialLocation();
  const insets = useSafeAreaInsets();

  const { data: existing, isLoading } = useQuery({
    queryKey: ['pro-profile-mine'],
    queryFn: () => proService.getMine(),
  });

  const isUpdate = !!existing;

  const [displayName, setDisplayName] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [realName, setRealName] = useState('');
  const [tagline, setTagline] = useState('');
  const [description, setDescription] = useState('');
  const [website, setWebsite] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [instagram, setInstagram] = useState('');
  const [facebook, setFacebook] = useState('');
  const [locationName, setLocationName] = useState('');
  const [pinLng, setPinLng] = useState<number | null>(null);
  const [pinLat, setPinLat] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [showMapPicker, setShowMapPicker] = useState(false);
  const [pickerPinLng, setPickerPinLng] = useState<number | null>(null);
  const [pickerPinLat, setPickerPinLat] = useState<number | null>(null);
  const [pinIcon, setPinIcon] = useState<string | null>(null);
  const [pinIconBusy, setPinIconBusy] = useState(false);

  // Once the existing profile loads, hydrate the form. Falling through
  // to defaults if the user is new (no profile yet).
  useEffect(() => {
    if (!existing) return;
    setDisplayName(existing.display_name);
    setCompanyName(existing.company_name ?? '');
    setRealName(existing.real_name ?? '');
    setTagline(existing.tagline ?? '');
    setDescription(existing.description ?? '');
    setWebsite(existing.website ?? '');
    setEmail(existing.email ?? '');
    setPhone(existing.phone ?? '');
    setInstagram(existing.instagram ?? '');
    setFacebook(existing.facebook ?? '');
    setLocationName(existing.primary_location_name);
    setPinLng(existing.primary_lng);
    setPinLat(existing.primary_lat);
    setPinIcon(existing.pin_icon);
  }, [existing]);


  // Tap an icon to set it; tap the selected one again to clear (back to the
  // initial fallback). Persisted immediately via the approved-only setter.
  const handlePickIcon = async (key: string) => {
    if (pinIconBusy) return;
    const prev = pinIcon;
    const next = pinIcon === key ? null : key;
    setPinIcon(next);
    setPinIconBusy(true);
    try {
      await proService.setPinIcon(next);
      await queryClient.invalidateQueries({ queryKey: ['pro-profile-mine'] });
      await queryClient.invalidateQueries({ queryKey: ['pro-profile', existing?.user_id] });
      await queryClient.invalidateQueries({ queryKey: ['pros'] });
    } catch (err) {
      setPinIcon(prev);
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setPinIconBusy(false);
    }
  };

  const openMapPicker = () => {
    if (locationLocked) return;
    setPickerPinLng(pinLng);
    setPickerPinLat(pinLat);
    setShowMapPicker(true);
  };

  const confirmMapPick = () => {
    if (pickerPinLng !== null && pickerPinLat !== null) {
      setPinLng(pickerPinLng);
      setPinLat(pickerPinLat);
    }
    setShowMapPicker(false);
  };

  // Location-change rate limit is enforced at the DB level; surface it
  // to the user before submit so they don't get a generic "not
  // permitted" toast.
  const lastChange = existing?.last_location_change_at;
  const locationLocked = useMemo(() => {
    if (!lastChange) return false;
    const elapsed = Date.now() - new Date(lastChange).getTime();
    return elapsed < 30 * 24 * 60 * 60 * 1000;
  }, [lastChange]);
  const locationChanged =
    existing != null &&
    (pinLng !== existing.primary_lng || pinLat !== existing.primary_lat || locationName.trim() !== existing.primary_location_name);

  // Verification fields (company + real name) are required to register AND to
  // re-submit a rejected application (so the pro can fix what got them rejected).
  // An approved pro editing their live page doesn't re-enter them.
  const showVerification = !isUpdate || existing?.status === 'rejected';
  const verificationOk = !showVerification || (companyName.trim().length >= 2 && realName.trim().length >= 2);
  const canSubmit =
    displayName.trim().length >= 1 &&
    verificationOk &&
    pinLng !== null &&
    pinLat !== null &&
    locationName.trim().length >= 1 &&
    !(locationChanged && locationLocked) &&
    !saving;

  const handleSubmit = async () => {
    if (!canSubmit || pinLng === null || pinLat === null) return;
    setSaving(true);
    try {
      const payload = {
        display_name: displayName.trim(),
        company_name: companyName.trim(),
        real_name: realName.trim(),
        tagline: tagline.trim() || null,
        description: description.trim() || null,
        website: website.trim() || null,
        email: email.trim() || null,
        phone: phone.trim() || null,
        instagram: instagram.trim() || null,
        facebook: facebook.trim() || null,
        primary_lng: pinLng,
        primary_lat: pinLat,
        primary_location_name: locationName.trim(),
      };
      if (isUpdate) {
        const base = {
          display_name: payload.display_name,
          tagline: payload.tagline,
          description: payload.description,
          website: payload.website,
          email: payload.email,
          phone: payload.phone,
          instagram: payload.instagram,
          facebook: payload.facebook,
          // Only a rejected pro re-enters the verification fields.
          ...(showVerification ? { company_name: payload.company_name, real_name: payload.real_name } : {}),
        };
        // Only send location when it actually changed — otherwise the
        // RPC's "primary_lng/lat must come together" guard rejects.
        if (!locationChanged) {
          await proService.update(base);
        } else {
          await proService.update({ ...base, primary_lng: pinLng, primary_lat: pinLat, primary_location_name: locationName.trim() });
        }
        // A rejected pro editing their page re-submits for review.
        if (existing?.status === 'rejected') {
          await proService.resubmit();
        }
      } else {
        await proService.register(payload);
      }
      await queryClient.invalidateQueries({ queryKey: ['pro-profile-mine'] });
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
      Burnt.toast({
        title: isUpdate
          ? t('pro.saved', { defaultValue: 'Page pro enregistrée' })
          : t('pro.submitted', { defaultValue: 'Demande envoyée — en attente de validation' }),
        preset: 'done',
      });
      router.back();
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setSaving(false);
    }
  };

  if (isLoading) {
    return <View style={styles.center}><LogoSpinner size={48} /></View>;
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.container} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Text style={styles.title}>
          {isUpdate ? t('pro.editTitle', { defaultValue: 'Modifier ta page pro' }) : t('pro.registerTitle', { defaultValue: 'Devenir pro' })}
        </Text>
        <Text style={styles.subtitle}>
          {t('pro.registerSubtitle', {
            defaultValue: 'Crée la page publique de ton activité, club ou structure.',
          })}
        </Text>

        {existing?.status === 'pending' && (
          <View style={[styles.statusBanner, styles.statusPending]}>
            <Text style={styles.statusBannerText}>
              {t('pro.bannerPending', { defaultValue: 'Ta demande est en attente de validation.' })}
            </Text>
          </View>
        )}
        {existing?.status === 'rejected' && (
          <View style={[styles.statusBanner, styles.statusRejected]}>
            <Text style={styles.statusBannerText}>
              {existing.rejection_reason || t('pro.bannerRejected', { defaultValue: 'Demande refusée. Corrige tes informations puis renvoie-la.' })}
            </Text>
          </View>
        )}


        {/* Pin image — square photo that replaces the initial inside the
            pro pin on the map. Update-mode only, same as banner. */}
        {isUpdate && (
          <View style={styles.bannerSection}>
            <Text style={styles.section}>{t('pro.pinIconSection', { defaultValue: 'Icône du pin' })}</Text>
            <Text style={styles.helper}>
              {t('pro.pinIconHelper', { defaultValue: "Choisis ton univers — il s'affiche dans ton pin sur la carte." })}
            </Text>
            <View style={styles.pinIconRow}>
              <View style={styles.pinPreviewWrap}>
                <ProPin displayName={displayName || 'P'} pinIcon={pinIcon} />
              </View>
              <View style={styles.pinIconGrid}>
                {PRO_PIN_ICONS.map((opt) => {
                  const selected = pinIcon === opt.key;
                  return (
                    <Pressable
                      key={opt.key}
                      style={[styles.pinIconChip, selected && styles.pinIconChipSelected]}
                      onPress={() => handlePickIcon(opt.key)}
                      disabled={pinIconBusy}
                      accessibilityLabel={opt.label}
                    >
                      <Text style={styles.pinIconEmoji}>{opt.emoji}</Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </View>
        )}

        <Field label={t('pro.fieldName', { defaultValue: 'Nom *' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={displayName}
            onChangeText={setDisplayName}
            placeholder={t('pro.fieldNamePlaceholder', { defaultValue: 'Junto Alpine School' })}
            placeholderTextColor={colors.textSecondary}
            maxLength={100}
          />
        </Field>

        {showVerification && (
          <>
            <Field label={t('pro.fieldCompany', { defaultValue: 'Nom de la structure *' })} styles={styles}>
              <TextInput
                style={styles.input}
                value={companyName}
                onChangeText={setCompanyName}
                placeholder={t('pro.fieldCompanyPlaceholder', { defaultValue: 'Raison sociale / nom de l’entreprise' })}
                placeholderTextColor={colors.textSecondary}
                maxLength={120}
              />
            </Field>
            <Field label={t('pro.fieldRealName', { defaultValue: 'Ton nom et prénom *' })} styles={styles}>
              <TextInput
                style={styles.input}
                value={realName}
                onChangeText={setRealName}
                placeholder={t('pro.fieldRealNamePlaceholder', { defaultValue: 'Pour la vérification — non public' })}
                placeholderTextColor={colors.textSecondary}
                maxLength={120}
              />
            </Field>
          </>
        )}

        <Field label={t('pro.fieldTagline', { defaultValue: 'Slogan' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={tagline}
            onChangeText={setTagline}
            placeholder={t('pro.fieldTaglinePlaceholder', { defaultValue: 'Une phrase courte qui te décrit' })}
            placeholderTextColor={colors.textSecondary}
            maxLength={120}
          />
        </Field>

        <Field label={t('pro.fieldDescription', { defaultValue: 'Description' })} styles={styles}>
          <TextInput
            style={[styles.input, styles.textarea]}
            value={description}
            onChangeText={setDescription}
            placeholder={t('pro.fieldDescriptionPlaceholder', { defaultValue: 'Présente ce que tu proposes en détail.' })}
            placeholderTextColor={colors.textSecondary}
            maxLength={2000}
            multiline
            numberOfLines={6}
            textAlignVertical="top"
          />
        </Field>

        <Text style={styles.section}>{t('pro.contactSection', { defaultValue: 'Contact' })}</Text>

        <Field label={t('pro.fieldWebsite', { defaultValue: 'Site web' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={website}
            onChangeText={setWebsite}
            placeholder="https://..."
            placeholderTextColor={colors.textSecondary}
            autoCapitalize="none"
            keyboardType="url"
            maxLength={200}
          />
        </Field>

        <Field label={t('pro.fieldEmail', { defaultValue: 'Email' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={email}
            onChangeText={setEmail}
            placeholder="contact@..."
            placeholderTextColor={colors.textSecondary}
            autoCapitalize="none"
            keyboardType="email-address"
            maxLength={200}
          />
        </Field>

        <Field label={t('pro.fieldPhone', { defaultValue: 'Téléphone' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={phone}
            onChangeText={setPhone}
            placeholder="+33 6 ..."
            placeholderTextColor={colors.textSecondary}
            keyboardType="phone-pad"
            maxLength={30}
          />
        </Field>

        <Field label={t('pro.fieldInstagram', { defaultValue: 'Instagram' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={instagram}
            onChangeText={setInstagram}
            placeholder="@junto.alpine"
            placeholderTextColor={colors.textSecondary}
            autoCapitalize="none"
            maxLength={100}
          />
        </Field>

        <Field label={t('pro.fieldFacebook', { defaultValue: 'Facebook' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={facebook}
            onChangeText={setFacebook}
            placeholder="page-ou-url"
            placeholderTextColor={colors.textSecondary}
            autoCapitalize="none"
            maxLength={200}
          />
        </Field>

        <Text style={styles.section}>{t('pro.locationSection', { defaultValue: 'Localisation *' })}</Text>
        <Text style={styles.helper}>
          {locationLocked
            ? t('pro.locationLocked', { defaultValue: 'Tu pourras déplacer ton emplacement après 30 jours.' })
            : t('pro.locationHelper', { defaultValue: 'Tape sur la carte pour placer ton emplacement principal.' })}
        </Text>

        {/* Inline preview — taps open the full-screen picker. Read-only
            mini-map here; the actual location is set in the modal. */}
        <Pressable
          style={[styles.mapPreview, locationLocked && styles.mapContainerLocked]}
          onPress={openMapPicker}
          disabled={locationLocked}
        >
          <JuntoMapView
            center={pinLng !== null && pinLat !== null ? [pinLng, pinLat] : center}
            zoom={12}
            pins={
              pinLng !== null && pinLat !== null
                ? [{ id: 'pro', coordinate: [pinLng, pinLat], color: colors.cta }]
                : []
            }
            compassEnabled={false}
          />
          <View style={styles.mapPreviewOverlay} pointerEvents="box-only" />
          <View style={styles.mapPreviewHint} pointerEvents="none">
            <Text style={styles.mapPreviewHintText}>
              {pinLng !== null
                ? t('pro.locationChangeOnMap', { defaultValue: 'Modifier sur la carte' })
                : t('pro.locationPickOnMap', { defaultValue: 'Choisir sur la carte' })}
            </Text>
          </View>
        </Pressable>

        <Field label={t('pro.fieldLocationName', { defaultValue: 'Adresse / ville *' })} styles={styles}>
          <TextInput
            style={styles.input}
            value={locationName}
            onChangeText={setLocationName}
            placeholder={t('pro.fieldLocationNamePlaceholder', { defaultValue: 'Briançon, Hautes-Alpes' })}
            placeholderTextColor={colors.textSecondary}
            maxLength={200}
          />
        </Field>

        {!isUpdate && (
          <Text style={styles.verifyNote}>
            {t('pro.verifyNote', { defaultValue: 'Ta demande est vérifiée par notre équipe avant la mise en ligne de ta page. Tu seras notifié·e dès qu’elle est validée.' })}
          </Text>
        )}

        <Pressable
          style={[styles.submit, (!canSubmit) && styles.submitDisabled]}
          onPress={handleSubmit}
          disabled={!canSubmit}
        >
          <Text style={styles.submitText}>
            {saving
              ? '...'
              : existing?.status === 'rejected'
                ? t('pro.resubmit', { defaultValue: 'Renvoyer la demande' })
                : isUpdate
                  ? t('pro.saveChanges', { defaultValue: 'Enregistrer' })
                  : t('pro.register', { defaultValue: 'Devenir pro' })}
          </Text>
        </Pressable>
      </ScrollView>

      {/* Full-screen map picker — replaces the tiny inline square that
          was too cramped to position a pin precisely. Drop pin anywhere
          on the map; "Confirmer" promotes the picker pin to the form. */}
      <Modal visible={showMapPicker} animationType="slide" onRequestClose={() => setShowMapPicker(false)}>
        <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
          <JuntoMapView
            center={
              pickerPinLng !== null && pickerPinLat !== null
                ? [pickerPinLng, pickerPinLat]
                : pinLng !== null && pinLat !== null
                  ? [pinLng, pinLat]
                  : center
            }
            zoom={12}
            onMapPress={(lng, lat) => {
              setPickerPinLng(lng);
              setPickerPinLat(lat);
            }}
            pins={
              pickerPinLng !== null && pickerPinLat !== null
                ? [{ id: 'pro-picker', coordinate: [pickerPinLng, pickerPinLat], color: colors.cta }]
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
          <View style={[styles.fullMapHint, { top: insets.top + spacing.sm + 4 + 44 }]} pointerEvents="none">
            <Text style={styles.fullMapHintText}>
              {pickerPinLng !== null
                ? t('pro.locationConfirmHint', { defaultValue: 'Tape pour repositionner, ou confirme.' })
                : t('pro.locationFirstTapHint', { defaultValue: 'Tape sur la carte pour placer le pin.' })}
            </Text>
          </View>
          <Pressable
            style={[styles.fullMapConfirm, { bottom: insets.bottom + 24 }, pickerPinLng === null && styles.fullMapConfirmDisabled]}
            onPress={confirmMapPick}
            disabled={pickerPinLng === null}
          >
            <Check size={16} color={colors.textPrimary} strokeWidth={2.6} />
            <Text style={styles.fullMapConfirmText}>
              {t('pro.locationConfirm', { defaultValue: 'Confirmer' })}
            </Text>
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
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontFamily: fonts.title,
    marginBottom: spacing.xs,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    marginBottom: spacing.lg,
  },
  statusBanner: {
    borderRadius: radius.sm,
    borderWidth: 1,
    padding: spacing.sm + 2,
    marginBottom: spacing.lg,
  },
  statusPending: { backgroundColor: colors.cta + '14', borderColor: colors.cta },
  statusRejected: { backgroundColor: colors.error + '14', borderColor: colors.error },
  statusBannerText: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 19 },
  verifyNote: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 17, textAlign: 'center', marginBottom: spacing.sm },
  section: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginTop: spacing.md,
    marginBottom: spacing.sm,
  },
  helper: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    marginBottom: spacing.sm,
  },
  bannerSection: { marginBottom: spacing.md },
  pinIconRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    marginTop: spacing.xs,
  },
  pinIconGrid: {
    flex: 1,
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs,
  },
  pinIconChip: {
    width: 42,
    height: 42,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1.5,
    borderColor: colors.borderMuted,
  },
  pinIconChipSelected: {
    borderColor: colors.cta,
    backgroundColor: colors.cta + '20',
  },
  pinIconEmoji: { fontSize: 20 },
  pinImageRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  // Live preview of how the pro pin will look on the map with the
  // currently-picked image.
  pinPreviewWrap: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
  },
  pinImagePickBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  pinImagePickText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
  pinImageRemoveBtn: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.error,
    borderRadius: radius.sm,
  },
  field: { marginBottom: spacing.md },
  fieldLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    marginBottom: spacing.xs - 2,
  },
  input: {
    backgroundColor: 'transparent',
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.sm,
  },
  textarea: {
    minHeight: 110,
  },
  // Inline preview — clearly read-only; taps open the full-screen
  // picker where the actual placement happens.
  mapPreview: {
    height: 180,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    overflow: 'hidden',
    marginBottom: spacing.md,
  },
  mapPreviewOverlay: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
  },
  mapPreviewHint: {
    position: 'absolute',
    bottom: spacing.sm,
    alignSelf: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
  },
  mapPreviewHintText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  mapContainerLocked: {
    opacity: 0.55,
  },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  fullMapCloseBtn: {
    position: 'absolute', top: spacing.sm + 4, left: spacing.md,
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  fullMapCloseText: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  fullMapHint: {
    position: 'absolute', alignSelf: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.borderMuted,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md, paddingVertical: 6,
  },
  fullMapHintText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
  },
  fullMapConfirm: {
    position: 'absolute', alignSelf: 'center',
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg, paddingVertical: spacing.sm + 2,
  },
  fullMapConfirmDisabled: { opacity: 0.4 },
  fullMapConfirmText: {
    color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
  submit: {
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
    marginTop: spacing.md,
  },
  submitDisabled: { opacity: 0.4 },
  submitText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
  },
});
