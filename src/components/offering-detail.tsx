import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Share, Modal } from 'react-native';
import { Image } from 'expo-image';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { ScrollView as GHScrollView } from 'react-native-gesture-handler';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { MapPin, Calendar, BarChart3, Users, Clock, Route, Mountain, Share2, X, Star, StarHalf, ImagePlus, Maximize2 } from 'lucide-react-native';
import { JuntoMapView } from './map-view';
import { fontSizes, fonts, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useAuth } from '@/hooks/use-auth';
import type { ProOffering } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { proOfferingPhotoService } from '@/services/pro-photo-service';
import { useProOfferingPhotos } from '@/hooks/use-pro-photos';
import { reviewService } from '@/services/review-service';
import { pickAndUploadProOfferingPhotos, removeProOfferingPhoto } from '@/utils/pro-photo-upload';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { ReviewSection } from './review-section';
import { PhotoLightbox } from './photo-lightbox';

const GALLERY_MAX = 25;
const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

interface Props {
  offering: ProOffering;
  inSheet?: boolean;
  onClose?: () => void;
  onHeaderMeasured?: (height: number) => void;
  // In the sheet, tapping the host switches to the PP drawer rather than pushing
  // the full page (and passes the pro's coordinate so the map can fly to it).
  // On the standalone page this is undefined → push.
  onOpenPro?: (userId: string, coordinate: [number, number]) => void;
}

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

