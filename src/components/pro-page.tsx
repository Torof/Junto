import { useMemo, useState } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Linking, Share, Platform } from 'react-native';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import dayjs from 'dayjs';
import {
  X, Share2, Pencil, MapPin, Phone, Globe, Mail, Instagram, Facebook, Navigation, Star, ChevronRight, Camera, Plus,
} from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { UserAvatar } from '@/components/user-avatar';
import { FavoriteButton } from '@/components/favorite-button';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { StarRating } from '@/components/star-rating';
import { useColors } from '@/hooks/use-theme';
import { useProPhotos } from '@/hooks/use-pro-photos';
import { fontSizes, spacing, radius, shadows, glow } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import type { ProProfile } from '@/services/pro-service';
import { proOfferingService, type ProOffering } from '@/services/pro-offering-service';
import { proCommunityPhotoService } from '@/services/pro-photo-service';
import { reviewService } from '@/services/review-service';
import { userService } from '@/services/user-service';
import { sportCategoryColor } from '@/utils/sport-category-color';

// The pro page (Scott 2026-10-25, canvas « Page pro — la sortie d'abord »):
// full page, the photo at its usual height with the identity on it (avatar,
// PRO in gold, name, profession · place, sport labels, rating), the contact
// actions right under, ONE featured outing + a banner to the catalogue, the
// reviews (big rating + two reviews, discreet link), four photo thumbnails,
// about, then the address and links. No tabs: the old tabs live behind the
// links (`?tab=catalog|reviews|pictures`, ProDetail).
//
// « Someone », never « something to book » (UX_UI): the avatar and PRO are
// here, the price only in the featured card, no date anywhere.

export const PRO_GOLD = '#F2B705';
const WHITE = '#FFFFFF';
const COVER_H = 250;
const COLLAPSED_DESCRIPTION_CHARS = 280;

