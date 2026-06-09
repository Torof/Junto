import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Linking, Modal, Image } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { Phone, Mail, Globe, Instagram, Facebook, MapPin, Pencil, Navigation, Plus } from 'lucide-react-native';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import type { ProProfile } from '@/services/pro-service';
import { proOfferingService } from '@/services/pro-offering-service';
import { userService } from '@/services/user-service';
import { useProPhotos } from '@/hooks/use-pro-photos';
import { getSportIcon } from '@/constants/sport-icons';
import { JuntoMapView } from './map-view';
import { PhotoGallery } from './photo-gallery';

interface Props {
  pro: ProProfile;
  isOwner: boolean;
  onEdit?: () => void;
}

const COLLAPSED_DESCRIPTION_CHARS = 280;

export function ProDetail({ pro, isOwner, onEdit }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [descExpanded, setDescExpanded] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'pictures' | 'catalog' | 'reviews'>('info');
  const [showFullMap, setShowFullMap] = useState(false);

  const { data: offerings = [] } = useQuery({
    queryKey: ['pro-offerings', 'by-pro', pro.user_id],
    queryFn: () => proOfferingService.getByProId(pro.user_id),
    enabled: activeTab === 'catalog',
  });

  const { data: photos = [] } = useProPhotos(pro.user_id);

  // Underlying human behind the pro brand — exposed as a small avatar
  // in the hero so visitors can jump to the user's personal profile.
  const { data: ownerProfile } = useQuery({
    queryKey: ['public-profile', pro.user_id],
    queryFn: () => userService.getPublicProfile(pro.user_id),
  });

  const hasContact = Boolean(pro.phone || pro.email || pro.website || pro.instagram || pro.facebook);
  const description = pro.description ?? '';
  const descriptionOverflowing = description.length > COLLAPSED_DESCRIPTION_CHARS;
  const mapCenter: [number, number] = [pro.primary_lng, pro.primary_lat];
  const mapPins = [{ id: 'pro', coordinate: mapCenter, color: colors.cta, label: pro.primary_location_name }];

  return (
    <View style={styles.container}>
      {/* Tab bar — text-only, brutalist. Pictures sits between Info and
          Activités: info → context → offer → social-proof. */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.tabBarScroll}
        contentContainerStyle={styles.tabBar}
      >
        {(['info', 'pictures', 'catalog', 'reviews'] as const).map((tab) => {
          const isActiveTab = activeTab === tab;
          return (
            <Pressable
              key={tab}
              style={[styles.tab, isActiveTab && styles.tabActive]}
              onPress={() => setActiveTab(tab)}
              accessibilityRole="tab"
              accessibilityState={{ selected: isActiveTab }}
              accessibilityLabel={t(`pro.tab.${tab}`, { defaultValue: tab })}
            >
              <Text style={[styles.tabText, isActiveTab && styles.tabTextActive]}>
                {t(`pro.tab.${tab}`, {
                  defaultValue:
                    tab === 'info' ? 'Infos'
                      : tab === 'pictures' ? 'Photos'
                      : tab === 'catalog' ? 'Catalogue'
                      : 'Avis',
                })}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>

      {/* ===== INFO TAB ===== */}
      {activeTab === 'info' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          {/* === BANNER === First gallery photo doubles as the hero
              (Phase 4A consolidation). Hidden when the gallery is
              empty; layout collapses to just the hero. */}
          {photos[0] && (
            <Image
              source={{ uri: photos[0].photo_url }}
              style={styles.banner}
              resizeMode="cover"
              accessibilityLabel={`${pro.display_name} — bannière`}
            />
          )}

          {/* === HERO — full-width edge-to-edge, no horizontal margins. === */}
          <View style={[styles.heroCard, styles.heroFullBleed]}>
            <View style={styles.heroHeader}>
              <View style={{ flex: 1 }}>
                <Text style={styles.proLabel}>{t('pro.label', { defaultValue: 'PRO' })}</Text>
                <Text style={styles.heroTitle}>{pro.display_name}</Text>
              </View>
              <View style={styles.heroActions}>
                {/* Owner's user avatar — discloses the human behind the
                    pro brand. Taps through to /profile/[user_id]. Shown
                    to everyone (including the owner — they can still
                    visit their own profile from here). */}
                {ownerProfile && (
                  <Pressable
                    onPress={() => router.push(`/(auth)/profile/${pro.user_id}`)}
                    hitSlop={6}
                    accessibilityLabel={t('pro.ownerProfile', { defaultValue: 'Voir le profil' })}
                  >
                    {ownerProfile.avatar_url ? (
                      <Image source={{ uri: ownerProfile.avatar_url }} style={styles.ownerAvatar} />
                    ) : (
                      <View style={[styles.ownerAvatar, styles.ownerAvatarPlaceholder]}>
                        <Text style={styles.ownerAvatarInitial}>
                          {ownerProfile.display_name.charAt(0).toUpperCase()}
                        </Text>
                      </View>
                    )}
                  </Pressable>
                )}
                {isOwner && onEdit && (
                  <Pressable
                    onPress={onEdit}
                    hitSlop={10}
                    accessibilityLabel={t('pro.editPage', { defaultValue: 'Edit pro page' })}
                  >
                    <Pencil size={18} color={colors.textSecondary} strokeWidth={2.2} />
                  </Pressable>
                )}
              </View>
            </View>
            {pro.tagline && <Text style={styles.tagline}>{pro.tagline}</Text>}
            <View style={styles.locationRow}>
              <MapPin size={14} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.locationText} numberOfLines={2}>{pro.primary_location_name}</Text>
            </View>
          </View>

          {/* All cards below the hero get standard horizontal padding via
              the wrapper. */}
          <View style={styles.paddedSection}>
            {pro.description && (
              <View style={styles.infoCard}>
                <Text style={styles.sectionTitle}>{t('pro.about', { defaultValue: 'À propos' })}</Text>
                <Text style={styles.descriptionBody}>
                  {descExpanded || !descriptionOverflowing
                    ? description
                    : `${description.slice(0, COLLAPSED_DESCRIPTION_CHARS).trimEnd()}…`}
                </Text>
                {descriptionOverflowing && (
                  <Pressable onPress={() => setDescExpanded((v) => !v)} hitSlop={6}>
                    <Text style={styles.descriptionToggle}>
                      {descExpanded
                        ? t('pro.descSeeLess', { defaultValue: 'Voir moins' })
                        : t('pro.descSeeMore', { defaultValue: 'Voir plus' })}
                    </Text>
                  </Pressable>
                )}
              </View>
            )}

            {hasContact && (
              <View style={styles.infoCard}>
                <Text style={styles.sectionTitle}>{t('pro.contact', { defaultValue: 'Contact' })}</Text>
                {pro.phone && (
                  <ContactRow
                    icon={<Phone size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.phone}
                    onPress={() => Linking.openURL(`tel:${pro.phone}`)}
                    styles={styles}
                  />
                )}
                {pro.email && (
                  <ContactRow
                    icon={<Mail size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.email}
                    onPress={() => Linking.openURL(`mailto:${pro.email}`)}
                    styles={styles}
                  />
                )}
                {pro.website && (
                  <ContactRow
                    icon={<Globe size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.website.replace(/^https?:\/\//, '')}
                    onPress={() => Linking.openURL(pro.website!.startsWith('http') ? pro.website! : `https://${pro.website!}`)}
                    styles={styles}
                  />
                )}
                {pro.instagram && (
                  <ContactRow
                    icon={<Instagram size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.instagram}
                    onPress={() => Linking.openURL(`https://instagram.com/${pro.instagram!.replace(/^@/, '')}`)}
                    styles={styles}
                  />
                )}
                {pro.facebook && (
                  <ContactRow
                    icon={<Facebook size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.facebook}
                    onPress={() => Linking.openURL(pro.facebook!.startsWith('http') ? pro.facebook! : `https://facebook.com/${pro.facebook!}`)}
                    styles={styles}
                  />
                )}
              </View>
            )}

            {/* === LOCATION === Map preview, tap to open full screen +
                navigate. Same idiom as the activity info screen. */}
            <View style={styles.infoCard}>
              <Text style={styles.sectionTitle}>{t('pro.location', { defaultValue: 'Localisation' })}</Text>
              <Pressable style={styles.mapContainer} onPress={() => setShowFullMap(true)}>
                <JuntoMapView center={mapCenter} zoom={13} pins={mapPins} compassEnabled={false} />
                <View style={styles.mapTapOverlay} pointerEvents="box-only" />
                <View style={styles.mapNavHint} pointerEvents="none">
                  <Navigation size={12} color={colors.textPrimary} strokeWidth={2.4} />
                  <Text style={styles.mapNavHintText}>{t('activity.navigate', { defaultValue: 'Y aller' })}</Text>
                </View>
              </Pressable>
            </View>
          </View>
        </ScrollView>
      )}

      {/* ===== PICTURES TAB ===== Read-only gallery (owner manages from
          the edit screen). Empty-state copy nudges the owner to add some. */}
      {activeTab === 'pictures' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.galleryWrap}>
            <PhotoGallery
              photos={photos}
              emptyText={
                isOwner
                  ? t('pro.picturesEmptyOwner', { defaultValue: 'Aucune photo. Ajoute-en depuis l\'écran de modification.' })
                  : t('pro.picturesEmpty', { defaultValue: 'Aucune photo pour le moment.' })
              }
            />
          </View>
        </ScrollView>
      )}

      {/* ===== CATALOG TAB ===== List of pro_offerings authored by this
          pro. Owner gets a "+ create" button at the top; everyone else
          just sees the cards. Tapping a card routes to the offering
          detail page. */}
      {activeTab === 'catalog' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.paddedSection}>
            {isOwner && (
              <Pressable
                style={styles.catalogCreateButton}
                onPress={() => router.push('/(auth)/pro/offering/edit')}
              >
                <Plus size={16} color={colors.cta} strokeWidth={2.5} />
                <Text style={styles.catalogCreateText}>
                  {t('pro.catalogCreate', { defaultValue: 'Nouvelle activité' })}
                </Text>
              </Pressable>
            )}

            {offerings.length === 0 ? (
              <View style={styles.infoCard}>
                <Text style={styles.placeholderText}>
                  {isOwner
                    ? t('pro.catalogEmptyOwner', { defaultValue: 'Aucune activité au catalogue. Ajoute-en une pour qu\'elle apparaisse sur la carte.' })
                    : t('pro.catalogEmpty', { defaultValue: 'Le catalogue est encore vide.' })}
                </Text>
              </View>
            ) : (
              offerings.map((o) => (
                <Pressable
                  key={o.id}
                  style={styles.catalogCard}
                  onPress={() => router.push(`/(auth)/pro/offering/${o.id}`)}
                >
                  {o.image_url ? (
                    <Image source={{ uri: o.image_url }} style={styles.catalogCardImage} resizeMode="cover" />
                  ) : (
                    <View style={[styles.catalogCardImage, styles.catalogCardPlaceholder]}>
                      <Text style={styles.catalogCardEmoji}>{getSportIcon(o.sport_key)}</Text>
                    </View>
                  )}
                  <View style={styles.catalogCardBody}>
                    <Text style={styles.catalogCardTitle} numberOfLines={1}>{o.title}</Text>
                    <Text style={styles.catalogCardLocation} numberOfLines={1}>{o.location_name}</Text>
                    {o.schedule_text && (
                      <Text style={styles.catalogCardSchedule} numberOfLines={1}>{o.schedule_text}</Text>
                    )}
                  </View>
                </Pressable>
              ))
            )}
          </View>
        </ScrollView>
      )}

      {/* ===== REVIEWS TAB ===== Phase 4 wires this. */}
      {activeTab === 'reviews' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.paddedSection}>
            <View style={styles.infoCard}>
              <Text style={styles.placeholderText}>
                {t('pro.reviewsPlaceholder', { defaultValue: 'Bientôt — les avis des participants apparaîtront ici.' })}
              </Text>
            </View>
          </View>
        </ScrollView>
      )}

      <Modal visible={showFullMap} animationType="slide" onRequestClose={() => setShowFullMap(false)}>
        <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
          <JuntoMapView center={mapCenter} zoom={14} pins={mapPins} />
          <Pressable style={styles.closeMapButton} onPress={() => setShowFullMap(false)} hitSlop={8}>
            <Text style={styles.closeMapText}>✕</Text>
          </Pressable>
          <Pressable
            style={[styles.navigateButton, { bottom: insets.bottom + 24 }]}
            onPress={() => Linking.openURL(`https://www.google.com/maps/dir/?api=1&destination=${pro.primary_lat},${pro.primary_lng}`)}
          >
            <Text style={styles.navigateText}>{t('activity.navigate', { defaultValue: 'Y aller' })}</Text>
          </Pressable>
        </SafeAreaView>
      </Modal>
    </View>
  );
}

