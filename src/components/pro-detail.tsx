import { useMemo, useRef, useState, type ComponentRef } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Linking, Modal, Alert, Share, Platform, Dimensions } from 'react-native';
import { Image } from 'expo-image';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Phone, Mail, Globe, Instagram, Facebook, MapPin, Pencil, Navigation, Plus, ExternalLink, ChevronRight, Share2, MessageCircle, X, ImagePlus, LayoutGrid, Star, StarHalf, Camera, Calendar, Clock, Users, BarChart3, Route, Mountain } from 'lucide-react-native';
import { ScrollView as GHScrollView } from 'react-native-gesture-handler';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { UserAvatar } from './user-avatar';
import { FavoriteButton } from './favorite-button';
import { fontSizes, fonts, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import type { ProProfile } from '@/services/pro-service';
import { proOfferingService, type ProOffering } from '@/services/pro-offering-service';
import { proPhotoService, proCommunityPhotoService } from '@/services/pro-photo-service';
import { userService } from '@/services/user-service';
import { useProPhotos } from '@/hooks/use-pro-photos';
import { useAuth } from '@/hooks/use-auth';
import { reviewService, type Review } from '@/services/review-service';
import { ReviewSection } from './review-section';
import { StarRating } from './star-rating';
import { pickAndUploadProPhotos, removeProPhoto, pickAndUploadCommunityPhotos, removeProCommunityPhoto } from '@/utils/pro-photo-upload';
import { getFriendlyError } from '@/utils/friendly-error';
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { JuntoMapView } from './map-view';
import { PhotoGallery } from './photo-gallery';
import { PhotoManager } from './photo-manager';
import { PhotoLightbox } from './photo-lightbox';

const GALLERY_MAX = 25;
const REVIEW_CARD_WIDTH = 220;

export type ProTab = 'info' | 'catalog' | 'pictures' | 'reviews';

// Overview review card. The body is clipped to 5 lines; an invisible copy with
// no line cap measures the real line count (onTextLayout is unreliable on the
// clipped copy under Android), so the card only becomes tappable + shows the
// "Lire l'avis" affordance when the text is actually cut off.
function ReviewMiniCard({
  review,
  styles,
  onOpen,
  moreLabel,
}: {
  review: Review;
  styles: ReturnType<typeof createStyles>;
  onOpen: (review: Review) => void;
  moreLabel: string;
}) {
  const [truncated, setTruncated] = useState(false);
  return (
    <Pressable
      style={styles.reviewMini}
      onPress={() => onOpen(review)}
      disabled={!truncated}
      accessibilityRole={truncated ? 'button' : undefined}
    >
      <View style={styles.reviewMiniHead}>
        <UserAvatar name={review.reviewer_name ?? '?'} avatarUrl={review.reviewer_avatar} size={28} />
        <View style={styles.reviewMiniWho}>
          <Text style={styles.reviewMiniName} numberOfLines={1}>{review.reviewer_name ?? '?'}</Text>
          <View style={styles.reviewMiniMeta}>
            <StarRating rating={review.rating} size={12} />
            <Text style={styles.reviewMiniDate}>{dayjs(review.created_at).locale('fr').format('D MMM YYYY')}</Text>
          </View>
        </View>
      </View>
      {review.body ? (
        <>
          <Text style={styles.reviewMiniBody} numberOfLines={5}>{review.body}</Text>
          {/* Invisible measuring copy at the exact content width (an absolute
              copy with left/right:0 would span the padding box and under-count
              lines). Explicit width + opacity:0 guarantees it lays out, so
              onTextLayout reliably reports the true uncapped line count. */}
          <Text
            style={[styles.reviewMiniBody, styles.reviewMeasure]}
            pointerEvents="none"
            onTextLayout={(e) => setTruncated(e.nativeEvent.lines.length > 5)}
          >
            {review.body}
          </Text>
          {truncated ? <Text style={styles.reviewMiniMore}>{moreLabel}</Text> : null}
        </>
      ) : null}
    </Pressable>
  );
}

interface Props {
  pro: ProProfile;
  isOwner: boolean;
  onEdit?: () => void;
  // When hosted inside the pin drawer (gorhom sheet), the tab bodies must
  // use BottomSheetScrollView so the drag gesture coordinates with the sheet.
  inSheet?: boolean;
  // Present only in the sheet — shows the ✕ close button and animates the
  // sheet shut when tapped.
  onClose?: () => void;
  // Present only in the sheet — expand the sheet to its top snap (e.g. when a
  // tab is selected), Google place-sheet style.
  onExpand?: () => void;
  // Present only in the sheet — reports the header (name · actions · divider)
  // height so ProSheet can pin its first snap point right at the divider.
  onHeaderMeasured?: (height: number) => void;
  // In the sheet, tapping a catalogue offering switches to the RA drawer rather
  // than pushing the full page. On the standalone page this is undefined → push.
  onOpenOffering?: (offering: ProOffering) => void;
}

const COLLAPSED_DESCRIPTION_CHARS = 280;
const PHOTO_H = 240;
const PHOTO_GAP = 6;
const PHOTO_SMALL = (PHOTO_H - PHOTO_GAP) / 2;
const PHOTO_MAX_COLUMNS = 5;
// Stable array identity — a fresh [2] each render makes the (BottomSheet)
// ScrollView reconfigure its sticky header, which can disrupt scrolling.
const STICKY_HEADER_INDICES = [2];

// duration is a Postgres interval serialized as "HH:MM:SS" (e.g. "05:00:00").
// Render it as "5h" / "2h30" / "45min" instead of the raw interval (mirrors
// offering-detail's formatter so the catalogue matches the detail page).
function formatDuration(d: string | null): string | null {
  if (!d) return null;
  const match = d.match(/^(\d+):(\d+):/);
  if (!match) return d;
  const h = parseInt(match[1] ?? '0', 10);
  const m = parseInt(match[2] ?? '0', 10);
  if (h > 0 && m > 0) return `${h}h${m.toString().padStart(2, '0')}`;
  if (h > 0) return `${h}h`;
  return `${m}min`;
}

// Open an external URL, swallowing the rejection Linking.openURL throws on a
// device with no handler (no dialer / mail app) — audit 2026-07-13.
function openLink(url: string): void {
  Linking.openURL(url).catch(() => {});
}
// The tab content is forced to at least this tall so the outer scroll always
// has enough range to slide the header/carousel off and pin the tabs to the
// top (Google collapsing-header). Short tabs just get trailing empty space.
const MIN_TAB_CONTENT_H = Dimensions.get('window').height;

// Display form of a URL — drops the protocol, a leading www., and any trailing
// slash so the row reads "getjunto.app" instead of "https://www.getjunto.app/".
function prettyUrl(url: string): string {
  return url.replace(/^https?:\/\//i, '').replace(/^www\./i, '').replace(/\/+$/, '');
}

type ColPhoto = { id: string; photo_url: string };
// Google-Photos mixed grid: alternating columns — a 2-photo stack, then one
// big square, repeating — consumed left→right up to maxColumns.
function buildPhotoColumns(photos: ColPhoto[], maxColumns: number) {
  const columns: { kind: 'big' | 'stack'; items: ColPhoto[] }[] = [];
  let i = 0;
  let c = 0;
  while (i < photos.length && c < maxColumns) {
    if (c % 2 === 1) {
      columns.push({ kind: 'big', items: [photos[i]!] });
      i += 1;
    } else {
      columns.push({ kind: 'stack', items: photos.slice(i, i + 2) });
      i += 2;
    }
    c += 1;
  }
  return columns;
}

export function ProDetail({ pro, isOwner, onEdit, inSheet = false, onClose, onExpand, onHeaderMeasured, onOpenOffering }: Props) {
  const openOffering = (o: ProOffering) => (onOpenOffering ? onOpenOffering(o) : router.push(`/(auth)/pro/offering/${o.id}`));
  // Selecting a tab expands the sheet to full height, then (once it settles at
  // the '100%' top snap, where scroll is reliably unlocked) scrolls the header +
  // carousel away so the tab bar pins to the top. tabBarTopRef holds the tab
  // bar's y within the content (= header + carousel height, measured onLayout);
  // the delay lets the expand animation finish before we scroll.
  const selectTab = (tab: ProTab) => {
    setActiveTab(tab);
    onExpand?.();
    if (inSheet) {
      setTimeout(() => scrollRef.current?.scrollTo({ y: tabBarTopRef.current, animated: true }), 320);
    }
  };
  const { t } = useTranslation();
  const colors = useColors();
  const { session } = useAuth();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const scrollRef = useRef<ComponentRef<typeof BottomSheetScrollView>>(null);
  const tabBarTopRef = useRef(0);
  const [descExpanded, setDescExpanded] = useState(false);
  const [activeTab, setActiveTab] = useState<ProTab>('info');
  const [showFullMap, setShowFullMap] = useState(false);
  // Fullscreen viewer for the header carousel (indexes into galleryPhotos).
  const [carouselViewerIndex, setCarouselViewerIndex] = useState<number | null>(null);
  const [openReview, setOpenReview] = useState<Review | null>(null);

  const { data: offerings = [] } = useQuery({
    queryKey: ['pro-offerings', 'by-pro', pro.user_id],
    queryFn: () => proOfferingService.getByProId(pro.user_id),
    // Needed on the Aperçu tab (catalogue carousel) and the Catalogue tab.
    enabled: activeTab === 'catalog' || activeTab === 'info',
  });

  const { data: photos = [] } = useProPhotos(pro.user_id);

  // Community photos — anyone's contributions (incl. those posted with a
  // review). Shown in the carousel + Photos tab alongside the owner's gallery.
  const { data: communityPhotos = [] } = useQuery({
    queryKey: ['community-photos', pro.user_id],
    queryFn: () => proCommunityPhotoService.listByPro(pro.user_id),
  });
  const currentUserId = session?.user?.id ?? null;
  const myCommunityCount = communityPhotos.filter((c) => c.contributor_id === currentUserId).length;
  // Merged display list for the carousel — owner gallery first, community after.
  const galleryPhotos = useMemo(
    () => [...photos, ...communityPhotos.map((c) => ({ id: c.id, photo_url: c.photo_url }))],
    [photos, communityPhotos],
  );

  const invalidateCommunity = async () => {
    await queryClient.invalidateQueries({ queryKey: ['community-photos', pro.user_id] });
  };

  const handleCommunityAdd = async () => {
    const remaining = 5 - myCommunityCount;
    if (remaining <= 0) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), t('errors.code.photo_limit', { defaultValue: 'Limite de 5 photos atteinte.' }));
      return;
    }
    try {
      await pickAndUploadCommunityPhotos(pro.user_id, remaining);
      await invalidateCommunity();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };

  const handleCommunityRemove = async (photoId: string) => {
    try {
      await removeProCommunityPhoto(photoId);
      await invalidateCommunity();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };


  const { data: reviews = [] } = useQuery({
    queryKey: ['reviews', 'pro', pro.user_id],
    queryFn: () => reviewService.getForPro(pro.user_id),
  });

  const { data: reviewStats } = useQuery({
    queryKey: ['review-stats', 'pro', pro.user_id],
    queryFn: () => reviewService.getProStats(pro.user_id),
  });

  const invalidatePhotos = async () => {
    await queryClient.invalidateQueries({ queryKey: ['pro-photos', pro.user_id] });
  };

  const handleGalleryAdd = async () => {
    try {
      const remaining = GALLERY_MAX - photos.length;
      await pickAndUploadProPhotos(remaining);
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };

  const handleGalleryRemove = async (photoId: string) => {
    try {
      await removeProPhoto(photoId);
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };

  const handleGalleryReorder = async (orderedIds: string[]) => {
    try {
      await proPhotoService.reorder(orderedIds);
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };

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

  // Action-row handlers (Google place-sheet style). Directions launches the
  // user's own maps app (a deep link, not an embedded map).
  const openDirections = () => {
    const url = Platform.OS === 'ios'
      ? `https://maps.apple.com/?ll=${pro.primary_lat},${pro.primary_lng}&q=${encodeURIComponent(pro.display_name)}`
      : `https://www.google.com/maps/search/?api=1&query=${pro.primary_lat},${pro.primary_lng}`;
    openLink(url);
  };
  const openWebsite = () => {
    if (!pro.website) return;
    openLink(pro.website.startsWith('http') ? pro.website : `https://${pro.website}`);
  };
  const sharePage = () => {
    // Env-driven host (default getjunto.app) so the share URL always matches the
    // App Links intentFilter host — same pattern as activity-detail.
    const webHost = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
    Share.share({ message: `${pro.display_name} sur Junto\nhttps://${webHost}/pro/${pro.user_id}` }).catch(() => {});
  };

  // À propos rows (Google-style grouped grey list). Only the ones the pro
  // filled; WhatsApp is derived from the phone number.
  const aboutItems: { icon: React.ReactNode; text: string; onPress: () => void; external?: boolean }[] = [
    { icon: <MapPin size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: pro.primary_location_name, onPress: openDirections },
    ...(pro.phone ? [{ icon: <Phone size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: pro.phone, onPress: () => openLink(`tel:${pro.phone}`) }] : []),
    ...(pro.phone ? [{ icon: <MessageCircle size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: 'WhatsApp', onPress: () => openLink(`https://wa.me/${pro.phone!.replace(/[^0-9]/g, '')}`) }] : []),
    ...(pro.website ? [{ icon: <Globe size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: prettyUrl(pro.website), onPress: openWebsite, external: true }] : []),
    ...(pro.email ? [{ icon: <Mail size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: pro.email, onPress: () => openLink(`mailto:${pro.email}`) }] : []),
    ...(pro.instagram ? [{ icon: <Instagram size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: 'Instagram', onPress: () => openLink(`https://instagram.com/${pro.instagram!.replace(/^@/, '')}`), external: true }] : []),
    ...(pro.facebook ? [{ icon: <Facebook size={18} color={colors.textSecondary} strokeWidth={2.2} />, text: 'Facebook', onPress: () => openLink(pro.facebook!.startsWith('http') ? pro.facebook! : `https://facebook.com/${pro.facebook!}`), external: true }] : []),
  ];

  // Header star row with half-star precision (4.5 shows 4½ stars). Per
  // position: full from −0.25, half from −0.75 — a half overlays an empty
  // outline so the star keeps its full silhouette.
  const renderHeroStars = (avg: number) => (
    <View style={styles.heroStars}>
      {[1, 2, 3, 4, 5].map((i) => {
        const kind = avg >= i - 0.25 ? 'full' : avg >= i - 0.75 ? 'half' : 'empty';
        return (
          <View key={i} style={styles.heroStarSlot}>
            <Star size={14} color={colors.star} fill={kind === 'full' ? colors.star : 'transparent'} strokeWidth={1.8} />
            {kind === 'half' ? (
              <View style={StyleSheet.absoluteFill}>
                <StarHalf size={14} color={colors.star} fill={colors.star} strokeWidth={1.8} />
              </View>
            ) : null}
          </View>
        );
      })}
    </View>
  );

  // 0 — header (name · rating · actions). In the sheet this is part of the
  // drag handle; on the page it scrolls away above the sticky tab bar.
  const headerNode = (
      <View
        style={styles.sheetHeader}
        onLayout={(e) => onHeaderMeasured?.(Math.round(e.nativeEvent.layout.height))}
      >
        {onClose ? (
          <View style={styles.topBar}>
            <FavoriteButton kind="pro" id={pro.user_id} size={20} style={styles.topBarBtn} />
            <Pressable onPress={sharePage} hitSlop={8} style={styles.topBarBtn} accessibilityLabel={t('common.share', { defaultValue: 'Partager' })}>
              <Share2 size={20} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
            <Pressable onPress={onClose} hitSlop={8} style={styles.topBarBtn} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
              <X size={22} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
          </View>
        ) : null}
        <View style={styles.headerRow}>
          <View style={styles.headerInfo}>
            <Text style={styles.proLabel}>{t('pro.label', { defaultValue: 'Page professionnelle' })}</Text>
            <Text style={styles.headerName} numberOfLines={1}>{pro.display_name}</Text>
            {pro.tagline ? <Text style={styles.tagline}>{pro.tagline}</Text> : null}
            {reviewStats && reviewStats.review_count > 0 ? (
              <Pressable style={styles.heroStatsRow} onPress={() => setActiveTab('reviews')} hitSlop={6}>
                <Text style={styles.heroStatsAvg}>{Number(reviewStats.avg_rating).toFixed(1)}</Text>
                {renderHeroStars(Number(reviewStats.avg_rating))}
                <Text style={styles.heroStatsCount}>({reviewStats.review_count})</Text>
              </Pressable>
            ) : null}
          </View>
          <View style={styles.heroActions}>
            {!inSheet && <FavoriteButton kind="pro" id={pro.user_id} size={22} />}
            {ownerProfile ? (
              <Pressable
                onPress={() => {
                  // The drawer lives in the root portal — it would float over
                  // the pushed page. Dismiss first (same fix as the UA drawer).
                  if (inSheet) onClose?.();
                  router.push(`/(auth)/profile/${pro.user_id}`);
                }}
                hitSlop={6}
                accessibilityLabel={t('pro.ownerProfile', { defaultValue: 'Voir le profil' })}
              >
                {/* Brand page → brand image first: logo → owner photo → initial.
                    Tap still opens the owner's user profile. */}
                {pro.pin_image_url ? (
                  <Image source={{ uri: pro.pin_image_url }} style={styles.ownerAvatar} />
                ) : ownerProfile.avatar_url ? (
                  <Image source={{ uri: ownerProfile.avatar_url }} style={styles.ownerAvatar} />
                ) : (
                  <View style={[styles.ownerAvatar, styles.ownerAvatarPlaceholder]}>
                    <Text style={styles.ownerAvatarInitial}>{ownerProfile.display_name.charAt(0).toUpperCase()}</Text>
                  </View>
                )}
              </Pressable>
            ) : null}
            {isOwner && onEdit ? (
              <Pressable onPress={onEdit} hitSlop={10} accessibilityLabel={t('pro.editPage', { defaultValue: 'Edit pro page' })}>
                <Pencil size={18} color={colors.textSecondary} strokeWidth={2.2} />
              </Pressable>
            ) : null}
          </View>
        </View>
        <GHScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.carouselBleed} contentContainerStyle={styles.actionRow}>
          <ActionButton icon={<Navigation size={18} color={colors.cta} strokeWidth={2.4} />} label={t('pro.directions', { defaultValue: 'Itinéraire' })} onPress={openDirections} styles={styles} />
          {pro.phone ? <ActionButton icon={<Phone size={18} color={colors.cta} strokeWidth={2.4} />} label={t('pro.callAction', { defaultValue: 'Appeler' })} onPress={() => openLink(`tel:${pro.phone}`)} styles={styles} /> : null}
          {pro.website ? <ActionButton icon={<Globe size={18} color={colors.cta} strokeWidth={2.4} />} label={t('pro.websiteShort', { defaultValue: 'Site web' })} onPress={openWebsite} styles={styles} /> : null}
          <ActionButton icon={<Share2 size={18} color={colors.cta} strokeWidth={2.4} />} label={t('common.share', { defaultValue: 'Partager' })} onPress={sharePage} styles={styles} />
          {pro.instagram ? <ActionButton icon={<Instagram size={18} color={colors.cta} strokeWidth={2.4} />} label="Instagram" onPress={() => openLink(`https://instagram.com/${pro.instagram!.replace(/^@/, '')}`)} styles={styles} /> : null}
          {pro.facebook ? <ActionButton icon={<Facebook size={18} color={colors.cta} strokeWidth={2.4} />} label="Facebook" onPress={() => openLink(pro.facebook!.startsWith('http') ? pro.facebook! : `https://facebook.com/${pro.facebook!}`)} styles={styles} /> : null}
          {pro.email ? <ActionButton icon={<Mail size={18} color={colors.cta} strokeWidth={2.4} />} label="Email" onPress={() => openLink(`mailto:${pro.email}`)} styles={styles} /> : null}
        </GHScrollView>
      </View>
  );

  // 1 — carousel (mixed grid + Voir tout / Ajouter). Hidden on the Photos tab.
  // GHScrollView so it scrolls horizontally inside the sheet drag gesture.
  const carouselNode = (
      <View>
      {activeTab !== 'pictures' && galleryPhotos.length > 0 && (
        <GHScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={styles.headerPhotos}
          contentContainerStyle={styles.photoRow}
        >
          {buildPhotoColumns(galleryPhotos, PHOTO_MAX_COLUMNS).map((col, ci) =>
            col.kind === 'big' ? (
              <Pressable key={ci} onPress={() => setCarouselViewerIndex(galleryPhotos.findIndex((g) => g.id === col.items[0]!.id))}>
                <Image source={{ uri: col.items[0]!.photo_url }} style={styles.photoBig} contentFit="cover" />
              </Pressable>
            ) : (
              <View key={ci} style={styles.photoStackCol}>
                {col.items.map((p) => (
                  <Pressable key={p.id} onPress={() => setCarouselViewerIndex(galleryPhotos.findIndex((g) => g.id === p.id))}>
                    <Image source={{ uri: p.photo_url }} style={styles.photoSmall} contentFit="cover" />
                  </Pressable>
                ))}
              </View>
            ),
          )}
          <View style={styles.photoStackCol}>
            <Pressable onPress={() => setActiveTab('pictures')} style={[styles.photoSmall, styles.photoActionTile]}>
              <LayoutGrid size={16} color={colors.cta} strokeWidth={2.4} />
              <Text style={styles.photoActionText}>{t('pro.seeAll', { defaultValue: 'Voir tout' })}</Text>
            </Pressable>
            <Pressable onPress={handleCommunityAdd} style={[styles.photoSmall, styles.photoActionTile]}>
              <View style={styles.addPhotoIconRow}>
                <Camera size={16} color={colors.cta} strokeWidth={2.4} />
                <Plus size={12} color={colors.cta} strokeWidth={3} />
              </View>
              <Text style={styles.photoActionText}>{t('pro.addPhotos', { defaultValue: 'Ajouter des photos' })}</Text>
            </Pressable>
          </View>
        </GHScrollView>
      )}
      </View>
  );

  // 2 — tab bar. In the sheet it's the bottom of the drag handle (always
  // visible); on the page it's sticky (pins to the top when the header scrolls).
  const tabBarNode = (
      <View
        style={styles.tabBarSticky}
        onLayout={(e) => { tabBarTopRef.current = e.nativeEvent.layout.y; }}
      >
      <GHScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.tabBarScroll}
        contentContainerStyle={styles.tabBar}
      >
        {(['info', 'catalog', 'pictures', 'reviews'] as const).map((tab) => {
          const isActiveTab = activeTab === tab;
          return (
            <Pressable
              key={tab}
              style={[styles.tab, isActiveTab && styles.tabActive]}
              onPress={() => selectTab(tab)}
              accessibilityRole="tab"
              accessibilityState={{ selected: isActiveTab }}
              accessibilityLabel={t(`pro.tab.${tab}`, { defaultValue: tab })}
            >
              <Text style={[styles.tabText, isActiveTab && styles.tabTextActive]}>
                {t(`pro.tab.${tab}`, {
                  defaultValue:
                    tab === 'info' ? 'Aperçu'
                      : tab === 'pictures' ? 'Photos'
                      : tab === 'catalog' ? 'Catalogue'
                      : 'Avis',
                })}
              </Text>
            </Pressable>
          );
        })}
      </GHScrollView>
      </View>
  );

  // 3 — tab content. The scrollable body in the sheet; the tail of the single
  // scroll on the page. minHeight guarantees scroll range for short tabs.
  const contentNode = (
      <View style={{ minHeight: MIN_TAB_CONTENT_H }}>

      {/* ===== INFO TAB ===== */}
      {activeTab === 'info' && (
        <View style={styles.content}>
          <View style={styles.paddedSection}>
            {/* ===== CATALOGUE — text-forward taste, swipe → Voir tout ===== */}
            {offerings.length > 0 && (
              <View style={styles.overviewBlock}>
                <View style={styles.catHeaderRow}>
                  <Text style={styles.sectionTitleStrong}>{t('pro.tab.catalog', { defaultValue: 'Catalogue' })}</Text>
                  <Pressable onPress={() => selectTab('catalog')} hitSlop={6}>
                    <Text style={styles.catSeeAll}>{t('pro.seeAll', { defaultValue: 'Voir tout' })} →</Text>
                  </Pressable>
                </View>
                <GHScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.carouselBleed} contentContainerStyle={styles.catCarousel}>
                  {offerings.map((o) => {
                    const accent = sportCategoryColor(o.sport_category, colors.cta);
                    const duration = formatDuration(o.duration);
                    const showRating = !!o.review_count && o.review_count > 0 && o.avg_rating != null;
                    return (
                      <Pressable
                        key={o.id}
                        style={[styles.catMiniCard, { borderLeftColor: accent }]}
                        onPress={() => openOffering(o)}
                      >
                        <View style={styles.catMiniTop}>
                          <View style={[styles.catMiniChip, { borderColor: accent, backgroundColor: accent + '18' }]}>
                            <Text style={[styles.catMiniChipText, { color: accent }]} numberOfLines={1}>
                              {t(`sports.${o.sport_key}`, { defaultValue: o.sport_key })}
                            </Text>
                          </View>
                          {showRating ? (
                            <View style={styles.catMiniRating}>
                              <Text style={styles.catMiniRatingText}>{Number(o.avg_rating).toFixed(1)}</Text>
                              <Star size={11} color={colors.star} fill={colors.star} strokeWidth={1.8} />
                            </View>
                          ) : null}
                        </View>
                        <Text style={styles.catMiniTitle} numberOfLines={2}>{o.title}</Text>
                        {/* Same tinted-pill model as the catalogue cards. */}
                        <View style={styles.expFacts}>
                          {o.level ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <BarChart3 size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{o.level}</Text>
                            </View>
                          ) : null}
                          {duration ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <Clock size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{duration}</Text>
                            </View>
                          ) : null}
                          {o.max_participants ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <Users size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{t('pro.maxParticipants', { defaultValue: `max ${o.max_participants}`, count: o.max_participants })}</Text>
                            </View>
                          ) : null}
                        </View>
                      </Pressable>
                    );
                  })}
                </GHScrollView>
              </View>
            )}

            {/* ===== AVIS — carousel + actions ===== */}
            <View style={styles.overviewBlock}>
              <View style={styles.catHeaderRow}>
                <Text style={styles.sectionTitleStrong}>{t('pro.tab.reviews', { defaultValue: 'Avis' })}</Text>
                {reviews.length > 0 ? (
                  <Pressable onPress={() => selectTab('reviews')} hitSlop={6}>
                    <Text style={styles.catSeeAll}>{t('pro.seeAll', { defaultValue: 'Voir tout' })} →</Text>
                  </Pressable>
                ) : null}
              </View>
              {reviewStats && reviewStats.review_count > 0 ? (
                <View style={styles.reviewSummary}>
                  <Text style={styles.reviewAvg}>{Number(reviewStats.avg_rating).toFixed(1)}</Text>
                  <Star size={14} color={colors.star} fill={colors.star} strokeWidth={1.8} />
                  <Text style={styles.reviewCount}>({reviewStats.review_count})</Text>
                </View>
              ) : null}

              {reviews.length > 0 ? (
                <GHScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.carouselBleed} contentContainerStyle={styles.reviewCarousel}>
                  {reviews.slice(0, 8).map((r) => (
                    <ReviewMiniCard
                      key={r.id}
                      review={r}
                      styles={styles}
                      onOpen={setOpenReview}
                      moreLabel={t('reviews.readOne', { defaultValue: "Lire l'avis" })}
                    />
                  ))}
                </GHScrollView>
              ) : (
                <Text style={styles.placeholderText}>{t('reviews.empty', { defaultValue: 'Aucun avis pour le moment.' })}</Text>
              )}

              {!isOwner ? (
                <View style={styles.overviewButtons}>
                  <Pressable style={styles.primaryBtn} onPress={() => setActiveTab('reviews')}>
                    <Text style={styles.primaryBtnText}>{t('reviews.writeOne', { defaultValue: 'Donner son avis' })}</Text>
                  </Pressable>
                </View>
              ) : null}
            </View>

            {/* ===== À PROPOS — flat (Google-style) ===== */}
            <View style={styles.aboutBlock}>
              <Text style={styles.sectionTitleStrong}>{t('pro.about', { defaultValue: 'À propos' })}</Text>
              {pro.description ? (
                <View style={styles.aboutDesc}>
                  <Text style={styles.descriptionBody}>
                    {descExpanded || !descriptionOverflowing
                      ? description
                      : `${description.slice(0, COLLAPSED_DESCRIPTION_CHARS).trimEnd()}…`}
                  </Text>
                  {descriptionOverflowing ? (
                    <Pressable onPress={() => setDescExpanded((v) => !v)} hitSlop={6}>
                      <Text style={styles.descriptionToggle}>
                        {descExpanded ? t('pro.descSeeLess', { defaultValue: 'Voir moins' }) : t('pro.descSeeMore', { defaultValue: 'Voir plus' })}
                      </Text>
                    </Pressable>
                  ) : null}
                </View>
              ) : null}

              <View style={styles.aboutList}>
                {aboutItems.map((item, i) => {
                  const isFirst = i === 0;
                  const isLast = i === aboutItems.length - 1;
                  return (
                    <Pressable
                      key={i}
                      onPress={item.onPress}
                      hitSlop={2}
                      style={[
                        styles.aboutListRow,
                        isFirst && styles.aboutListTop,
                        isLast && styles.aboutListBottom,
                      ]}
                    >
                      <View style={styles.aboutRowIcon}>{item.icon}</View>
                      <Text style={styles.aboutRowText} numberOfLines={1}>{item.text}</Text>
                      {item.external ? <ExternalLink size={14} color={colors.textMuted} strokeWidth={2} /> : null}
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </View>
        </View>
      )}

      {/* ===== PICTURES TAB ===== Owner sees the PhotoManager (edit in
          place); visitors see the read-only PhotoGallery. Same tab,
          mode switches on ownership. */}
      {activeTab === 'pictures' && (
        <View style={styles.content}>
          {isOwner ? (
            <View style={styles.galleryWrap}>
              {/* Owner's pill adds to THEIR curated gallery (PhotoManager's own
                  header button is hidden — the pill is the single add path). */}
              <Pressable style={styles.addPhotoChip} onPress={handleGalleryAdd}>
                <View style={styles.addPhotoIconRow}>
                  <Camera size={16} color={colors.cta} strokeWidth={2.4} />
                  <Plus size={12} color={colors.cta} strokeWidth={3} />
                </View>
                <Text style={styles.addPhotoChipText}>{t('pro.addPhotos', { defaultValue: 'Ajouter des photos' })}</Text>
              </Pressable>
              <PhotoManager
                photos={photos}
                maxCount={GALLERY_MAX}
                onAdd={handleGalleryAdd}
                onRemove={handleGalleryRemove}
                onReorder={handleGalleryReorder}
                hideAddButton
                extraPhotos={communityPhotos.map((c) => ({ id: c.id, photo_url: c.photo_url }))}
                onRemoveExtra={handleCommunityRemove}
              />
            </View>
          ) : (
            <View style={styles.galleryWrap}>
              <Pressable style={styles.addPhotoChip} onPress={handleCommunityAdd}>
                <View style={styles.addPhotoIconRow}>
                  <Camera size={16} color={colors.cta} strokeWidth={2.4} />
                  <Plus size={12} color={colors.cta} strokeWidth={3} />
                </View>
                <Text style={styles.addPhotoChipText}>{t('pro.addPhotos', { defaultValue: 'Ajouter des photos' })}</Text>
              </Pressable>
              {/* One merged grid — owner gallery + community photos rendered
                  indistinguishably. Delete shows only on tiles the viewer can
                  moderate (their own community contributions). */}
              <PhotoGallery
                photos={galleryPhotos}
                emptyText={t('pro.picturesEmpty', { defaultValue: 'Aucune photo pour le moment.' })}
                canDelete={(p) => {
                  const c = communityPhotos.find((x) => x.id === p.id);
                  return !!c && c.contributor_id === currentUserId;
                }}
                onDelete={(p) => handleCommunityRemove(p.id)}
              />
            </View>
          )}
        </View>
      )}

      {/* ===== CATALOG TAB ===== List of pro_offerings authored by this
          pro. Owner gets a "+ create" button at the top; everyone else
          just sees the cards. Tapping a card routes to the offering
          detail page. */}
      {activeTab === 'catalog' && (
        <View style={styles.content}>
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
              <>
                <Text style={styles.catalogIntro}>
                  {t('pro.catalogIntro', { defaultValue: `Les sorties proposées par ${pro.display_name}` })}
                </Text>
                {offerings.map((o) => {
                  const accent = sportCategoryColor(o.sport_category, colors.cta);
                  const duration = formatDuration(o.duration);
                  const showRating = !!o.review_count && o.review_count > 0 && o.avg_rating != null;
                  return (
                    <Pressable key={o.id} style={styles.expCard} onPress={() => openOffering(o)}>
                      <View style={styles.expImageWrap}>
                        {o.image_url ? (
                          <Image source={{ uri: o.image_url }} style={styles.expImage} contentFit="cover" />
                        ) : (
                          <View style={[styles.expImage, styles.expImageFallback, { backgroundColor: accent }]}>
                            <Text style={styles.expFallbackEmoji}>{getSportIcon(o.sport_key)}</Text>
                          </View>
                        )}
                        <View style={styles.expSportPill}>
                          <Text style={[styles.expSportPillText, { color: accent }]} numberOfLines={1}>
                            {t(`sports.${o.sport_key}`, { defaultValue: o.sport_key })}
                          </Text>
                        </View>
                        {showRating ? (
                          <View style={styles.expRating}>
                            <Text style={styles.expRatingText}>{Number(o.avg_rating).toFixed(1)}</Text>
                            <Star size={11} color="#FFFFFF" fill="#FFFFFF" strokeWidth={1.8} />
                          </View>
                        ) : null}
                      </View>
                      <View style={styles.expBody}>
                        <Text style={styles.expTitle} numberOfLines={2}>{o.title}</Text>

                        {/* Faits clés as tinted pills — scannable tags with
                            breathing room, not a run-on grey line. The light
                            accent tint gives each card its sport colour without
                            the old all-blue density. Same icons as the detail page. */}
                        <View style={styles.expFacts}>
                          {o.level ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <BarChart3 size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{o.level}</Text>
                            </View>
                          ) : null}
                          {duration ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <Clock size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{duration}</Text>
                            </View>
                          ) : null}
                          {o.max_participants ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <Users size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{t('pro.maxParticipants', { defaultValue: `max ${o.max_participants}`, count: o.max_participants })}</Text>
                            </View>
                          ) : null}
                          {o.distance_km != null ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <Route size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{o.distance_km} km</Text>
                            </View>
                          ) : null}
                          {o.elevation_gain_m != null ? (
                            <View style={[styles.expPill, { backgroundColor: accent + '14' }]}>
                              <Mountain size={12} color={accent} strokeWidth={2.2} />
                              <Text style={styles.expPillText}>{o.elevation_gain_m} m</Text>
                            </View>
                          ) : null}
                        </View>

                        {/* Quand / Où — separated block with air above. The
                            schedule is key info and shows IN FULL: it wraps
                            instead of truncating (Scott 2026-07-12). */}
                        <View style={styles.expWhereWhen}>
                          {o.schedule_text ? (
                            <View style={styles.expLineTop}>
                              <Calendar size={13} color={colors.pinMeeting} strokeWidth={2.4} style={styles.expLineIcon} />
                              <Text style={styles.expLineText}>{o.schedule_text}</Text>
                            </View>
                          ) : null}
                          <View style={styles.expLine}>
                            <MapPin size={13} color={colors.pinEnd} strokeWidth={2.4} />
                            <Text style={styles.expLineText} numberOfLines={1}>{o.location_name}</Text>
                          </View>
                        </View>

                        <Text style={[styles.expCta, { color: accent }]}>{t('pro.seeDetail', { defaultValue: 'Voir le détail →' })}</Text>
                      </View>
                    </Pressable>
                  );
                })}
              </>
            )}
          </View>
        </View>
      )}

      {/* ===== REVIEWS TAB ===== Phase 4 wires this. */}
      {activeTab === 'reviews' && (
        <View style={styles.content}>
          <ReviewSection
            targetType="pro"
            targetId={pro.user_id}
            isOwner={isOwner}
            currentUserId={session?.user?.id ?? null}
          />
        </View>
      )}

      </View>
  );

  const modalsNode = (
      <>
      <PhotoLightbox photos={galleryPhotos} index={carouselViewerIndex} onIndexChange={setCarouselViewerIndex} />
      <Modal
        visible={!!openReview}
        transparent
        animationType="fade"
        onRequestClose={() => setOpenReview(null)}
        statusBarTranslucent
      >
        <Pressable style={styles.reviewModalBackdrop} onPress={() => setOpenReview(null)}>
          <Pressable style={styles.reviewModalCard} onPress={() => {}}>
            {openReview ? (
              <>
                <View style={styles.reviewModalHead}>
                  <UserAvatar name={openReview.reviewer_name ?? '?'} avatarUrl={openReview.reviewer_avatar} size={40} />
                  <View style={styles.reviewMiniWho}>
                    <Text style={styles.reviewModalName} numberOfLines={1}>{openReview.reviewer_name ?? '?'}</Text>
                    <View style={styles.reviewMiniMeta}>
                      <StarRating rating={openReview.rating} size={14} />
                      <Text style={styles.reviewMiniDate}>{dayjs(openReview.created_at).locale('fr').format('D MMM YYYY')}</Text>
                    </View>
                  </View>
                  <Pressable onPress={() => setOpenReview(null)} hitSlop={8} style={styles.reviewModalClose}>
                    <X size={20} color={colors.textMuted} />
                  </Pressable>
                </View>
                <ScrollView style={styles.reviewModalBodyScroll} contentContainerStyle={styles.reviewModalBodyContent} showsVerticalScrollIndicator={false}>
                  <Text style={styles.reviewModalBody}>{openReview.body}</Text>
                </ScrollView>
              </>
            ) : null}
          </Pressable>
        </Pressable>
      </Modal>
      <Modal visible={showFullMap} animationType="slide" onRequestClose={() => setShowFullMap(false)}>
        <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
          <JuntoMapView center={mapCenter} zoom={14} pins={mapPins} />
          <Pressable style={styles.closeMapButton} onPress={() => setShowFullMap(false)} hitSlop={8}>
            <Text style={styles.closeMapText}>✕</Text>
          </Pressable>
          <Pressable
            style={[styles.navigateButton, { bottom: insets.bottom + 24 }]}
            onPress={() => openLink(`https://www.google.com/maps/dir/?api=1&destination=${pro.primary_lat},${pro.primary_lng}`)}
          >
            <Text style={styles.navigateText}>{t('activity.navigate', { defaultValue: 'Y aller' })}</Text>
          </Pressable>
        </SafeAreaView>
      </Modal>
      </>
  );

  // One collapsing scroll (Google place-sheet). In the sheet the scroller is
  // gorhom's BottomSheetScrollView with content-panning ON, so gorhom
  // coordinates drag ↔ scroll: at the top of the list a pull drags the sheet in
  // one motion up to full height; once expanded, scrolling slides the header +
  // carousel away and pins the tab bar (sticky index 2) to the top. On the page
  // it's a plain ScrollView with the same collapsing-header behaviour.
  if (inSheet) {
    return (
      <View style={styles.container}>
        <BottomSheetScrollView
          ref={scrollRef}
          contentContainerStyle={styles.scrollContent}
          stickyHeaderIndices={STICKY_HEADER_INDICES}
          showsVerticalScrollIndicator={false}
        >
          {headerNode}
          {carouselNode}
          {tabBarNode}
          {contentNode}
        </BottomSheetScrollView>
        {modalsNode}
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={styles.scrollContent}
        stickyHeaderIndices={STICKY_HEADER_INDICES}
        showsVerticalScrollIndicator={false}
        nestedScrollEnabled
      >
        {headerNode}
        {carouselNode}
        {tabBarNode}
        {contentNode}
      </ScrollView>
      {modalsNode}
    </View>
  );
}