function openLink(url: string): void {
  Linking.openURL(url).catch(() => {});
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

function prettyUrl(url: string): string {
  return url.replace(/^https?:\/\//i, '').replace(/^www\./i, '').replace(/\/+$/, '');
}

interface Props {
  pro: ProProfile;
  isOwner: boolean;
}

export function ProPage({ pro, isOwner }: Props) {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  const [descExpanded, setDescExpanded] = useState(false);

  const { data: offerings = [] } = useQuery({
    queryKey: ['pro-offerings', 'by-pro', pro.user_id],
    queryFn: () => proOfferingService.getByProId(pro.user_id),
  });
  const { data: photos = [] } = useProPhotos(pro.user_id);
  const { data: communityPhotos = [] } = useQuery({
    queryKey: ['community-photos', pro.user_id],
    queryFn: () => proCommunityPhotoService.listByPro(pro.user_id),
  });
  const { data: reviews = [] } = useQuery({
    queryKey: ['reviews', 'pro', pro.user_id],
    queryFn: () => reviewService.getForPro(pro.user_id),
  });
  const { data: reviewStats } = useQuery({
    queryKey: ['review-stats', 'pro', pro.user_id],
    queryFn: () => reviewService.getProStats(pro.user_id),
  });
  const { data: ownerProfile } = useQuery({
    queryKey: ['public-profile', pro.user_id],
    queryFn: () => userService.getPublicProfile(pro.user_id),
  });

  // The cover: the pro's first gallery photo, else the logo, else a tint.
  const coverUrl = photos[0]?.photo_url ?? pro.pin_image_url ?? null;
  const avatarUrl = pro.pin_image_url ?? ownerProfile?.avatar_url ?? null;
  const sportKeys = useMemo(() => {
    const seen: { key: string; category: string }[] = [];
    for (const o of offerings) {
      if (!seen.some((s) => s.key === o.sport_key)) seen.push({ key: o.sport_key, category: o.sport_category });
    }
    return seen.slice(0, 3);
  }, [offerings]);
  const tint = sportCategoryColor(sportKeys[0]?.category, colors.cta);
  const featured: ProOffering | undefined =
    offerings.find((o) => o.id === pro.featured_offering_id) ?? offerings[0];
  const allPhotos = [...photos.map((p) => p.photo_url), ...communityPhotos.map((c) => c.photo_url)];
  const hasRating = !!reviewStats && reviewStats.review_count > 0;

  const openDirections = () => {
    const url = Platform.OS === 'ios'
      ? `https://maps.apple.com/?ll=${pro.primary_lat},${pro.primary_lng}&q=${encodeURIComponent(pro.display_name)}`
      : `https://www.google.com/maps/search/?api=1&query=${pro.primary_lat},${pro.primary_lng}`;
    openLink(url);
  };
  const sharePage = () => {
    const webHost = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
    Share.share({ message: `${pro.display_name} sur askandgo\nhttps://${webHost}/pro/${pro.user_id}` }).catch(() => {});
  };
  const openTab = (tab: 'catalog' | 'reviews' | 'pictures') => router.push(`/(auth)/pro/${pro.user_id}?tab=${tab}`);
  const openOffering = (o: ProOffering) => router.push(`/(auth)/pro/offering/${o.id}`);
  const book = (o: ProOffering) => router.push(`/(auth)/pro/book/${o.id}`);

  const description = pro.description?.trim() ?? '';
  const descriptionOverflowing = description.length > COLLAPSED_DESCRIPTION_CHARS;
  const professionLabel = pro.profession ? t(`pro.profession.${pro.profession}`, { defaultValue: pro.profession }) : null;

  // Contact actions, only the ones the pro filled in — Itinéraire always.
  const actions: { key: string; icon: React.ReactNode; label: string; onPress: () => void }[] = [
    ...(pro.phone ? [{ key: 'phone', icon: <Phone size={15} color={colors.cta} strokeWidth={2.4} />, label: t('pro.callAction', { defaultValue: 'Appeler' }), onPress: () => openLink(`tel:${pro.phone}`) }] : []),
    ...(pro.email ? [{ key: 'email', icon: <Mail size={15} color={colors.cta} strokeWidth={2.4} />, label: t('pro.page.write', { defaultValue: 'Écrire' }), onPress: () => openLink(`mailto:${pro.email}`) }] : []),
    ...(pro.website ? [{ key: 'web', icon: <Globe size={15} color={colors.cta} strokeWidth={2.4} />, label: t('pro.websiteShort', { defaultValue: 'Site web' }), onPress: () => openLink(pro.website!) }] : []),
    { key: 'directions', icon: <Navigation size={15} color={colors.cta} strokeWidth={2.4} />, label: t('pro.directions', { defaultValue: 'Itinéraire' }), onPress: openDirections },
    ...(pro.instagram ? [{ key: 'ig', icon: <Instagram size={15} color={colors.cta} strokeWidth={2.4} />, label: 'Instagram', onPress: () => openLink(pro.instagram!.startsWith('http') ? pro.instagram! : `https://instagram.com/${pro.instagram!.replace(/^@/, '')}`) }] : []),
    ...(pro.facebook ? [{ key: 'fb', icon: <Facebook size={15} color={colors.cta} strokeWidth={2.4} />, label: 'Facebook', onPress: () => openLink(pro.facebook!.startsWith('http') ? pro.facebook! : `https://facebook.com/${pro.facebook}`) }] : []),
  ];

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ paddingBottom: insets.bottom + spacing.xl }} showsVerticalScrollIndicator={false}>
      {/* ===== Cover — the identity sits on the photo ===== */}
      <View style={[styles.cover, { backgroundColor: tint }]}>
        {coverUrl ? (
          <Image source={{ uri: coverUrl }} style={StyleSheet.absoluteFill} contentFit="cover" cachePolicy="memory-disk" transition={150} />
        ) : null}
        <View style={[StyleSheet.absoluteFill, styles.veil]} />

        <View style={[styles.topRow, { top: Math.max(insets.top, 8) + 4 }]}>
          <View style={styles.proBadge}><AppText style={styles.proBadgeText}>PRO</AppText></View>
          <View style={{ flex: 1 }} />
          {isOwner ? (
            <Pressable style={styles.topBtn} onPress={() => router.push('/(auth)/pro/edit')} hitSlop={6} accessibilityLabel={t('pro.editPage', { defaultValue: 'Modifier la page' })}>
              <Pencil size={17} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
          ) : (
            <View style={styles.topBtn}><FavoriteButton kind="pro" id={pro.user_id} size={18} /></View>
          )}
          <Pressable style={styles.topBtn} onPress={sharePage} hitSlop={6} accessibilityLabel={t('common.share', { defaultValue: 'Partager' })}>
            <Share2 size={17} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>
          <Pressable style={styles.topBtn} onPress={() => router.back()} hitSlop={6} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
            <X size={18} color={colors.textPrimary} strokeWidth={2.6} />
          </Pressable>
        </View>

        <View style={styles.identity}>
          <View style={styles.avatarRing}>
            <UserAvatar name={pro.display_name} avatarUrl={avatarUrl} size={58} />
          </View>
          <AppText style={styles.name} numberOfLines={2}>{pro.display_name}</AppText>
          <View style={styles.placeRow}>
            <MapPin size={13} color={WHITE} strokeWidth={2.4} />
            <AppText style={styles.place} numberOfLines={1}>
              {professionLabel ? `${professionLabel} · ` : ''}{pro.primary_location_name}
            </AppText>
          </View>
          {sportKeys.length > 0 ? (
            <View style={styles.labels}>
              {sportKeys.map((s) => (
                <View key={s.key} style={styles.label}>
                  <SportIcon sportKey={s.key} size={12} color={WHITE} />
                  <AppText style={styles.labelText} numberOfLines={1}>{t(`sports.${s.key}`, { defaultValue: s.key })}</AppText>
                </View>
              ))}
            </View>
          ) : null}
          {hasRating ? (
            <Pressable style={styles.ratingRow} onPress={() => openTab('reviews')} hitSlop={6}>
              <Star size={14} color="#FBBF24" fill="#FBBF24" strokeWidth={1.6} />
              <AppText style={styles.ratingAvg}>{Number(reviewStats!.avg_rating).toFixed(1).replace('.', ',')}</AppText>
              <AppText style={styles.ratingCount}>· {t('pro.page.reviewCount', { defaultValue: '{{count}} avis', count: reviewStats!.review_count })}</AppText>
            </Pressable>
          ) : null}
        </View>
      </View>

      {/* ===== Actions ===== */}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.actions}>
        {actions.map((a) => (
          <PressableScale key={a.key} style={styles.action} onPress={a.onPress} accessibilityRole="button">
            {a.icon}
            <AppText style={styles.actionText}>{a.label}</AppText>
          </PressableScale>
        ))}
      </ScrollView>

      {/* ===== One featured outing + the catalogue banner ===== */}
      <View style={styles.head}>
        <AppText style={styles.sec}>{t('pro.page.outings', { defaultValue: 'Sorties encadrées' })}</AppText>
        {featured && offerings.length > 1 ? <AppText style={styles.sub}>{t('pro.page.featured', { defaultValue: 'mise en avant' })}</AppText> : null}
      </View>
      {featured ? (
        <Pressable style={styles.card} onPress={() => openOffering(featured)} accessibilityRole="button">
          <View style={styles.cardTop}>
            <View style={[styles.sportDisc, { backgroundColor: sportCategoryColor(featured.sport_category, colors.cta) }]}>
              <SportIcon sportKey={featured.sport_key} size={20} color={WHITE} />
            </View>
            <View style={{ flex: 1, minWidth: 0 }}>
              <AppText style={styles.cardTitle} numberOfLines={2}>{featured.title}</AppText>
              <AppText style={styles.sub} numberOfLines={1}>
                {[formatDuration(featured.duration), featured.level, featured.location_name].filter(Boolean).join(' · ')}
              </AppText>
            </View>
            {featured.price_eur != null ? (
              <View style={{ alignItems: 'flex-end' }}>
                <AppText style={styles.price}>{Number(featured.price_eur)} €</AppText>
                <AppText style={styles.priceUnit}>{featured.price_unit === 'group' ? t('booking.perGroup', { defaultValue: '/groupe' }) : t('booking.perPerson', { defaultValue: '/pers' })}</AppText>
              </View>
            ) : null}
          </View>
          <View style={styles.cardBottom}>
            {featured.max_participants ? (
              <View style={styles.okChip}><AppText style={styles.okChipText}>{t('pro.page.upTo', { defaultValue: "jusqu'à {{count}} pers.", count: featured.max_participants })}</AppText></View>
            ) : <View />}
            {!isOwner ? (
              <PressableScale style={[styles.book, glow(colors.cta)]} onPress={() => book(featured)} accessibilityRole="button">
                <AppText style={styles.bookText}>{t('booking.bookCta', { defaultValue: 'Réserver' })}</AppText>
              </PressableScale>
            ) : null}
          </View>
        </Pressable>
      ) : isOwner ? (
        <PressableScale style={styles.banner} onPress={() => router.push('/(auth)/pro/offering/edit')} accessibilityRole="button">
          <Plus size={18} color={colors.textPrimary} strokeWidth={2.6} />
          <AppText style={styles.bannerText}>{t('pro.page.firstOuting', { defaultValue: 'Ajoute ta première sortie' })}</AppText>
        </PressableScale>
      ) : (
        <AppText style={[styles.sub, styles.inset]}>{t('pro.page.noOutings', { defaultValue: "Pas encore de sortie au catalogue." })}</AppText>
      )}
      {offerings.length > 1 ? (
        <PressableScale style={styles.banner} onPress={() => openTab('catalog')} accessibilityRole="button">
          <AppText style={styles.bannerText}>{t('pro.page.seeOutings', { defaultValue: 'Voir les {{count}} sorties', count: offerings.length })}</AppText>
          <ChevronRight size={18} color={colors.textPrimary} strokeWidth={2.6} />
        </PressableScale>
      ) : null}

      {/* ===== Reviews ===== */}
      <View style={styles.head}>
        <AppText style={styles.sec}>{t('pro.tab.reviews', { defaultValue: 'Avis' })}</AppText>
        <Pressable onPress={() => openTab('reviews')} hitSlop={6}>
          <AppText style={styles.link}>
            {hasRating
              ? t('pro.page.seeReviews', { defaultValue: 'Voir les {{count}} avis ›', count: reviewStats!.review_count })
              : t('pro.page.reviewsPage', { defaultValue: 'Voir ›' })}
          </AppText>
        </Pressable>
      </View>
      {hasRating ? (
        <View style={styles.ratingBlock}>
          <AppText style={styles.ratingBig}>{Number(reviewStats!.avg_rating).toFixed(1).replace('.', ',')}</AppText>
          <View style={{ gap: 3 }}>
            <StarRating rating={Number(reviewStats!.avg_rating)} size={16} />
            <AppText style={styles.sub}>{t('pro.page.reviewCount', { defaultValue: '{{count}} avis', count: reviewStats!.review_count })}</AppText>
          </View>
        </View>
      ) : (
        <AppText style={[styles.sub, styles.inset]}>{t('reviews.empty', { defaultValue: 'Aucun avis pour le moment.' })}</AppText>
      )}
      {reviews.slice(0, 2).map((r) => (
        <View key={r.id} style={styles.review}>
          <UserAvatar name={r.reviewer_name} avatarUrl={r.reviewer_avatar} size={30} />
          <View style={{ flex: 1, minWidth: 0, gap: 3 }}>
            <View style={styles.reviewHead}>
              <AppText style={styles.reviewName} numberOfLines={1}>{r.reviewer_name}</AppText>
              <StarRating rating={r.rating} size={12} />
            </View>
            <AppText style={styles.sub}>{dayjs(r.created_at).locale(i18n.language).format('MMM YYYY')}</AppText>
            {r.body ? <AppText style={styles.reviewBody} numberOfLines={4}>{r.body}</AppText> : null}
          </View>
        </View>
      ))}

      {/* ===== Photos — four thumbnails, the page behind ===== */}
      <View style={styles.head}>
        <AppText style={styles.sec}>
          {t('pro.tab.pictures', { defaultValue: 'Photos' })}{allPhotos.length > 0 ? <AppText style={styles.sub}>{`  · ${allPhotos.length}`}</AppText> : null}
        </AppText>
        <Pressable onPress={() => openTab('pictures')} hitSlop={6}>
          <AppText style={styles.link}>{allPhotos.length > 0 ? t('pro.seeAll', { defaultValue: 'Voir tout' }) + ' ›' : t('pro.addPhotos', { defaultValue: 'Ajouter des photos' }) + ' ›'}</AppText>
        </Pressable>
      </View>
      {allPhotos.length > 0 ? (
        <View style={styles.thumbs}>
          {allPhotos.slice(0, 4).map((url, i) => {
            const more = i === 3 && allPhotos.length > 4 ? allPhotos.length - 4 : 0;
            return (
              <Pressable key={`${url}-${i}`} style={styles.thumbWrap} onPress={() => openTab('pictures')}>
                <Image source={{ uri: url }} style={styles.thumb} contentFit="cover" cachePolicy="memory-disk" />
                {more > 0 ? <View style={styles.thumbMore}><AppText style={styles.thumbMoreText}>+{more}</AppText></View> : null}
              </Pressable>
            );
          })}
        </View>
      ) : (
        <View style={[styles.inset, { flexDirection: 'row', alignItems: 'center', gap: 6 }]}>
          <Camera size={14} color={colors.textSecondary} strokeWidth={2.2} />
          <AppText style={styles.sub}>{t('pro.page.noPhotos', { defaultValue: 'Pas encore de photo.' })}</AppText>
        </View>
      )}

      {/* ===== About ===== */}
      {(pro.tagline || description) ? (
        <>
          <View style={styles.head}><AppText style={styles.sec}>{t('pro.about', { defaultValue: 'À propos' })}</AppText></View>
          <View style={[styles.inset, { gap: 6 }]}>
            {pro.tagline ? <AppText style={styles.tagline}>{pro.tagline}</AppText> : null}
            {description ? (
              <AppText style={styles.body}>
                {descExpanded || !descriptionOverflowing ? description : `${description.slice(0, COLLAPSED_DESCRIPTION_CHARS).trimEnd()}…`}
              </AppText>
            ) : null}
            {descriptionOverflowing ? (
              <Pressable onPress={() => setDescExpanded((v) => !v)} hitSlop={6}>
                <AppText style={styles.link}>{descExpanded ? t('pro.descSeeLess', { defaultValue: 'Voir moins' }) : t('pro.descSeeMore', { defaultValue: 'Voir plus' })}</AppText>
              </Pressable>
            ) : null}
          </View>
        </>
      ) : null}

      {/* ===== Address and links ===== */}
      <View style={[styles.inset, { marginTop: spacing.md }]}>
        <Pressable style={styles.row} onPress={openDirections}>
          <MapPin size={18} color={colors.textSecondary} strokeWidth={2.2} />
          <AppText style={styles.rowText} numberOfLines={2}>{pro.primary_location_name}</AppText>
          <AppText style={styles.sub}>{t('pro.directions', { defaultValue: 'Itinéraire' })}</AppText>
        </Pressable>
        {pro.website ? (
          <Pressable style={styles.row} onPress={() => openLink(pro.website!)}>
            <Globe size={18} color={colors.textSecondary} strokeWidth={2.2} />
            <AppText style={styles.rowText} numberOfLines={1}>{prettyUrl(pro.website)}</AppText>
          </Pressable>
        ) : null}
        {pro.email ? (
          <Pressable style={styles.row} onPress={() => openLink(`mailto:${pro.email}`)}>
            <Mail size={18} color={colors.textSecondary} strokeWidth={2.2} />
            <AppText style={styles.rowText} numberOfLines={1}>{pro.email}</AppText>
          </Pressable>
        ) : null}
        {pro.phone ? (
          <Pressable style={[styles.row, styles.rowLast]} onPress={() => openLink(`tel:${pro.phone}`)}>
            <Phone size={18} color={colors.textSecondary} strokeWidth={2.2} />
            <AppText style={styles.rowText} numberOfLines={1}>{pro.phone}</AppText>
          </Pressable>
        ) : null}
      </View>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  cover: { height: COVER_H, overflow: 'hidden' },
  veil: { backgroundColor: 'rgba(15,12,9,0.46)' },
  topRow: { position: 'absolute', left: 12, right: 12, flexDirection: 'row', alignItems: 'center', gap: 8 },
  proBadge: { backgroundColor: PRO_GOLD, borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 4 },
  proBadgeText: { color: '#1F1A15', fontSize: 11, fontWeight: '800', letterSpacing: 0.8 },
  topBtn: { width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.92)', alignItems: 'center', justifyContent: 'center' },
  identity: { position: 'absolute', left: 18, right: 18, bottom: 12, gap: 5 },
  avatarRing: { alignSelf: 'flex-start', borderWidth: 3, borderColor: WHITE, borderRadius: 32, marginBottom: 3, ...shadows.card },
  name: { color: WHITE, fontSize: 22, fontWeight: '800', lineHeight: 25, letterSpacing: -0.4, textShadowColor: 'rgba(0,0,0,0.55)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  placeRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  place: { flex: 1, color: WHITE, fontSize: fontSizes.sm - 1, fontWeight: '600', opacity: 0.95, textShadowColor: 'rgba(0,0,0,0.55)', textShadowRadius: 8 },
  labels: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 2 },
  label: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: 'rgba(255,255,255,0.22)', borderRadius: radius.full, paddingHorizontal: 8, paddingVertical: 3 },
  labelText: { color: WHITE, fontSize: 11, fontWeight: '700' },
  ratingRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 1 },
  ratingAvg: { color: WHITE, fontSize: fontSizes.sm - 1, fontWeight: '800' },
  ratingCount: { color: WHITE, fontSize: fontSizes.sm - 1, opacity: 0.9 },
  actions: { flexDirection: 'row', gap: 8, paddingHorizontal: spacing.md, paddingTop: spacing.sm + 4, paddingBottom: 2 },
  action: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: 13, paddingVertical: 9 },
  actionText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  head: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md + 2, paddingTop: spacing.lg - 4, paddingBottom: spacing.sm },
  sec: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', letterSpacing: -0.2 },
  sub: { color: colors.textSecondary, fontSize: fontSizes.xs },
  link: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  inset: { paddingHorizontal: spacing.md + 2 },
  card: { marginHorizontal: spacing.md, backgroundColor: colors.surfaceAlt, borderRadius: 18, padding: spacing.sm + 6, gap: 10 },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  sportDisc: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
  cardTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800', lineHeight: 19 },
  price: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800' },
  priceUnit: { color: colors.textSecondary, fontSize: 11 },
  cardBottom: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  okChip: { backgroundColor: '#E6F4EC', borderRadius: radius.full, paddingHorizontal: 12, paddingVertical: 6 },
  okChipText: { color: '#1E6B45', fontSize: fontSizes.sm - 1, fontWeight: '700' },
  book: { backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: 14, paddingVertical: 8 },
  bookText: { color: colors.onCta, fontSize: fontSizes.sm - 1, fontWeight: '800' },
  banner: { marginHorizontal: spacing.md, marginTop: spacing.sm + 4, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingVertical: 13 },
  bannerText: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  ratingBlock: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: spacing.md + 2, paddingBottom: spacing.sm + 4 },
  ratingBig: { color: colors.textPrimary, fontSize: 30, fontWeight: '800', letterSpacing: -0.5, lineHeight: 34 },
  review: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, paddingHorizontal: spacing.md + 2, paddingBottom: spacing.sm + 4 },
  reviewHead: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  reviewName: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700', flexShrink: 1 },
  reviewBody: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, lineHeight: 18 },
  thumbs: { flexDirection: 'row', gap: 6, paddingHorizontal: spacing.md + 2 },
  thumbWrap: { flex: 1, aspectRatio: 1, borderRadius: 10, overflow: 'hidden', backgroundColor: colors.surfaceAlt },
  thumb: { width: '100%', height: '100%' },
  thumbMore: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(15,12,9,0.5)', alignItems: 'center', justifyContent: 'center' },
  thumbMoreText: { color: WHITE, fontSize: fontSizes.sm, fontWeight: '800' },
  tagline: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700', lineHeight: 21 },
  body: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 11, borderBottomWidth: 1, borderBottomColor: colors.surfaceAlt },
  rowLast: { borderBottomWidth: 0 },
  rowText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
});
