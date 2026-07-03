import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Share, Linking } from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { Pencil, MapPin, Calendar, ChevronRight, BarChart3, Users, Clock, Route, Mountain, Share2, X } from 'lucide-react-native';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
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
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { StarRating } from './star-rating';
import { ReviewSection } from './review-section';
import { PhotoGallery } from './photo-gallery';
import { PhotoManager } from './photo-manager';
import { MetaChipsGrid, type MetaChip } from './meta-chips-grid';

const GALLERY_MAX = 25;

interface Props {
  offering: ProOffering;
  // In the drawer (gorhom sheet), the scroller is BottomSheetScrollView and a
  // close/share row overlays the hero; on the /pro/offering/[id] page it's a
  // plain ScrollView with no overlay.
  inSheet?: boolean;
  onClose?: () => void;
  // Drawer only — reports the hero block height so OfferingSheet snaps the peek
  // right below it.
  onHeaderMeasured?: (height: number) => void;
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

// Single-scroll "experience listing" for a pro offering (RA). Its own identity
// vs the tabbed PP: hero → key facts → who hosts it (→ PP) → description →
// photos → reviews, top to bottom. Shared by the drawer (OfferingSheet) and the
// deep-link page.
export function OfferingDetail({ offering, inSheet = false, onClose, onHeaderMeasured }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const router = useRouter();
  const { session } = useAuth();
  const queryClient = useQueryClient();
  const styles = useMemo(() => createStyles(colors), [colors]);

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
  const handleGalleryReorder = async (orderedIds: string[]) => {
    try {
      await proOfferingPhotoService.reorder(offering.id, orderedIds);
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };

  const sharePage = () => {
    Share.share({ message: `${offering.title} — ${sportLabel}\nhttps://getjunto.app/pro/offering/${offering.id}` }).catch(() => {});
  };
  const openDirections = () => {
    Linking.openURL(`https://www.google.com/maps/dir/?api=1&destination=${offering.lat},${offering.lng}`);
  };

  const proThumbUrl = pro?.pin_image_url ?? null;
  const formattedDuration = formatDuration(offering.duration);

  const chips: MetaChip[] = [
    { id: 'level', icon: BarChart3, accent: '#F4642A', label: t('meta.level', { defaultValue: 'Niveau' }), value: offering.level },
  ];
  if (offering.distance_km != null && offering.distance_km > 0) {
    chips.push({ id: 'distance', icon: Route, accent: '#06B6D4', label: t('meta.distance', { defaultValue: 'Distance' }), value: `${offering.distance_km} km` });
  }
  if (offering.elevation_gain_m != null && offering.elevation_gain_m > 0) {
    chips.push({ id: 'elev', icon: Mountain, accent: '#E74C3C', label: t('meta.elevation', { defaultValue: 'D+' }), value: `${offering.elevation_gain_m} m` });
  }
  if (formattedDuration) {
    chips.push({ id: 'duration', icon: Clock, accent: '#A78BFA', label: t('meta.duration', { defaultValue: 'Durée' }), value: formattedDuration });
  }
  if (offering.max_participants != null) {
    chips.push({ id: 'places', icon: Users, accent: '#2ECC71', label: t('meta.places', { defaultValue: 'Places' }), value: `${offering.max_participants}` });
  }

  const body = (
    <>
      {/* Hero region — measured so the drawer peek stops just below it. */}
      <View onLayout={(e) => onHeaderMeasured?.(Math.round(e.nativeEvent.layout.height))}>
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

        {photos[0] ? <Image source={{ uri: photos[0].photo_url }} style={styles.banner} contentFit="cover" /> : null}

        <View style={styles.heroBody}>
          <Text style={[styles.heroSportDecor, { color: accent }]}>{getSportIcon(offering.sport_key)}</Text>
          <Text style={[styles.heroSportLabel, { color: accent }]}>{sportLabel}</Text>
          <Text style={styles.heroTitle}>{offering.title}</Text>
          {reviewStats && reviewStats.review_count > 0 ? (
            <View style={styles.heroStatsRow}>
              <Text style={styles.heroStatsAvg}>{Number(reviewStats.avg_rating).toFixed(1)}</Text>
              <StarRating rating={Number(reviewStats.avg_rating)} size={13} />
              <Text style={styles.heroStatsCount}>({reviewStats.review_count})</Text>
            </View>
          ) : null}

          <View style={styles.heroFacts}>
            <View style={styles.heroRow}>
              <MapPin size={14} color={colors.textPrimary} strokeWidth={2.4} />
              <Text style={styles.heroRowText} numberOfLines={2}>{offering.location_name}</Text>
            </View>
            {offering.schedule_text ? (
              <View style={styles.heroRow}>
                <Calendar size={14} color={colors.textPrimary} strokeWidth={2.4} />
                <Text style={styles.heroRowText}>{offering.schedule_text}</Text>
              </View>
            ) : null}
          </View>
        </View>
      </View>

      {/* Stats chips */}
      <View style={styles.section}>
        <MetaChipsGrid chips={chips} />
      </View>

      {/* Host — "Proposé par {pro}" → PP (the funnel + trust bridge) */}
      {pro ? (
        <Pressable style={styles.hostCard} onPress={() => router.push(`/(auth)/pro/${pro.user_id}`)}>
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
            {pro.tagline ? <Text style={styles.hostTagline} numberOfLines={1}>{pro.tagline}</Text> : null}
          </View>
          <ChevronRight size={20} color={colors.textSecondary} />
        </Pressable>
      ) : null}

      {/* Actions — directions to the spot + (owner) edit */}
      <View style={styles.actionRow}>
        <Pressable style={[styles.actionBtn, { borderColor: accent }]} onPress={openDirections}>
          <Text style={[styles.actionBtnText, { color: accent }]}>{t('pro.directions', { defaultValue: 'Itinéraire' })}</Text>
        </Pressable>
        {isOwner ? (
          <Pressable
            style={styles.actionBtnGhost}
            onPress={() => router.push({ pathname: '/(auth)/pro/offering/edit', params: { id: offering.id } })}
          >
            <Pencil size={16} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.actionBtnGhostText}>{t('common.edit', { defaultValue: 'Modifier' })}</Text>
          </Pressable>
        ) : null}
      </View>

      {/* Description */}
      {offering.description ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('proOffering.description', { defaultValue: 'Description' })}</Text>
          <Text style={styles.descBody}>{offering.description}</Text>
        </View>
      ) : null}