function ContactRow({
  icon,
  label,
  onPress,
  styles,
}: {
  icon: React.ReactNode;
  label: string;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <Pressable style={styles.contactRow} onPress={onPress} hitSlop={4}>
      <View style={styles.contactIcon}>{icon}</View>
      <Text style={styles.contactLabel} numberOfLines={1}>{label}</Text>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
  },
  tab: {
    paddingVertical: spacing.sm,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.borderStrong },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '500' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },
  content: {
    paddingBottom: spacing.xl + 32,
  },
  // Sections below the hero get their own horizontal padding so the
  // hero can be edge-to-edge.
  paddedSection: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
  },
  // The gallery carousel has its own horizontal padding so the cards
  // can scroll edge-to-edge; we just need top breathing room.
  galleryWrap: {
    paddingTop: spacing.md,
  },
  infoCard: {
    backgroundColor: 'transparent',
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  heroCard: {
    backgroundColor: 'transparent',
    padding: spacing.lg,
    // No left stripe — the PRO label + the banner above already
    // carry the brand identity; the stripe was visually redundant.
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  // Banner — full-width 3:1 magazine cover above the hero.
  banner: {
    width: '100%',
    aspectRatio: 3,
  },
  tabBarScroll: {
    flexGrow: 0,
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  heroFullBleed: {
    // No horizontal margin — full screen width. Side and bottom borders
    // anchor it visually without a rounded card frame.
    marginHorizontal: 0,
  },
  heroHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
  },
  heroActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  // Small circular avatar — discloses the owner of the pro brand
  // without competing with the pro identity. Tap = jump to the user's
  // personal profile.
  ownerAvatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  ownerAvatarPlaceholder: {
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ownerAvatarInitial: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '800',
  },
  proLabel: {
    color: colors.cta,
    fontSize: fontSizes.xs - 1,
    fontWeight: '800',
    letterSpacing: 1.5,
    marginBottom: spacing.xs - 2,
  },
  heroTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 36,
  },
  tagline: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    fontWeight: '500',
    marginTop: spacing.sm,
    lineHeight: 22,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: spacing.md,
    paddingTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  locationText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    flex: 1,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
  },
  descriptionBody: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    lineHeight: 22,
  },
  descriptionToggle: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    marginTop: spacing.xs,
  },
  contactRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 2,
    paddingVertical: spacing.sm,
  },
  contactIcon: {
    width: 24,
    alignItems: 'center',
  },
  contactLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    flex: 1,
  },
  placeholderText: {
    color: colors.textMuted,
    fontSize: fontSizes.sm,
    fontStyle: 'italic',
  },
  catalogCreateButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.sm,
    borderWidth: 2,
    borderColor: colors.cta,
    marginBottom: spacing.md,
  },
  catalogCreateText: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '700' },
  catalogCard: {
    flexDirection: 'row',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    overflow: 'hidden',
    marginBottom: spacing.sm,
  },
  catalogCardImage: { width: 100, aspectRatio: 1, backgroundColor: colors.background },
  catalogCardPlaceholder: { alignItems: 'center', justifyContent: 'center' },
  catalogCardEmoji: { fontSize: 36 },
  catalogCardBody: { flex: 1, padding: spacing.sm, justifyContent: 'center' },
  catalogCardTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  catalogCardLocation: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2 },
  catalogCardSchedule: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: 2 },
  mapContainer: {
    height: 180,
    borderRadius: radius.md,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  mapTapOverlay: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
  },
  mapNavHint: {
    position: 'absolute', top: spacing.sm, right: spacing.sm,
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm, paddingVertical: 4,
  },
  mapNavHintText: {
    color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  closeMapButton: {
    position: 'absolute', top: spacing.sm + 4, left: spacing.md,
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  closeMapText: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  navigateButton: {
    position: 'absolute', alignSelf: 'center',
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg, paddingVertical: spacing.sm + 2,
    flexDirection: 'row', alignItems: 'center', gap: 6,
  },
  navigateText: {
    color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
});
