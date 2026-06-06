import { Redirect, useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  Image,
  Pressable,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useMemo, useState, useLayoutEffect } from 'react';
import { Pencil, MapPin, Calendar, ChevronRight, BarChart3, Users, Clock, Route, Mountain } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proOfferingService } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { MetaChipsGrid, type MetaChip } from '@/components/meta-chips-grid';

// Public detail view of a pro_offering. Hero mirrors the spontaneous
// activity-detail layout: sport-color banner with a big decorative
// sport icon, white uppercase sport label, big white title; plain
// footer below with location + schedule. Stats live in a brutalist
// MetaChipsGrid card directly under the hero.
export default function ProOfferingDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { session, isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();
  const navigation = useNavigation();
  const [activeTab, setActiveTab] = useState<'info' | 'pictures' | 'reviews'>('info');

  const { data: offering, isLoading } = useQuery({
    queryKey: ['pro-offering', id],
    queryFn: () => proOfferingService.getById(id ?? ''),
    enabled: !!id && isAuthenticated,
  });

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', offering?.pro_id],
    queryFn: () => proService.getById(offering!.pro_id),
    enabled: !!offering?.pro_id,
  });

  // Fill the navbar with the sport icon + offering title so the back
  // button isn't paired with empty space. Same useLayoutEffect pattern
  // as the conversation screen.
  const headerSportIcon = offering ? getSportIcon(offering.sport_key) : '';
  const headerTitle = offering?.title ?? '';
  useLayoutEffect(() => {
    if (!offering) return;
    navigation.setOptions({
      headerTitle: () => (
        <View style={styles.headerRow}>
          <Text style={styles.headerIcon}>{headerSportIcon}</Text>
          <Text style={styles.headerTitleText} numberOfLines={1}>{headerTitle}</Text>
        </View>
      ),
    });
  }, [navigation, offering, headerSportIcon, headerTitle, styles]);

  if (authLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;
  if (!isAuthenticated) return <Redirect href="/(visitor)/login" />;
  if (isSuspended) return <Redirect href="/(visitor)/suspended" />;
  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  if (!offering) {
    return (
      <View style={styles.center}>
        <Text style={styles.notFound}>{t('proOffering.notFound')}</Text>
      </View>
    );
  }

  const isOwner = session?.user?.id === offering.pro_id;
  const accentColor = sportCategoryColor(offering.sport_category, colors.cta);

  const formatDuration = (d: string | null): string | null => {
    if (!d) return null;
    const match = d.match(/^(\d+):(\d+):/);
    if (!match) return d;
    const h = parseInt(match[1] ?? '0', 10);
    const m = parseInt(match[2] ?? '0', 10);
    if (h > 0 && m > 0) return `${h}h${m.toString().padStart(2, '0')}`;
    if (h > 0) return `${h}h`;
    return `${m}min`;
  };

  const formattedDuration = formatDuration(offering.duration);
  const proThumbUrl = pro?.pin_image_url ?? pro?.banner_url ?? null;
  const sportLabel = t(`sports.${offering.sport_key}`, offering.sport_key);

  // Build the chip list. Same per-stat accent palette as activity-detail
  // so the visual language is consistent across spontaneous + catalog.
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

  return (
    <View style={styles.container}>
      {/* Tab bar */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.tabBarScroll}
        contentContainerStyle={styles.tabBar}
      >
        {(['info', 'pictures', 'reviews'] as const).map((tab) => {
          const isActive = activeTab === tab;
          return (
            <Pressable
              key={tab}
              style={[styles.tab, isActive && styles.tabActive]}
              onPress={() => setActiveTab(tab)}
            >
              <Text style={[styles.tabText, isActive && styles.tabTextActive]}>
                {t(`proOffering.tab.${tab}`, {
                  defaultValue: tab === 'info' ? 'Infos' : tab === 'pictures' ? 'Photos' : 'Avis',
                })}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>

      {activeTab === 'info' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          {/* Banner only if the pro uploaded an image. Phase 4 swaps this
              for the gallery's first photo. */}
          {offering.image_url && (
            <Image source={{ uri: offering.image_url }} style={styles.banner} resizeMode="cover" />
          )}

          {/* === HERO === Restrained variant — keeps the structure of
              the activity-detail hero (sport label, decorative icon,
              big title) but drops the full sport-color background.
              Sport identity comes through the accent-colored label
              and a low-opacity decorative emoji. */}
          <View style={styles.heroCard}>
            <View style={styles.heroBanner}>
              <Text style={[styles.heroSportDecor, { color: accentColor }]}>
                {getSportIcon(offering.sport_key)}
              </Text>
              <Text style={[styles.heroSportLabel, { color: accentColor }]}>
                {sportLabel}
              </Text>
              <Text style={styles.heroTitle}>{offering.title}</Text>
            </View>
            <View style={styles.heroFooter}>
              <View style={styles.heroFooterLeft}>
                <View style={styles.heroRow}>
                  <MapPin size={14} color={colors.textPrimary} strokeWidth={2.4} />
                  <Text style={styles.heroRowText} numberOfLines={2}>{offering.location_name}</Text>
                </View>
                {offering.schedule_text && (
                  <View style={styles.heroRow}>
                    <Calendar size={14} color={colors.textPrimary} strokeWidth={2.4} />
                    <Text style={styles.heroRowText}>{offering.schedule_text}</Text>
                  </View>
                )}
              </View>
              {isOwner && (
                <Pressable
                  onPress={() => router.push({ pathname: '/(auth)/pro/offering/edit', params: { id: offering.id } })}
                  hitSlop={10}
                  style={styles.heroEditBtn}
                >
                  <Pencil size={16} color={colors.textSecondary} strokeWidth={2.4} />
                </Pressable>
              )}
            </View>
          </View>

          {/* Stats — brutalist tiled chips, same component the activity
              detail page uses. */}
          <View style={styles.card}>
            <MetaChipsGrid chips={chips} />
          </View>

          {/* Identity card — taps through to pro page */}
          {pro && (
            <Pressable
              style={styles.identityCard}
              onPress={() => router.push(`/(auth)/pro/${pro.user_id}`)}
            >
              {proThumbUrl ? (
                <Image source={{ uri: proThumbUrl }} style={styles.identityThumb} />
              ) : (
                <View style={[styles.identityThumb, styles.identityThumbPlaceholder]}>
                  <Text style={styles.identityThumbInitial}>
                    {pro.display_name.charAt(0).toUpperCase()}
                  </Text>
                </View>
              )}
              <View style={{ flex: 1 }}>
                <Text style={styles.identityLabel}>{t('proOffering.byPro', { defaultValue: 'Proposé par' })}</Text>
                <Text style={styles.identityName} numberOfLines={1}>{pro.display_name}</Text>
                {pro.tagline && (
                  <Text style={styles.identityTagline} numberOfLines={1}>{pro.tagline}</Text>
                )}
              </View>
              <ChevronRight size={20} color={colors.textSecondary} />
            </Pressable>
          )}

          {/* Description */}
          {offering.description && (
            <View style={styles.card}>
              <Text style={styles.section}>{t('proOffering.description')}</Text>
              <Text style={styles.body}>{offering.description}</Text>
            </View>
          )}
        </ScrollView>
      )}

      {activeTab === 'pictures' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.card}>
            <Text style={styles.placeholderText}>
              {t('proOffering.picturesPlaceholder', {
                defaultValue: 'Bientôt — la galerie photo arrivera ici.',
              })}
            </Text>
          </View>
        </ScrollView>
      )}

      {activeTab === 'reviews' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.card}>
            <Text style={styles.placeholderText}>
              {t('proOffering.reviewsPlaceholder', {
                defaultValue: 'Bientôt — les avis des participants apparaîtront ici.',
              })}
            </Text>
          </View>
        </ScrollView>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { paddingBottom: spacing.xl + 32 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  notFound: { color: colors.textSecondary, fontSize: fontSizes.md },

  // Navbar header — sport icon + offering title, replaces the empty
  // title slot so the page reads identified even without scrolling
  // into the hero.
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs + 2,
    maxWidth: 220,
  },
  headerIcon: {
    fontSize: 18,
  },
  headerTitleText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
    flexShrink: 1,
  },

  tabBarScroll: {
    flexGrow: 0,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
    backgroundColor: colors.background,
  },
  tabBar: {
    flexDirection: 'row',
    paddingHorizontal: spacing.md,
  },
  tab: {
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.borderStrong },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '500' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },

  banner: { width: '100%', aspectRatio: 3 },

  // === Hero — sport-color banner on top, plain footer below.
  // Mirrors activity-detail.tsx heroCard/heroBanner/heroFooter.
  heroCard: {
    marginTop: spacing.md,
    marginHorizontal: spacing.md,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    overflow: 'hidden',
  },
  heroBanner: {
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    paddingBottom: spacing.md,
    position: 'relative',
  },
  // Decorative sport emoji at top-right. Same low opacity as the
  // activity-detail decor so the page reads as quietly sport-flavored
  // instead of shouting the category color.
  heroSportDecor: {
    position: 'absolute',
    top: spacing.sm,
    right: spacing.md,
    fontSize: 56,
    opacity: 0.18,
  },
  heroSportLabel: {
    fontSize: fontSizes.xs,
    fontWeight: '800',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
    marginBottom: spacing.xs,
  },
  heroTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 36,
    paddingRight: 64, // leave room for the decorative sport icon
  },
  heroFooter: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    gap: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  heroFooterLeft: { flex: 1 },
  heroRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, paddingVertical: 4 },
  heroRowText: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  heroEditBtn: {
    width: 32,
    height: 32,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    alignItems: 'center',
    justifyContent: 'center',
  },

  identityCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginTop: spacing.md,
    marginHorizontal: spacing.md,
    padding: spacing.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  identityThumb: { width: 48, height: 48, borderRadius: radius.sm, backgroundColor: colors.background },
  identityThumbPlaceholder: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cta },
  identityThumbInitial: { color: '#FFFFFF', fontSize: 20, fontWeight: '800' },
  identityLabel: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
  },
  identityName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', marginTop: 1 },
  identityTagline: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },

  card: {
    marginHorizontal: spacing.md,
    marginTop: spacing.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  section: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
  },
  body: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
  placeholderText: { color: colors.textMuted, fontSize: fontSizes.sm, fontStyle: 'italic' },
});