      {/* Photos — inline (no tab) */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('proOffering.tab.pictures', { defaultValue: 'Photos' })}</Text>
        {isOwner ? (
          <PhotoManager
            photos={photos}
            maxCount={GALLERY_MAX}
            onAdd={handleGalleryAdd}
            onRemove={handleGalleryRemove}
            onReorder={handleGalleryReorder}
          />
        ) : (
          <PhotoGallery
            photos={photos}
            emptyText={t('proOffering.picturesEmpty', { defaultValue: 'Aucune photo pour le moment.' })}
          />
        )}
      </View>

      {/* Reviews — inline (no tab) */}
      <ReviewSection
        targetType="offering"
        targetId={offering.id}
        isOwner={isOwner}
        currentUserId={session?.user?.id ?? null}
      />
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
  topBar: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    alignItems: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xs,
    paddingBottom: spacing.xs,
  },
  topBarBtn: { padding: 2 },
  banner: { width: '100%', aspectRatio: 5 / 2, backgroundColor: colors.surface },
  heroBody: { paddingHorizontal: spacing.lg, paddingTop: spacing.md, position: 'relative' },
  heroSportDecor: { position: 'absolute', top: spacing.sm, right: spacing.lg, fontSize: 56, opacity: 0.18 },
  heroSportLabel: { fontSize: fontSizes.xs, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 1.5, marginBottom: spacing.xs },
  heroTitle: { color: colors.textPrimary, fontSize: fontSizes.xxl, fontFamily: fonts.title, letterSpacing: -0.5, lineHeight: 36, paddingRight: 64 },
  heroStatsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginTop: spacing.xs },
  heroStatsAvg: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  heroStatsCount: { color: colors.textSecondary, fontSize: fontSizes.xs },
  heroFacts: { marginTop: spacing.sm, gap: 4, paddingBottom: spacing.md, borderBottomWidth: 1, borderBottomColor: colors.line },
  heroRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  heroRowText: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  section: { marginHorizontal: spacing.lg, marginTop: spacing.md },
  sectionTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '900', marginBottom: spacing.sm },
  descBody: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
  hostCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginHorizontal: spacing.lg,
    marginTop: spacing.md,
    padding: spacing.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  hostThumb: { width: 48, height: 48, borderRadius: radius.sm, backgroundColor: colors.surfaceAlt },
  hostThumbPlaceholder: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cta },
  hostThumbInitial: { color: '#FFFFFF', fontSize: 20, fontWeight: '800' },
  hostInfo: { flex: 1, minWidth: 0 },
  hostLabel: { color: colors.textMuted, fontSize: fontSizes.xs, textTransform: 'uppercase', letterSpacing: 0.8 },
  hostName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', marginTop: 1 },
  hostTagline: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  actionRow: { flexDirection: 'row', gap: spacing.sm, marginHorizontal: spacing.lg, marginTop: spacing.md },
  actionBtn: { flex: 1, borderWidth: 1.5, borderRadius: radius.md, paddingVertical: spacing.sm, alignItems: 'center' },
  actionBtnText: { fontSize: fontSizes.sm, fontWeight: '800' },
  actionBtnGhost: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
  },
  actionBtnGhostText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
});