function ContactRow({
  icon,
  label,
  onPress,
  styles,
  colors,
  external,
}: {
  icon: React.ReactNode;
  label: string;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  external?: boolean;
}) {
  return (
    <Pressable style={styles.contactRow} onPress={onPress} hitSlop={4}>
      <View style={styles.contactIcon}>{icon}</View>
      <Text style={styles.contactLabel} numberOfLines={1}>{label}</Text>
      {external
        ? <ExternalLink size={15} color={colors.textSecondary} strokeWidth={2.2} />
        : <ChevronRight size={16} color={colors.textSecondary} strokeWidth={2.2} />}
    </Pressable>
  );
}

// Google-style round action button (icon + label) for the header row.
function ActionButton({
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
    <Pressable style={styles.actionBtn} onPress={onPress} hitSlop={4}>
      <View style={styles.actionBtnIcon}>{icon}</View>
      <Text style={styles.actionBtnLabel} numberOfLines={1}>{label}</Text>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.surfaceAlt },
  scrollContent: { paddingBottom: spacing.xl },
  tabBarSticky: { backgroundColor: colors.surfaceAlt },
  sheetHeader: {
    paddingHorizontal: spacing.lg,
    paddingTop: 2,
    paddingBottom: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
    gap: 2,
  },
  headerRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  headerThumb: { width: 56, height: 56, borderRadius: radius.md, backgroundColor: colors.surfaceAlt },
  headerThumbPlaceholder: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.pinProBackground },
  headerThumbInitial: { color: '#FFFFFF', fontSize: fontSizes.lg, fontWeight: '800' },
  headerInfo: { flex: 1, minWidth: 0 },
  headerName: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  actionRow: { flexDirection: 'row', gap: spacing.lg, paddingTop: spacing.sm, paddingHorizontal: spacing.lg },
  actionBtn: { alignItems: 'center', gap: 4, minWidth: 56 },
  actionBtnIcon: {
    width: 44,
    height: 44,
    borderRadius: 22,
    borderWidth: 1.5,
    borderColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.cta + '12',
  },
  actionBtnLabel: { color: colors.textPrimary, fontSize: 11, fontWeight: '600' },
  overviewRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.sm },
  overviewRowText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  overviewBlock: { paddingTop: spacing.md, gap: spacing.sm },
  overviewHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  overviewLink: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  photoStrip: { gap: spacing.sm, paddingRight: spacing.lg },
  photoThumb: { width: 96, height: 96, borderRadius: radius.md, backgroundColor: colors.surfaceAlt },
  reviewSummary: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  reviewAvg: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  reviewCount: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  headerPhotos: { flexGrow: 0, backgroundColor: colors.surfaceAlt, borderBottomWidth: 1, borderBottomColor: colors.line },
  photoRow: { gap: PHOTO_GAP, paddingHorizontal: spacing.lg, paddingVertical: spacing.sm, alignItems: 'flex-start' },
  photoStackCol: { gap: PHOTO_GAP },
  photoBig: { width: PHOTO_H, height: PHOTO_H, borderRadius: radius.md, backgroundColor: colors.surfaceAlt, ...shadows.card },
  photoSmall: { width: PHOTO_SMALL, height: PHOTO_SMALL, borderRadius: radius.md, backgroundColor: colors.surfaceAlt, ...shadows.card },
  photoActionTile: { alignItems: 'center', justifyContent: 'center', gap: 3, borderWidth: 1, borderColor: colors.borderMuted },
  photoActionText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700', textAlign: 'center' },
  addPhotoIconRow: { flexDirection: 'row', alignItems: 'center', gap: 1 },
  // "Ajouter des photos" chip at the top of the Photos tab — anyone can add.
  addPhotoChip: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radius.full,
    borderWidth: 1.5,
    borderColor: colors.cta,
    marginBottom: spacing.md,
  },
  addPhotoChipText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  topBar: { flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center', gap: spacing.md },
  topBarBtn: { padding: 2 },
  // Cancels the paddedSection's horizontal padding so the carousel spans the
  // full screen width; the first/last card inset comes from paddingHorizontal.
  carouselBleed: { marginHorizontal: -spacing.lg },
  reviewCarousel: { gap: spacing.sm, paddingHorizontal: spacing.lg, paddingBottom: spacing.xs },
  reviewMini: {
    width: REVIEW_CARD_WIDTH,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    padding: spacing.md,
    gap: spacing.xs,
    backgroundColor: colors.surface,
    ...shadows.card,
  },
  reviewMiniHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  reviewMiniWho: { flex: 1, minWidth: 0 },
  reviewMiniName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  reviewMiniMeta: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 2 },
  reviewMiniDate: { color: colors.textMuted, fontSize: fontSizes.xs },
  reviewMiniBody: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 19 },
  reviewMeasure: {
    position: 'absolute',
    top: 0,
    left: 0,
    opacity: 0,
    // content width = card width − 2 borders − 2 horizontal paddings
    width: REVIEW_CARD_WIDTH - 2 - spacing.md * 2,
  },
  reviewMiniMore: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700', marginTop: 2 },
  reviewModalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  reviewModalCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    padding: spacing.lg,
    gap: spacing.md,
    maxHeight: '75%',
    ...shadows.card,
  },
  reviewModalHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  reviewModalName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  reviewModalClose: { padding: spacing.xs },
  reviewModalBodyScroll: { flexGrow: 0 },
  reviewModalBodyContent: { paddingBottom: spacing.xs },
  reviewModalBody: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 23 },
  overviewButtons: { flexDirection: 'row', gap: spacing.sm, paddingTop: spacing.xs },
  ghostBtn: { flex: 1, borderWidth: 1, borderColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  ghostBtnText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  primaryBtn: { flex: 1, backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  primaryBtnText: { color: colors.background, fontSize: fontSizes.sm, fontWeight: '800' },
  aboutBlock: { paddingTop: spacing.lg, gap: spacing.xs },
  aboutDesc: { gap: spacing.xs, marginBottom: spacing.sm },
  // Separate rows with a small gap between them. Corners square EXCEPT the
  // first row's top corners and the last row's bottom corners.
  aboutList: { marginTop: spacing.xs, gap: spacing.xs },
  aboutListRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.surface,
    ...shadows.card,
  },
  aboutListTop: { borderTopLeftRadius: radius.md, borderTopRightRadius: radius.md },
  aboutListBottom: { borderBottomLeftRadius: radius.md, borderBottomRightRadius: radius.md },
  aboutRowIcon: { width: 22, alignItems: 'center' },
  aboutRowText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
  },
  tab: {
    paddingVertical: spacing.sm,
    borderBottomWidth: 3,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.cta },
  tabText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  tabTextActive: { color: colors.cta, fontWeight: '800' },
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
    backgroundColor: colors.surfaceAlt,
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
  // 56 = same size as headerThumb; the header row is taller than this
  // (label+name+tagline+stars), so the bump costs no vertical space.
  ownerAvatar: {
    width: 56,
    height: 56,
    borderRadius: 28,
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
  heroStatsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    marginTop: spacing.xs,
  },
  heroStatsAvg: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
  heroStatsCount: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  heroStars: { flexDirection: 'row', gap: 2 },
  heroStarSlot: { position: 'relative' },
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
  // First section title (e.g. "Avis") — kept uppercase, now bold + black.
  sectionTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
  },
  // Subsequent section titles (e.g. "À propos") — bold + black, no caps.
  sectionTitleStrong: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: '900',
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
    paddingHorizontal: spacing.sm + 2,
    marginTop: spacing.xs,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    backgroundColor: colors.surfaceAlt,
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
  // One-line intro under the tab so the catalogue reads at a glance.
  catalogIntro: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.md },
  // Photo-forward "experience card" — hero image + rating/sport overlays, then
  // title + graceful meta lines + a see-detail affordance. Whole card taps
  // through to the offering page.
  expCard: {
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.lg,
    backgroundColor: colors.surface,
    overflow: 'hidden',
    marginBottom: spacing.md,
    ...shadows.raised,
  },
  expImageWrap: { width: '100%', aspectRatio: 3 / 2, backgroundColor: colors.surfaceAlt },
  expImage: { width: '100%', height: '100%' },
  expImageFallback: { alignItems: 'center', justifyContent: 'center' },
  expFallbackEmoji: { fontSize: 56 },
  expSportPill: {
    position: 'absolute',
    top: spacing.sm,
    left: spacing.sm,
    maxWidth: '75%',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: radius.full,
    backgroundColor: 'rgba(255,255,255,0.95)',
  },
  expSportPillText: { fontSize: fontSizes.xs, fontWeight: '800', letterSpacing: 0.4, textTransform: 'uppercase' },
  expRating: {
    position: 'absolute',
    top: spacing.sm,
    right: spacing.sm,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    backgroundColor: 'rgba(0,0,0,0.6)',
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm,
    paddingVertical: 3,
  },
  expRatingText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '800' },
  expBody: { padding: spacing.md, gap: spacing.sm },
  expTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', lineHeight: 24 },
  expFacts: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.sm },
  expPill: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 9, paddingVertical: 4, borderRadius: radius.full },
  expPillText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700' },
  expWhereWhen: { gap: 4 },
  expLine: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  expLineTop: { flexDirection: 'row', alignItems: 'flex-start', gap: 5 },
  expLineIcon: { marginTop: 2 },
  expLineText: { flex: 1, color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 18 },
  expCta: { fontSize: fontSizes.sm, fontWeight: '800', marginTop: spacing.xs, alignSelf: 'flex-end' },
  // Aperçu catalogue carousel — text-forward mini cards (no photo).
  catHeaderRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  catSeeAll: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  catCarousel: { gap: spacing.sm, paddingHorizontal: spacing.lg, paddingBottom: spacing.xs },
  catMiniCard: {
    width: 200,
    minHeight: 112,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderLeftWidth: 3,
    borderRadius: radius.md,
    padding: spacing.md,
    gap: spacing.xs,
    backgroundColor: colors.surface,
    justifyContent: 'space-between',
    ...shadows.card,
  },
  catMiniTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.xs },
  catMiniChip: { paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.full, borderWidth: 1, flexShrink: 1, minWidth: 0 },
  catMiniChipText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.5, textTransform: 'uppercase' },
  catMiniRating: { flexDirection: 'row', alignItems: 'center', gap: 2 },
  catMiniRatingText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '800' },
  catMiniTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', lineHeight: 20 },
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
