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
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { X, Check, Trash2, ChevronDown, ChevronUp, ChevronRight, Plus, MapPin } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius, glow } from '@/constants/theme';
import { proService, type ClearableProField } from '@/services/pro-service';
import { proOfferingService } from '@/services/pro-offering-service';
import { PRO_PROFESSIONS, isProProfession, type ProProfession } from '@/constants/professions';
import { getFriendlyError } from '@/utils/friendly-error';
import { pickAndUploadProPinImage } from '@/utils/pro-pin-image-upload';
import { LogoSpinner } from '@/components/logo-spinner';
import { JuntoMapView } from '@/components/map-view';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { PressableScale } from '@/components/pressable-scale';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { ProPinPicker } from '@/components/pro-pin-picker';

// Register-or-update screen for the pro page (lot 2 pro, mockup validated
// 2026-10-15):
//   - becoming a pro asks FOUR things (name shown, legal name, identity,
//     place) — contact and about are folded away, optional;
//   - the place is one gesture: a place search fills the town and drops the
//     pin, the mini-map stays to adjust by hand;
//   - once approved, the page edit has ONE save logic: pin icon and logo are
//     applied with « Enregistrer » like every other field (the logo file is
//     uploaded at pick time, the profile change waits);
//   - the primary action is a sticky bar, never lost at the bottom of a
//     13-field scroll.
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
  const isApproved = existing?.status === 'approved';
  const { data: myOfferings } = useQuery({
    queryKey: ['pro-offerings', existing?.user_id],
    queryFn: () => proOfferingService.getByProId(existing!.user_id),
    enabled: !!existing?.user_id && isApproved,
  });

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
  const [deleting, setDeleting] = useState(false);
  const [showMapPicker, setShowMapPicker] = useState(false);
  const [pickerPinLng, setPickerPinLng] = useState<number | null>(null);
  const [pickerPinLat, setPickerPinLat] = useState<number | null>(null);
  const [pinIcon, setPinIcon] = useState<string | null>(null);
  const [pinImageUrl, setPinImageUrl] = useState<string | null>(null);
  const [pinImageBusy, setPinImageBusy] = useState(false);
  // Folded sections.
  const [showContact, setShowContact] = useState(false);
  const [showAbout, setShowAbout] = useState(false);
  const [showLocation, setShowLocation] = useState(false);
  // 00554: declared profession (required) + the outing featured on the page.
  const [profession, setProfession] = useState<ProProfession | null>(null);
  const [showProfessionPicker, setShowProfessionPicker] = useState(false);
  const [featuredOfferingId, setFeaturedOfferingId] = useState<string | null>(null);

  // Once the existing profile loads, hydrate the form.
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
    setPinImageUrl(existing.pin_image_url);
    setProfession(isProProfession(existing.profession) ? existing.profession : null);
    setFeaturedOfferingId(existing.featured_offering_id ?? null);
    // An approved pro sees slogan/description open (that is the page), a
    // pending/rejected one sees the application as they sent it.
    setShowAbout(existing.status === 'approved' || !!existing.tagline || !!existing.description);
    setShowContact(!!(existing.website || existing.email || existing.phone || existing.instagram || existing.facebook) && existing.status !== 'approved');
    setShowLocation(existing.status !== 'approved');
  }, [existing]);

  // Pin icon / photo: local state only — applied with « Enregistrer ».
  const handlePickPinImage = async () => {
    if (pinImageBusy) return;
    setPinImageBusy(true);
    try {
      const newUrl = await pickAndUploadProPinImage(false);
      if (newUrl) setPinImageUrl(newUrl);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setPinImageBusy(false);
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
  // before submit. Only an APPROVED (public) pin is locked (00444).
  const lastChange = existing?.last_location_change_at;
  const locationLocked = useMemo(() => {
    if (!isApproved || !lastChange) return false;
    const elapsed = Date.now() - new Date(lastChange).getTime();
    return elapsed < 30 * 24 * 60 * 60 * 1000;
  }, [isApproved, lastChange]);
  const locationChanged =
    existing != null &&
    (pinLng !== existing.primary_lng || pinLat !== existing.primary_lat || locationName.trim() !== existing.primary_location_name);

  // Verification fields are editable until approval; frozen server-side
  // after (00443, junto.pro_identity_locked) and no longer shown.
  const showVerification = !isUpdate || !isApproved;
  const verificationOk = !showVerification || (companyName.trim().length >= 2 && realName.trim().length >= 2);
  const pinChanged = isApproved && existing
    ? pinIcon !== existing.pin_icon || pinImageUrl !== existing.pin_image_url
    : false;
  const canSubmit =
    displayName.trim().length >= 1 &&
    profession !== null &&
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
        profession,
      };
      if (isUpdate) {
        // A field the pro blanked out must be named to the RPC (00444).
        const clear: ClearableProField[] = [];
        const optional: Record<Exclude<ClearableProField, 'profession' | 'featured_offering_id'>, string | null> = {
          tagline: payload.tagline,
          description: payload.description,
          website: payload.website,
          email: payload.email,
          phone: payload.phone,
          instagram: payload.instagram,
          facebook: payload.facebook,
        };
        (Object.keys(optional) as (keyof typeof optional)[]).forEach((k) => {
          if (optional[k] === null && existing?.[k]) clear.push(k);
        });
        // The featured outing: NULL means « the first », named to the RPC when
        // the pro just unset it (the param itself reads NULL as unchanged).
        if (featuredOfferingId === null && existing?.featured_offering_id) clear.push('featured_offering_id');
        const base = {
          display_name: payload.display_name,
          ...optional,
          profession,
          featured_offering_id: featuredOfferingId,
          clear,
          ...(showVerification ? { company_name: payload.company_name, real_name: payload.real_name } : {}),
        };
        if (!locationChanged) {
          await proService.update(base);
        } else {
          await proService.update({ ...base, primary_lng: pinLng, primary_lat: pinLat, primary_location_name: locationName.trim() });
        }
        // Pin icon / logo travel with the same save (approved-only setters).
        if (pinChanged && existing) {
          if (pinImageUrl !== existing.pin_image_url) await proService.setPinImage(pinImageUrl);
          if (pinIcon !== existing.pin_icon) await proService.setPinIcon(pinIcon);
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
      if (existing?.user_id) {
        await queryClient.invalidateQueries({ queryKey: ['pro-profile', existing.user_id] });
      }
      await queryClient.invalidateQueries({ queryKey: ['pros'] });
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

  // Delete the whole pro page (cascades offerings + photos + reviews, tier → free).
  const handleDelete = () => {
    Alert.alert(
      t('pro.deleteTitle', { defaultValue: 'Supprimer ta page pro ?' }),
      t('pro.deleteBody', {
        defaultValue:
          'Ta page pro, ses offres et ses avis seront définitivement supprimés, et ton compte repasse en gratuit. Cette action est irréversible.',
      }),
      [
        { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
        {
          text: t('pro.deleteConfirm', { defaultValue: 'Supprimer' }),
          style: 'destructive',
          onPress: async () => {
            setDeleting(true);
            try {
              await proService.unregister();
              await queryClient.invalidateQueries({ queryKey: ['pro-profile-mine'] });
              await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
              await queryClient.invalidateQueries({ queryKey: ['pros'] });
              Burnt.toast({ title: t('pro.deleted', { defaultValue: 'Page pro supprimée' }), preset: 'done' });
              router.back();
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
            } finally {
              setDeleting(false);
            }
          },
        },
      ],
    );
  };

  if (isLoading) {
    return <View style={styles.center}><LogoSpinner size={48} /></View>;
  }

  const contactSummary = [phone.trim(), website.trim(), email.trim(), instagram.trim(), facebook.trim()].filter(Boolean).length;

  const renderFoldRow = (label: string, open: boolean, onToggle: () => void, summary?: string, optional = false) => (
    <Pressable style={styles.foldRow} onPress={onToggle} accessibilityRole="button">
      {!open && !isUpdate ? <Plus size={18} color={colors.textPrimary} strokeWidth={2.2} /> : null}
      <AppText style={styles.foldLabel}>{label}</AppText>
      {summary ? <AppText style={styles.foldSummary} numberOfLines={1}>{summary}</AppText> : null}
      {optional && !open ? <AppText style={styles.foldOptional}>{t('pro.optional', { defaultValue: 'optionnel' })}</AppText> : null}
      {open ? <ChevronUp size={18} color={colors.textMuted} strokeWidth={2.2} /> : <ChevronDown size={18} color={colors.textMuted} strokeWidth={2.2} />}
    </Pressable>
  );

  const locationBlock = (
    <View style={styles.locationBlock}>
      {!locationLocked && (
        <PlaceSearchBar
          bias={pinLng !== null && pinLat !== null ? { lat: pinLat, lng: pinLng } : null}
          onSelect={(place) => {
            setPinLng(place.lng);
            setPinLat(place.lat);
            setLocationName([place.label, place.sublabel.split(', ')[0]].filter((x): x is string => !!x).join(', ').slice(0, 200));
          }}
        />
      )}
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
        {!locationLocked && (
          <View style={styles.mapPreviewHint} pointerEvents="none">
            <AppText style={styles.mapPreviewHintText}>
              {pinLng !== null
                ? t('pro.locationAdjust', { defaultValue: 'Ajuste au doigt si besoin' })
                : t('pro.locationPickOnMap', { defaultValue: 'Choisir sur la carte' })}
            </AppText>
          </View>
        )}
      </Pressable>
      <View style={styles.placeRow}>
        <MapPin size={16} color={pinLng !== null ? colors.cta : colors.textMuted} strokeWidth={2.4} />
        <AppTextInput
          style={[styles.input, { flex: 1 }]}
          value={locationName}
          onChangeText={setLocationName}
          placeholder={t('pro.fieldLocationNamePlaceholder', { defaultValue: 'Briançon, Hautes-Alpes' })}
          placeholderTextColor={colors.textSecondary}
          maxLength={200}
          editable={!locationLocked}
        />
        {pinLng !== null ? <Check size={18} color={colors.cta} strokeWidth={2.6} /> : null}
      </View>
      <AppText style={styles.helper}>
        {locationLocked
          ? t('pro.locationLocked', { defaultValue: 'Tu pourras déplacer ton emplacement après 30 jours.' })
          : t('pro.locationHelperSearch', { defaultValue: 'Cherche ta ville ou ton adresse : la carte se place toute seule.' })}
      </AppText>
    </View>
  );

  const contactBlock = (
    <View style={styles.foldBody}>
      <Field label={t('pro.fieldPhone', { defaultValue: 'Téléphone' })} styles={styles}>
        <AppTextInput style={styles.input} value={phone} onChangeText={setPhone} placeholder="+33 6 ..." placeholderTextColor={colors.textSecondary} keyboardType="phone-pad" maxLength={30} />
      </Field>
      <Field label={t('pro.fieldWebsite', { defaultValue: 'Site web' })} styles={styles}>
        <AppTextInput style={styles.input} value={website} onChangeText={setWebsite} placeholder="https://..." placeholderTextColor={colors.textSecondary} autoCapitalize="none" keyboardType="url" maxLength={200} />
      </Field>
      <Field label={t('pro.fieldEmail', { defaultValue: 'Email' })} styles={styles}>
        <AppTextInput style={styles.input} value={email} onChangeText={setEmail} placeholder="contact@..." placeholderTextColor={colors.textSecondary} autoCapitalize="none" keyboardType="email-address" maxLength={200} />
      </Field>
      <Field label={t('pro.fieldInstagram', { defaultValue: 'Instagram' })} styles={styles}>
        <AppTextInput style={styles.input} value={instagram} onChangeText={setInstagram} placeholder="@junto.alpine" placeholderTextColor={colors.textSecondary} autoCapitalize="none" maxLength={100} />
      </Field>
      <Field label={t('pro.fieldFacebook', { defaultValue: 'Facebook' })} styles={styles}>
        <AppTextInput style={styles.input} value={facebook} onChangeText={setFacebook} placeholder="page-ou-url" placeholderTextColor={colors.textSecondary} autoCapitalize="none" maxLength={200} />
      </Field>
    </View>
  );

  const aboutBlock = (
    <View style={isApproved ? undefined : styles.foldBody}>
      <Field label={t('pro.fieldTagline', { defaultValue: 'Slogan' })} styles={styles}>
        <AppTextInput style={styles.input} value={tagline} onChangeText={setTagline} placeholder={t('pro.fieldTaglinePlaceholder', { defaultValue: 'Une phrase courte qui te décrit' })} placeholderTextColor={colors.textSecondary} maxLength={120} />
      </Field>
      <Field label={t('pro.fieldDescription', { defaultValue: 'Description' })} styles={styles}>
        <AppTextInput
          style={[styles.input, styles.textarea]}
          value={description}
          onChangeText={setDescription}
          placeholder={t('pro.fieldDescriptionPlaceholder', { defaultValue: 'Présente ce que tu proposes en détail.' })}
          placeholderTextColor={colors.textSecondary}
          maxLength={2000}
          multiline
          numberOfLines={5}
          textAlignVertical="top"
        />
      </Field>
    </View>
  );

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.container} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <AppText style={styles.title}>
          {isApproved
            ? t('pro.pageTitle', { defaultValue: 'Ma page pro' })
            : isUpdate
              ? t('pro.applicationTitle', { defaultValue: 'Ma demande pro' })
              : t('pro.registerTitle', { defaultValue: 'Devenir pro' })}
        </AppText>
        {!isApproved && (
          <AppText style={styles.subtitle}>
            {t('pro.registerSubtitleShort', { defaultValue: 'Quatre infos suffisent. Le reste se complète plus tard, depuis ta page.' })}
          </AppText>
        )}

        {existing?.status === 'pending' && (
          <View style={[styles.statusBanner, styles.statusPending]}>
            <AppText style={styles.statusBannerText}>
              {t('pro.bannerPending', { defaultValue: 'Ta demande est en attente de validation.' })}
            </AppText>
          </View>
        )}
        {existing?.status === 'rejected' && (
          <View style={[styles.statusBanner, styles.statusRejected]}>
            <AppText style={styles.statusBannerText}>
              {existing.rejection_reason || t('pro.bannerRejected', { defaultValue: 'Demande refusée. Corrige tes informations puis renvoie-la.' })}
            </AppText>
          </View>
        )}

        {/* Ton pin sur la carte — approved only (the setters refuse before).
            Four ways (2026-10-26): profession (default) · universe · sport · photo. */}
        {isApproved && (
          <ProPinPicker
            displayName={displayName || 'P'}
            profession={profession}
            pinIcon={pinIcon}
            pinImageUrl={pinImageUrl}
            pinImageBusy={pinImageBusy}
            onPinIcon={setPinIcon}
            onPickImage={handlePickPinImage}
            onRemoveImage={() => setPinImageUrl(null)}
          />
        )}

        <Field label={t('pro.fieldDisplayName', { defaultValue: 'Nom affiché sur ta page' })} styles={styles}>
          <AppTextInput
            style={styles.input}
            value={displayName}
            onChangeText={setDisplayName}
            placeholder={t('pro.fieldNamePlaceholder', { defaultValue: 'askandgo Alpine School' })}
            placeholderTextColor={colors.textSecondary}
            maxLength={100}
          />
        </Field>

        <Field label={t('pro.fieldProfession', { defaultValue: 'Métier' })} styles={styles}>
          <Pressable style={styles.pickRow} onPress={() => setShowProfessionPicker(true)} accessibilityRole="button">
            <AppText style={[styles.pickRowText, !profession && styles.pickRowPlaceholder]} numberOfLines={1}>
              {profession
                ? t(`pro.profession.${profession}`, { defaultValue: profession })
                : t('pro.professionPlaceholder', { defaultValue: 'Choisir…' })}
            </AppText>
            <ChevronDown size={18} color={colors.textMuted} strokeWidth={2.2} />
          </Pressable>
        </Field>

        {/* The outing that opens the page (00554) — a choice only once there are two. */}
        {isApproved && (myOfferings?.length ?? 0) >= 2 && (
          <Field label={t('pro.featuredSection', { defaultValue: 'Sortie mise en avant' })} styles={styles}>
            <View style={styles.chipWrap}>
              <Pressable
                style={[styles.choiceChip, featuredOfferingId === null && styles.choiceChipSelected]}
                onPress={() => setFeaturedOfferingId(null)}
                accessibilityRole="button"
              >
                <AppText style={[styles.choiceChipText, featuredOfferingId === null && styles.choiceChipTextSelected]}>
                  {t('pro.featuredFirst', { defaultValue: 'La première' })}
                </AppText>
              </Pressable>
              {(myOfferings ?? []).map((o) => (
                <Pressable
                  key={o.id}
                  style={[styles.choiceChip, featuredOfferingId === o.id && styles.choiceChipSelected]}
                  onPress={() => setFeaturedOfferingId(o.id)}
                  accessibilityRole="button"
                >
                  <AppText style={[styles.choiceChipText, featuredOfferingId === o.id && styles.choiceChipTextSelected]} numberOfLines={1}>{o.title}</AppText>
                </Pressable>
              ))}
            </View>
            <AppText style={styles.helper}>{t('pro.featuredHelp', { defaultValue: 'Celle qui ouvre ta page. Les autres sont derrière « Voir les sorties ».' })}</AppText>
          </Field>
        )}

        {showVerification && (
          <>
            <Field label={t('pro.fieldCompanyPrivate', { defaultValue: 'Raison sociale · non publique' })} styles={styles}>
              <AppTextInput
                style={styles.input}
                value={companyName}
                onChangeText={setCompanyName}
                placeholder={t('pro.fieldCompanyPlaceholderShort', { defaultValue: 'SARL, EI, association…' })}
                placeholderTextColor={colors.textSecondary}
                maxLength={120}
              />
            </Field>
            <Field label={t('pro.fieldRealNamePrivate', { defaultValue: 'Ton nom et prénom · non public' })} styles={styles}>
              <AppTextInput
                style={styles.input}
                value={realName}
                onChangeText={setRealName}
                placeholder={t('pro.fieldRealNamePlaceholderShort', { defaultValue: 'Pour la vérification' })}
                placeholderTextColor={colors.textSecondary}
                maxLength={120}
              />
            </Field>
          </>
        )}

        {/* Approved: slogan + description are the page, always open. */}
        {isApproved ? aboutBlock : null}

        {/* Place: open while applying; folded with its summary once approved. */}
        {isApproved ? (
          <>
            {renderFoldRow(t('pro.addressRow', { defaultValue: 'Adresse' }), showLocation, () => setShowLocation((v) => !v), locationName)}
            {showLocation ? locationBlock : null}
          </>
        ) : (
          <View style={styles.field}>
            <AppText style={styles.fieldLabel}>{t('pro.whereToFind', { defaultValue: 'Où te trouver' })}</AppText>
            {locationBlock}
          </View>
        )}

        {/* Folded, optional sections. */}
        {renderFoldRow(
          t('pro.contactRow', { defaultValue: 'Contact · site, téléphone, réseaux' }),
          showContact,
          () => setShowContact((v) => !v),
          isApproved && contactSummary > 0 ? t('pro.contactCount', { defaultValue: '{{count}} renseigné', count: contactSummary }) : undefined,
          !isApproved,
        )}
        {showContact ? contactBlock : null}

        {!isApproved && (
          <>
            {renderFoldRow(t('pro.aboutRow', { defaultValue: 'Slogan et description' }), showAbout, () => setShowAbout((v) => !v), undefined, true)}
            {showAbout ? aboutBlock : null}
          </>
        )}

        {isApproved && existing && (
          <Pressable style={styles.foldRow} onPress={() => router.push(`/(auth)/pro/${existing.user_id}?tab=pictures`)} accessibilityRole="button">
            <AppText style={styles.foldLabel}>{t('pro.photosRow', { defaultValue: 'Photos de la page' })}</AppText>
            <ChevronRight size={18} color={colors.textMuted} strokeWidth={2.2} />
          </Pressable>
        )}

        {isApproved && (
          <AppText style={styles.frozenNote}>
            {t('pro.identityFrozen', { defaultValue: 'Raison sociale et identité vérifiées — pour les modifier, écris-nous.' })}
          </AppText>
        )}

        {isUpdate && (
          <Pressable style={styles.deleteBtn} onPress={handleDelete} disabled={deleting || saving}>
            <Trash2 size={16} color={colors.error} strokeWidth={2.4} />
            <AppText style={styles.deleteBtnText}>
              {deleting
                ? t('pro.deleting', { defaultValue: 'Suppression…' })
                : t('pro.deleteAction', { defaultValue: 'Supprimer ma page pro' })}
            </AppText>
          </Pressable>
        )}
      </ScrollView>

      {/* Sticky primary action. */}
      <View style={[styles.ctaBar, { paddingBottom: Math.max(insets.bottom, spacing.sm) + spacing.sm }]}>
        <PressableScale
          style={[styles.cta, !canSubmit && styles.ctaDisabled, canSubmit && glow(colors.brand)]}
          onPress={handleSubmit}
          disabled={!canSubmit}
        >
          <AppText style={styles.ctaText}>
            {saving
              ? '…'
              : existing?.status === 'rejected'
                ? t('pro.resubmit', { defaultValue: 'Renvoyer la demande' })
                : isUpdate
                  ? t('pro.saveChanges', { defaultValue: 'Enregistrer' })
                  : t('pro.sendApplication', { defaultValue: 'Envoyer ma demande' })}
          </AppText>
        </PressableScale>
        {!isUpdate && (
          <AppText style={styles.verifyNote}>
            {t('pro.verifyNoteShort', { defaultValue: 'Vérifiée par notre équipe avant mise en ligne. On te prévient par notification.' })}
          </AppText>
        )}
      </View>

      {/* Full-screen map picker — drop the pin anywhere; "Confirmer" promotes it. */}
      {/* Profession picker — one choice, closed list (00554). */}
      <Modal visible={showProfessionPicker} animationType="slide" transparent onRequestClose={() => setShowProfessionPicker(false)}>
        <Pressable style={styles.sheetBackdrop} onPress={() => setShowProfessionPicker(false)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.sheetHandle} />
            <AppText style={styles.sheetTitle}>{t('pro.professionPick', { defaultValue: 'Choisis ton métier' })}</AppText>
            <ScrollView style={styles.sheetList} showsVerticalScrollIndicator={false}>
              {PRO_PROFESSIONS.map((code) => {
                const selected = profession === code;
                return (
                  <Pressable
                    key={code}
                    style={styles.sheetRow}
                    onPress={() => { setProfession(code); setShowProfessionPicker(false); }}
                    accessibilityRole="button"
                    accessibilityState={{ selected }}
                  >
                    <AppText style={[styles.sheetRowText, selected && styles.sheetRowTextSelected]}>
                      {t(`pro.profession.${code}`, { defaultValue: code })}
                    </AppText>
                    {selected ? <Check size={18} color={colors.cta} strokeWidth={2.6} /> : null}
                  </Pressable>
                );
              })}
            </ScrollView>
          </Pressable>
        </Pressable>
      </Modal>

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
            <X size={18} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>
          <View style={[styles.fullMapHint, { top: insets.top + spacing.sm + 4 + 44 }]} pointerEvents="none">
            <AppText style={styles.fullMapHintText}>
              {pickerPinLng !== null
                ? t('pro.locationConfirmHint', { defaultValue: 'Tape pour repositionner, ou confirme.' })
                : t('pro.locationFirstTapHint', { defaultValue: 'Tape sur la carte pour placer le pin.' })}
            </AppText>
          </View>
          <Pressable
            style={[styles.fullMapConfirm, { bottom: insets.bottom + 24 }, pickerPinLng === null && styles.fullMapConfirmDisabled]}
            onPress={confirmMapPick}
            disabled={pickerPinLng === null}
          >
            <Check size={16} color={colors.onCta} strokeWidth={2.6} />
            <AppText style={styles.fullMapConfirmText}>
              {t('pro.locationConfirm', { defaultValue: 'Confirmer' })}
            </AppText>
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
  content: { padding: spacing.lg, paddingBottom: spacing.xl * 4 },
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
    lineHeight: 20,
    marginBottom: spacing.lg,
  },
  statusBanner: {
    borderRadius: radius.card - 4,
    padding: spacing.sm + 4,
    marginBottom: spacing.lg,
  },
  statusPending: { backgroundColor: colors.cta + '1F' },
  statusRejected: { backgroundColor: colors.error + '1F' },
  statusBannerText: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 19 },
  verifyNote: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16, textAlign: 'center', marginTop: spacing.sm },
  helper: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16, marginTop: spacing.xs },
  field: { marginBottom: spacing.md },
  pickRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.surface, borderRadius: radius.card - 4, borderWidth: 1, borderColor: colors.lineStrong,
    paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm + 4,
  },
  pickRowText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md },
  pickRowPlaceholder: { color: colors.textSecondary },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  choiceChip: {
    borderRadius: radius.full, paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm,
    backgroundColor: colors.surface, borderWidth: 1.5, borderColor: colors.lineStrong, maxWidth: '100%',
  },
  choiceChipSelected: { borderColor: colors.cta, backgroundColor: colors.cta + '14' },
  choiceChipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  choiceChipTextSelected: { color: colors.cta, fontWeight: '700' },
  sheetBackdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl, padding: spacing.lg, paddingBottom: spacing.xl + 8, maxHeight: '80%' },
  sheetHandle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.md, opacity: 0.4 },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: spacing.sm },
  sheetList: { flexGrow: 0 },
  sheetRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.sm + 4, borderBottomWidth: 1, borderBottomColor: colors.surfaceAlt },
  sheetRowText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md },
  sheetRowTextSelected: { color: colors.cta, fontWeight: '700' },
  fieldLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm - 1,
    fontWeight: '700',
    marginBottom: spacing.xs + 2,
  },
  input: {
    backgroundColor: colors.surface,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    borderRadius: radius.card - 4,
    borderWidth: 1,
    borderColor: colors.lineStrong,
    paddingHorizontal: spacing.sm + 6,
    paddingVertical: spacing.sm + 4,
  },
  textarea: { minHeight: 110 },
  locationBlock: { gap: spacing.sm },
  mapPreview: {
    height: 132,
    borderRadius: radius.card,
    overflow: 'hidden',
    backgroundColor: colors.surfaceAlt,
  },
  mapPreviewOverlay: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  mapPreviewHint: {
    position: 'absolute', bottom: spacing.sm, left: spacing.sm,
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 4, paddingVertical: 5,
  },
  mapPreviewHintText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '600' },
  mapContainerLocked: { opacity: 0.55 },
  placeRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  foldRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    minHeight: 54, borderTopWidth: 1, borderTopColor: colors.line,
  },
  foldLabel: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '600' },
  foldSummary: { color: colors.textSecondary, fontSize: fontSizes.sm, maxWidth: 150 },
  foldOptional: { color: colors.textMuted, fontSize: fontSizes.xs },
  foldBody: { paddingTop: spacing.sm },
  frozenNote: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.md, lineHeight: 16 },
  ctaBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    paddingHorizontal: spacing.md, paddingTop: spacing.sm,
    backgroundColor: colors.background, borderTopWidth: 1, borderTopColor: colors.line,
  },
  cta: { backgroundColor: colors.brand, borderRadius: radius.full, paddingVertical: spacing.sm + 6, alignItems: 'center' },
  ctaDisabled: { opacity: 0.4 },
  ctaText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  fullMapCloseBtn: {
    position: 'absolute', top: spacing.sm + 4, left: spacing.md,
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  fullMapHint: {
    position: 'absolute', alignSelf: 'center',
    backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.borderMuted,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md, paddingVertical: 6,
  },
  fullMapHintText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '600' },
  fullMapConfirm: {
    position: 'absolute', alignSelf: 'center',
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg, paddingVertical: spacing.sm + 2,
  },
  fullMapConfirmDisabled: { opacity: 0.4 },
  fullMapConfirmText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  deleteBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    paddingVertical: spacing.sm + 2, marginTop: spacing.lg,
  },
  deleteBtnText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '700' },
});