// Single-scroll "place-page" for a pro offering (RA): a compact info header
// (sport chip · rating · title · location · schedule) then bold-titled sections
// — À propos (stats + description + host) → Photos (carousel) → Avis (carousel)
// → Carte. Shared by the drawer (OfferingSheet) and the deep-link page.
export function OfferingDetail({ offering, inSheet = false, onClose, onHeaderMeasured, onOpenPro }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const router = useRouter();
  const { session } = useAuth();
  const queryClient = useQueryClient();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);
  const [showFullMap, setShowFullMap] = useState(false);
  // MarkerViews present at a Mapbox map's INITIAL mount never attach (rnmapbox
  // Android bug) — inject the pin only after the map's first idle.
  const [fullMapReady, setFullMapReady] = useState(false);

  const isOwner = session?.user?.id === offering.pro_id;
  const accent = sportCategoryColor(offering.sport_category, colors.cta);
  const sportLabel = t(`sports.${offering.sport_key}`, { defaultValue: offering.sport_key });

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', offering.pro_id],
    queryFn: () => proService.getById(offering.pro_id),
  });
  const { data: photos = [] } = useProOfferingPhotos(offering.id);
  const { data: reviewStats } = useQuery({
    queryKey: ['review-stats', 'offering', offering.id],
    queryFn: () => reviewService.getOfferingStats(offering.id),
  });

  const invalidatePhotos = async () => {
    await queryClient.invalidateQueries({ queryKey: ['pro-offering-photos', offering.id] });
  };
  const handleGalleryAdd = async () => {
    try {
      await pickAndUploadProOfferingPhotos(offering.id, GALLERY_MAX - photos.length);
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };
  const handleGalleryRemove = async (photoId: string) => {
    try {
      await removeProOfferingPhoto(photoId);
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };

  const sharePage = () => {
    Share.share({ message: `${offering.title} — ${sportLabel}\nhttps://getjunto.app/pro/offering/${offering.id}` }).catch(() => {});
  };

  const proThumbUrl = pro?.pin_image_url ?? null;
  const formattedDuration = formatDuration(offering.duration);
  const showRating = !!reviewStats && reviewStats.review_count > 0;

  type Stat = { id: string; icon: typeof BarChart3; value: string };
  const stats: Stat[] = [{ id: 'level', icon: BarChart3, value: offering.level }];
  if (offering.distance_km != null && offering.distance_km > 0) stats.push({ id: 'distance', icon: Route, value: `${offering.distance_km} km` });
  if (offering.elevation_gain_m != null && offering.elevation_gain_m > 0) stats.push({ id: 'elev', icon: Mountain, value: `${offering.elevation_gain_m} m` });
  if (formattedDuration) stats.push({ id: 'duration', icon: Clock, value: formattedDuration });
  if (offering.max_participants != null) stats.push({ id: 'places', icon: Users, value: `${offering.max_participants}` });

  // Static Mapbox thumbnail centered on the spot — a non-interactive image (no
  // gesture conflict inside the drawer scroll). Tap → fullscreen interactive map.
  const mapUrl = `https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/pin-l+${accent.replace('#', '')}(${offering.lng},${offering.lat})/${offering.lng},${offering.lat},13,0/640x320@2x?access_token=${MAPBOX_TOKEN}`;

  // Full 5-star row with half-star precision (same rendering as the PP header).
  const renderStars = (avg: number) => (
    <View style={styles.starsRow}>
      {[1, 2, 3, 4, 5].map((i) => {
        const kind = avg >= i - 0.25 ? 'full' : avg >= i - 0.75 ? 'half' : 'empty';
        return (
          <View key={i} style={styles.starSlot}>
            <Star size={14} color={colors.cta} fill={kind === 'full' ? colors.cta : 'transparent'} strokeWidth={1.8} />
            {kind === 'half' ? (
              <View style={StyleSheet.absoluteFill}>
                <StarHalf size={14} color={colors.cta} fill={colors.cta} strokeWidth={1.8} />
              </View>
            ) : null}
          </View>
        );
      })}
    </View>
  );

  const openPro = () => {
    if (!pro) return;
    if (onOpenPro) onOpenPro(pro.user_id, [pro.primary_lng, pro.primary_lat]);
    else router.push(`/(auth)/pro/${pro.user_id}`);
  };

  const body = (
    <>
      {/* Header — measured so the drawer peek stops just below it. */}
      <View style={styles.header} onLayout={(e) => onHeaderMeasured?.(Math.round(e.nativeEvent.layout.height))}>
        {inSheet && onClose ? (
          <View style={styles.topBar}>
            <Pressable onPress={sharePage} hitSlop={8} style={styles.topBarBtn} accessibilityLabel={t('common.share', { defaultValue: 'Partager' })}>
              <Share2 size={20} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
            <Pressable onPress={onClose} hitSlop={8} style={styles.topBarBtn} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
              <X size={22} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
          </View>
        ) : null}

        <View style={styles.chipRatingRow}>
          <View style={[styles.sportChip, { borderColor: accent, backgroundColor: accent + '18' }]}>
            <Text style={[styles.sportChipText, { color: accent }]} numberOfLines={1}>{sportLabel}</Text>
          </View>
        </View>
        <Text style={styles.proLine} numberOfLines={1}>
          {t('proOffering.ledByPro', { defaultValue: 'Sortie encadrée par un pro' })}
        </Text>

        <Text style={styles.title}>{offering.title}</Text>
        {showRating ? (
          <View style={styles.ratingRow}>
            <Text style={styles.ratingAvg}>{Number(reviewStats.avg_rating).toFixed(1)}</Text>
            {renderStars(Number(reviewStats.avg_rating))}
            <Text style={styles.ratingCount}>({reviewStats.review_count})</Text>
          </View>
        ) : null}

        <View style={styles.factRow}>
          <MapPin size={15} color={accent} strokeWidth={2.2} />
          <Text style={styles.factText} numberOfLines={2}>{offering.location_name}</Text>
        </View>
        {offering.schedule_text ? (
          <View style={styles.factRow}>
            <Calendar size={15} color={accent} strokeWidth={2.2} />
            <Text style={styles.factText}>{offering.schedule_text}</Text>
          </View>
        ) : null}
      </View>

      {/* À propos — stats + description + host */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('proOffering.about', { defaultValue: 'À propos' })}</Text>
        <View style={styles.statsRow}>
          {stats.map((s) => (
            <View key={s.id} style={styles.statItem}>
              <s.icon size={16} color={accent} strokeWidth={2.4} />
              <Text style={styles.statValue}>{s.value}</Text>
            </View>
          ))}
        </View>
        {offering.description ? <Text style={styles.descBody}>{offering.description}</Text> : null}

        {pro ? (
          <Pressable style={styles.hostCard} onPress={openPro}>
            {proThumbUrl ? (
              <Image source={{ uri: proThumbUrl }} style={styles.hostThumb} />
            ) : (
              <View style={[styles.hostThumb, styles.hostThumbPlaceholder]}>
                <Text style={styles.hostThumbInitial}>{pro.display_name.charAt(0).toUpperCase()}</Text>
              </View>
            )}
            <View style={styles.hostInfo}>
              <Text style={styles.hostLabel}>{t('proOffering.byPro', { defaultValue: 'Proposé par' })}</Text>
              <Text style={styles.hostName} numberOfLines={1}>{pro.display_name}</Text>
            </View>
            <Pressable style={styles.contactBtn} onPress={openPro} hitSlop={6}>
              <Text style={styles.contactBtnText}>{t('proOffering.contact', { defaultValue: 'Contacter' })}</Text>
            </Pressable>
          </Pressable>
        ) : null}
      </View>

      {/* Photos — horizontal carousel */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('proOffering.tab.pictures', { defaultValue: 'Photos' })}</Text>
        {photos.length > 0 || isOwner ? (
          <GHScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.bleed} contentContainerStyle={styles.hCarousel}>
            {photos.map((p, i) => (
              <View key={p.id} style={styles.photoThumbWrap}>
                <Pressable onPress={() => setLightboxIndex(i)}>
                  <Image source={{ uri: p.photo_url }} style={styles.photoThumb} contentFit="cover" />
                </Pressable>
                {isOwner ? (
                  <Pressable style={styles.photoDelete} onPress={() => handleGalleryRemove(p.id)} hitSlop={6}>
                    <X size={12} color={colors.background} strokeWidth={3} />
                  </Pressable>
                ) : null}
              </View>
            ))}
            {isOwner && photos.length < GALLERY_MAX ? (
              <Pressable style={styles.photoAddTile} onPress={handleGalleryAdd}>
                <ImagePlus size={22} color={colors.cta} strokeWidth={2.2} />
                <Text style={styles.photoAddText}>{t('pro.addPhotos', { defaultValue: 'Ajouter' })}</Text>
              </Pressable>
            ) : null}
          </GHScrollView>
        ) : (
          <Text style={styles.emptyText}>{t('proOffering.picturesEmpty', { defaultValue: 'Aucune photo pour le moment.' })}</Text>
        )}
        <PhotoLightbox photos={photos} index={lightboxIndex} onIndexChange={setLightboxIndex} />
      </View>

      {/* Avis — horizontal carousel (summary + composer live inside) */}
      <Text style={[styles.sectionTitle, styles.sectionTitleInset]}>{t('proOffering.tab.reviews', { defaultValue: 'Avis' })}</Text>
      <ReviewSection
        targetType="offering"
        targetId={offering.id}
        isOwner={isOwner}
        currentUserId={session?.user?.id ?? null}
        horizontal
      />

      {/* Carte — locator (no directions CTA: the meeting point is arranged
          privately by the pro). Tap → fullscreen interactive map. */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('proOffering.map', { defaultValue: 'Carte' })}</Text>
        <Pressable style={styles.mapCard} onPress={() => setShowFullMap(true)}>
          <Image source={{ uri: mapUrl }} style={styles.mapImage} contentFit="cover" />
          <View style={styles.mapExpandBadge}>
            <Maximize2 size={15} color={colors.textPrimary} strokeWidth={2.4} />
          </View>
        </Pressable>
      </View>

      {/* Mounted only while open: a Mapbox map mounted hidden inside an RN
          Modal never positions its MarkerViews — fresh mount = pin shows. */}
      {showFullMap && (
        <Modal visible animationType="slide" onRequestClose={() => { setShowFullMap(false); setFullMapReady(false); }}>
          <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
            <JuntoMapView
              center={[offering.lng, offering.lat]}
              zoom={13}
              onBoundsChange={() => setFullMapReady(true)}
              pins={fullMapReady ? [{ id: 'offering', coordinate: [offering.lng, offering.lat], color: accent, label: offering.location_name }] : []}
            />
            <Pressable
              style={[styles.closeMapButton, { top: insets.top + spacing.sm }]}
              onPress={() => { setShowFullMap(false); setFullMapReady(false); }}
              hitSlop={8}
            >
              <X size={20} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
          </SafeAreaView>
        </Modal>
      )}
    </>
  );

  if (inSheet) {
    return (
      <View style={styles.container}>
        <BottomSheetScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
          {body}
        </BottomSheetScrollView>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        {body}
      </ScrollView>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.surfaceAlt },
  scrollContent: { paddingBottom: spacing.xl + 32 },
  header: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xs,
    paddingBottom: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.line,
    gap: spacing.xs,
  },
  topBar: { flexDirection: 'row', justifyContent: 'flex-end', alignItems: 'center', gap: spacing.md },
  topBarBtn: { padding: 2 },
  chipRatingRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  sportChip: { paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.full, borderWidth: 1, flexShrink: 0 },
  sportChipText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  proLine: { color: colors.pinProBackground, fontSize: fontSizes.xs, fontWeight: '700', flexShrink: 1 },
  ratingRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  ratingAvg: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800' },
  ratingCount: { color: colors.textSecondary, fontSize: fontSizes.xs },
  starsRow: { flexDirection: 'row', gap: 2 },
  starSlot: { position: 'relative' },
  title: { color: colors.textPrimary, fontSize: fontSizes.xxl, fontFamily: fonts.title, letterSpacing: -0.5, lineHeight: 34 },
  factRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  factText: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  section: { marginHorizontal: spacing.lg, marginTop: spacing.lg },
  sectionTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '900', marginBottom: spacing.sm },
  sectionTitleInset: { marginHorizontal: spacing.lg, marginTop: spacing.lg },
  // Stats — clean icon + value row, no boxes.
  statsRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.md, marginBottom: spacing.xs },
  statItem: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  statValue: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  descBody: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22, marginTop: spacing.sm },
  hostCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginTop: spacing.md,
    padding: spacing.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    ...shadows.card,
  },
  hostThumb: { width: 44, height: 44, borderRadius: radius.sm, backgroundColor: colors.surfaceAlt },
  hostThumbPlaceholder: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cta },
  hostThumbInitial: { color: '#FFFFFF', fontSize: 18, fontWeight: '800' },
  hostInfo: { flex: 1, minWidth: 0 },
  hostLabel: { color: colors.textMuted, fontSize: fontSizes.xs, textTransform: 'uppercase', letterSpacing: 0.8 },
  hostName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', marginTop: 1 },
  contactBtn: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  contactBtnText: { color: colors.background, fontSize: fontSizes.sm, fontWeight: '800' },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  // `top` set inline from insets — SafeAreaView pads its layout children, but
  // absolute positioning ignores that padding.
  closeMapButton: {
    position: 'absolute',
    left: spacing.md,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  // Horizontal carousels bleed full width.
  bleed: { marginHorizontal: -spacing.lg },
  hCarousel: { gap: spacing.sm, paddingHorizontal: spacing.lg, paddingBottom: spacing.xs },
  photoThumbWrap: { position: 'relative' },
  photoThumb: { width: 150, height: 150, borderRadius: radius.md, backgroundColor: colors.surface, ...shadows.card },
  photoDelete: {
    position: 'absolute',
    top: 6,
    right: 6,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  photoAddTile: {
    width: 150,
    height: 150,
    borderRadius: radius.md,
    borderWidth: 1.5,
    borderColor: colors.cta,
    borderStyle: 'dashed',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
  },
  photoAddText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700' },
  emptyText: { color: colors.textMuted, fontSize: fontSizes.sm, fontStyle: 'italic' },
  mapCard: {
    borderRadius: radius.md,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
    ...shadows.card,
  },
  mapExpandBadge: {
    position: 'absolute',
    bottom: spacing.sm,
    right: spacing.sm,
    width: 30,
    height: 30,
    borderRadius: radius.full,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  mapImage: { width: '100%', aspectRatio: 2 },
});
