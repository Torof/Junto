import { useMemo, useState } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Share } from 'react-native';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import dayjs from 'dayjs';
import { X, Share2, Pencil, Star, ChevronRight, Clock, BarChart3, MapPin, Users, Camera } from 'lucide-react-native';
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
import type { ProOffering } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { proOfferingPhotoService, proCommunityPhotoService } from '@/services/pro-photo-service';
import { reviewService } from '@/services/review-service';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { PRO_GOLD, PRO_GOLD_INK } from '@/constants/pin-style';

// The pro outing sheet, as a full page (Scott 2026-10-25, same canvas as the
// pro page). « Something to book », never « someone » (UX_UI): the sport
// chip up on the photo, only the title and rating on it, the price as a white
// tag under the gold SORTIE ENCADRÉE pill; the pro appears as a « par » strip
// under the photo; the facts in a 2×2 grid; about; gear provided / to bring;
// reviews of this outing; four photos; the sticky price + Réserver bar. The
// slots are chosen behind Réserver, never on the page.

const WHITE = '#FFFFFF';
const COVER_H = 250;
const COLLAPSED_DESCRIPTION_CHARS = 280;

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

interface Props {
  offering: ProOffering;
  isOwner: boolean;
}

export function OfferingPage({ offering, isOwner }: Props) {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();
  const [descExpanded, setDescExpanded] = useState(false);
  const accent = sportCategoryColor(offering.sport_category, colors.cta);

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', offering.pro_id],
    queryFn: () => proService.getById(offering.pro_id),
  });
  const { data: proStats } = useQuery({
    queryKey: ['review-stats', 'pro', offering.pro_id],
    queryFn: () => reviewService.getProStats(offering.pro_id),
  });
  const { data: proPhotos = [] } = useProPhotos(offering.pro_id);
  const { data: photos = [] } = useQuery({
    queryKey: ['pro-offering-photos', offering.id],
    queryFn: () => proOfferingPhotoService.listByOffering(offering.id),
  });
  const { data: communityPhotos = [] } = useQuery({
    queryKey: ['offering-community-photos', offering.id],
    queryFn: () => proCommunityPhotoService.listByOffering(offering.id),
  });
  const { data: reviews = [] } = useQuery({
    queryKey: ['reviews', 'offering', offering.id],
    queryFn: () => reviewService.getForOffering(offering.id),
  });
  const { data: stats } = useQuery({
    queryKey: ['review-stats', 'offering', offering.id],
    queryFn: () => reviewService.getOfferingStats(offering.id),
  });

  const allPhotos = [...photos.map((p) => p.photo_url), ...communityPhotos.map((c) => c.photo_url)];
  const coverUrl = offering.image_url ?? allPhotos[0] ?? proPhotos[0]?.photo_url ?? pro?.pin_image_url ?? null;
  const hasRating = !!stats && stats.review_count > 0;
  const description = offering.description?.trim() ?? '';
  const descriptionOverflowing = description.length > COLLAPSED_DESCRIPTION_CHARS;
  const duration = formatDuration(offering.duration);
  const priceUnit = offering.price_unit === 'group'
    ? t('booking.perGroup', { defaultValue: '/groupe' })
    : t('booking.perPerson', { defaultValue: '/pers' });

  const sharePage = () => {
    const webHost = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
    Share.share({ message: `${offering.title} — ${offering.pro_name} sur askandgo\nhttps://${webHost}/pro/offering/${offering.id}` }).catch(() => {});
  };
  const openPro = () => router.push(`/(auth)/pro/${offering.pro_id}`);
  const openOld = () => router.push(`/(auth)/pro/offering/${offering.id}?tab=details`);
  const openReviews = () => router.push(`/(auth)/pro/offering/${offering.id}?tab=reviews`);
  const book = () => router.push(`/(auth)/pro/book/${offering.id}`);

  const facts: { key: string; icon: React.ReactNode; label: string; value: string }[] = [
    ...(duration ? [{ key: 'duration', icon: <Clock size={16} color={accent} strokeWidth={2.4} />, label: t('proOffering.page.duration', { defaultValue: 'Durée' }), value: duration }] : []),
    ...(offering.level ? [{ key: 'level', icon: <BarChart3 size={16} color={accent} strokeWidth={2.4} />, label: t('proOffering.page.level', { defaultValue: 'Niveau' }), value: offering.level }] : []),
    { key: 'place', icon: <MapPin size={16} color={accent} strokeWidth={2.4} />, label: t('proOffering.page.place', { defaultValue: 'Lieu' }), value: offering.location_name },
    ...(offering.max_participants ? [{ key: 'group', icon: <Users size={16} color={accent} strokeWidth={2.4} />, label: t('proOffering.page.group', { defaultValue: 'Groupe' }), value: t('pro.page.upTo', { defaultValue: "jusqu'à {{count}} pers.", count: offering.max_participants }) }] : []),
  ];

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={{ paddingBottom: insets.bottom + (isOwner ? spacing.xl : 110) }} showsVerticalScrollIndicator={false}>
        {/* ===== Cover — the title and the price, nothing else ===== */}
        <View style={[styles.cover, { backgroundColor: accent }]}>
          {coverUrl ? (
            <Image source={{ uri: coverUrl }} style={StyleSheet.absoluteFill} contentFit="cover" cachePolicy="memory-disk" transition={150} />
          ) : null}
          <View style={[StyleSheet.absoluteFill, styles.veil]} />

          <View style={[styles.topRow, { top: Math.max(10, insets.top - 14) }]}>
            <View style={[styles.sportChip, { backgroundColor: accent }]}>
              <SportIcon sportKey={offering.sport_key} size={13} color={WHITE} />
              <AppText style={styles.sportChipText}>{t(`sports.${offering.sport_key}`, { defaultValue: offering.sport_key }).toUpperCase()}</AppText>
            </View>
            <View style={{ flex: 1 }} />
            {isOwner ? (
              <Pressable style={styles.topBtn} onPress={() => router.push(`/(auth)/pro/offering/edit?id=${offering.id}`)} hitSlop={6} accessibilityLabel={t('proOffering.edit', { defaultValue: "Modifier l'activité" })}>
                <Pencil size={17} color={colors.textPrimary} strokeWidth={2.4} />
              </Pressable>
            ) : (
              <View style={styles.topBtn}><FavoriteButton kind="offering" id={offering.id} size={18} /></View>
            )}
            <Pressable style={styles.topBtn} onPress={sharePage} hitSlop={6} accessibilityLabel={t('common.share', { defaultValue: 'Partager' })}>
              <Share2 size={17} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
            <Pressable style={styles.topBtn} onPress={() => router.back()} hitSlop={6} accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}>
              <X size={18} color={colors.textPrimary} strokeWidth={2.6} />
            </Pressable>
          </View>

          <View style={styles.bottomRow}>
            <View style={{ flex: 1, minWidth: 0, gap: 5 }}>
              <AppText style={styles.title} numberOfLines={3}>{offering.title}</AppText>
              {hasRating ? (
                <View style={styles.ratingRow}>
                  <Star size={14} color="#FBBF24" fill="#FBBF24" strokeWidth={1.6} />
                  <AppText style={styles.ratingAvg}>{Number(stats!.avg_rating).toFixed(1).replace('.', ',')}</AppText>
                  <AppText style={styles.ratingCount}>· {t('pro.page.reviewCount', { defaultValue: '{{count}} avis', count: stats!.review_count })}</AppText>
                </View>
              ) : null}
            </View>
            <View style={{ alignItems: 'flex-end', gap: 6 }}>
              <View style={styles.guidedPill}><AppText style={styles.guidedPillText}>{t('proOffering.page.guided', { defaultValue: 'SORTIE ENCADRÉE' })}</AppText></View>
              {offering.price_eur != null ? (
                <View style={styles.priceTag}>
                  <AppText style={styles.priceTagText}>{Number(offering.price_eur)} € <AppText style={styles.priceTagUnit}>{priceUnit}</AppText></AppText>
                </View>
              ) : null}
            </View>
          </View>
        </View>

        {/* ===== « par » — the pro, towards the pro page ===== */}
        <Pressable style={styles.byRow} onPress={openPro} accessibilityRole="button">
          <UserAvatar name={pro?.display_name ?? offering.pro_name} avatarUrl={pro?.pin_image_url ?? null} size={36} />
          <View style={{ flex: 1, minWidth: 0, gap: 1 }}>
            <AppText style={styles.byName} numberOfLines={1}>{t('proOffering.page.by', { defaultValue: 'par {{name}}', name: pro?.display_name ?? offering.pro_name })}</AppText>
            <AppText style={styles.sub} numberOfLines={1}>
              {[
                pro?.profession ? t(`pro.profession.${pro.profession}`, { defaultValue: pro.profession }) : null,
                pro?.primary_location_name ?? null,
                proStats && proStats.review_count > 0 ? `${Number(proStats.avg_rating).toFixed(1).replace('.', ',')} (${proStats.review_count})` : null,
              ].filter(Boolean).join(' · ')}
            </AppText>
          </View>
          <ChevronRight size={18} color={colors.textSecondary} strokeWidth={2.4} />
        </Pressable>

        {/* ===== Facts, 2 × 2 ===== */}
        <View style={styles.facts}>
          {facts.map((f) => (
            <View key={f.key} style={styles.fact}>
              <View style={styles.factIcon}>{f.icon}</View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <AppText style={styles.sub}>{f.label}</AppText>
                <AppText style={styles.factValue} numberOfLines={2}>{f.value}</AppText>
              </View>
            </View>
          ))}
        </View>

        {/* ===== About ===== */}
        {description ? (
          <>
            <View style={styles.head}><AppText style={styles.sec}>{t('proOffering.about', { defaultValue: 'À propos' })}</AppText></View>
            <View style={[styles.inset, { gap: 6 }]}>
              <AppText style={styles.body}>
                {descExpanded || !descriptionOverflowing ? description : `${description.slice(0, COLLAPSED_DESCRIPTION_CHARS).trimEnd()}…`}
              </AppText>
              {descriptionOverflowing ? (
                <Pressable onPress={() => setDescExpanded((v) => !v)} hitSlop={6}>
                  <AppText style={styles.link}>{descExpanded ? t('pro.descSeeLess', { defaultValue: 'Voir moins' }) : t('pro.descSeeMore', { defaultValue: 'Voir plus' })}</AppText>
                </Pressable>
              ) : null}
            </View>
          </>
        ) : null}

        {/* ===== Gear ===== */}
        {(offering.equipment_provided?.length > 0 || offering.equipment_required?.length > 0) ? (
          <>
            <View style={styles.head}><AppText style={styles.sec}>{t('proOffering.sectionEquipment', { defaultValue: 'Matériel' })}</AppText></View>
            <View style={styles.gear}>
              {offering.equipment_provided?.length > 0 ? (
                <View style={styles.gearCol}>
                  <AppText style={styles.gearLabel}>{t('proOffering.equipProvidedLabel', { defaultValue: 'Fourni' })}</AppText>
                  {offering.equipment_provided.map((g, i) => (
                    <View key={`p-${i}`} style={styles.gearLine}><View style={[styles.dot, { backgroundColor: colors.cta }]} /><AppText style={styles.gearText}>{g}</AppText></View>
                  ))}
                </View>
              ) : null}
              {offering.equipment_required?.length > 0 ? (
                <View style={styles.gearCol}>
                  <AppText style={styles.gearLabel}>{t('proOffering.equipRequiredLabel', { defaultValue: 'À prévoir' })}</AppText>
                  {offering.equipment_required.map((g, i) => (
                    <View key={`r-${i}`} style={styles.gearLine}><View style={[styles.dot, { backgroundColor: colors.textMuted }]} /><AppText style={styles.gearText}>{g}</AppText></View>
                  ))}
                </View>
              ) : null}
            </View>
          </>
        ) : null}

        {/* ===== Reviews of this outing ===== */}
        <View style={styles.head}>
          <AppText style={styles.sec}>{t('proOffering.tab.reviews', { defaultValue: 'Avis' })}</AppText>
          <Pressable onPress={openReviews} hitSlop={6}>
            <AppText style={styles.link}>
              {hasRating
                ? t('pro.page.seeReviews', { defaultValue: 'Voir les {{count}} avis ›', count: stats!.review_count })
                : t('pro.page.reviewsPage', { defaultValue: 'Voir ›' })}
            </AppText>
          </Pressable>
        </View>
        {hasRating ? (
          <View style={styles.ratingBlock}>
            <AppText style={styles.ratingBig}>{Number(stats!.avg_rating).toFixed(1).replace('.', ',')}</AppText>
            <View style={{ gap: 3 }}>
              <StarRating rating={Number(stats!.avg_rating)} size={16} />
              <AppText style={styles.sub}>{t('pro.page.reviewCount', { defaultValue: '{{count}} avis', count: stats!.review_count })}</AppText>
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

        {/* ===== Photos ===== */}
        <View style={styles.head}>
          <AppText style={styles.sec}>
            {t('proOffering.tab.pictures', { defaultValue: 'Photos' })}{allPhotos.length > 0 ? <AppText style={styles.sub}>{`  · ${allPhotos.length}`}</AppText> : null}
          </AppText>
          <Pressable onPress={openOld} hitSlop={6}>
            <AppText style={styles.link}>{allPhotos.length > 0 ? t('pro.seeAll', { defaultValue: 'Voir tout' }) + ' ›' : t('pro.addPhotos', { defaultValue: 'Ajouter des photos' }) + ' ›'}</AppText>
          </Pressable>
        </View>
        {allPhotos.length > 0 ? (
          <View style={styles.thumbs}>
            {allPhotos.slice(0, 4).map((url, i) => {
              const more = i === 3 && allPhotos.length > 4 ? allPhotos.length - 4 : 0;
              return (
                <Pressable key={`${url}-${i}`} style={styles.thumbWrap} onPress={openOld}>
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
      </ScrollView>

      {/* ===== Sticky: the price and Réserver, under the thumb ===== */}
      {!isOwner ? (
        <View style={[styles.sticky, { paddingBottom: Math.max(insets.bottom, spacing.sm) + spacing.sm }]}>
          <View style={{ flex: 1 }}>
            {offering.price_eur != null ? (
              <AppText style={styles.stickyPrice}>{Number(offering.price_eur)} € <AppText style={styles.stickyUnit}>{priceUnit}</AppText></AppText>
            ) : null}
            <AppText style={styles.sub}>{t('booking.paySite', { defaultValue: 'Paiement sur place' })}</AppText>
          </View>
          <PressableScale style={[styles.book, glow(colors.cta)]} onPress={book} accessibilityRole="button">
            <AppText style={styles.bookText}>{t('booking.bookCta', { defaultValue: 'Réserver' })}</AppText>
          </PressableScale>
        </View>
      ) : null}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  cover: { height: COVER_H, overflow: 'hidden' },
  veil: { backgroundColor: 'rgba(15,12,9,0.46)' },
  topRow: { position: 'absolute', left: 12, right: 12, flexDirection: 'row', alignItems: 'center', gap: 8 },
  sportChip: { flexDirection: 'row', alignItems: 'center', gap: 5, borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 4 },
  sportChipText: { color: WHITE, fontSize: 11, fontWeight: '800', letterSpacing: 0.3 },
  topBtn: { width: 34, height: 34, borderRadius: 17, backgroundColor: 'rgba(255,255,255,0.92)', alignItems: 'center', justifyContent: 'center' },
  bottomRow: { position: 'absolute', left: 18, right: 18, bottom: 14, flexDirection: 'row', alignItems: 'flex-end', gap: 12 },
  title: { color: WHITE, fontSize: 24, fontWeight: '800', lineHeight: 27, letterSpacing: -0.4, textShadowColor: 'rgba(0,0,0,0.55)', textShadowRadius: 8, textShadowOffset: { width: 0, height: 1 } },
  ratingRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  ratingAvg: { color: WHITE, fontSize: fontSizes.sm - 1, fontWeight: '800' },
  ratingCount: { color: WHITE, fontSize: fontSizes.sm - 1, opacity: 0.9 },
  guidedPill: { backgroundColor: PRO_GOLD, borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 4 },
  guidedPillText: { color: PRO_GOLD_INK, fontSize: 11, fontWeight: '800', letterSpacing: 0.8 },
  priceTag: { backgroundColor: WHITE, borderRadius: radius.full, paddingHorizontal: 12, paddingVertical: 7, ...shadows.card },
  priceTagText: { color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '800' },
  priceTagUnit: { color: colors.textSecondary, fontSize: 11, fontWeight: '600' },
  byRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginHorizontal: spacing.md, marginTop: spacing.sm + 4 },
  byName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800' },
  sub: { color: colors.textSecondary, fontSize: fontSizes.xs },
  facts: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginHorizontal: spacing.md, marginTop: spacing.sm + 4 },
  fact: { width: '48.5%', flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: colors.surfaceAlt, borderRadius: 14, paddingHorizontal: 12, paddingVertical: 10 },
  factIcon: { width: 30, height: 30, borderRadius: 15, backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center' },
  factValue: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  head: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md + 2, paddingTop: spacing.lg - 4, paddingBottom: spacing.sm },
  sec: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', letterSpacing: -0.2 },
  link: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  inset: { paddingHorizontal: spacing.md + 2 },
  body: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  gear: { flexDirection: 'row', gap: 14, paddingHorizontal: spacing.md + 2 },
  gearCol: { flex: 1, gap: 6 },
  gearLabel: { color: colors.textSecondary, fontSize: 11, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  gearLine: { flexDirection: 'row', alignItems: 'flex-start', gap: 8 },
  dot: { width: 6, height: 6, borderRadius: 3, marginTop: 7 },
  gearText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
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
  sticky: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    backgroundColor: colors.surface, borderTopWidth: 1, borderTopColor: colors.lineStrong,
    paddingHorizontal: spacing.md + 2, paddingTop: spacing.sm + 2,
  },
  stickyPrice: { color: colors.textPrimary, fontSize: fontSizes.lg + 2, fontWeight: '800', letterSpacing: -0.3 },
  stickyUnit: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600' },
  book: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 5, paddingHorizontal: spacing.lg + 4 },
  bookText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '800' },
});
