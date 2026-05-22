import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
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
import { useMemo, useState } from 'react';
import { Pencil, MapPin, Clock, Users, Calendar, TrendingUp, Mountain, ChevronRight } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proOfferingService } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';

// Public detail view of a pro_offering.
//
// Layout:
//   - Banner (image or sport-emoji placeholder)
//   - Hero card: big title, sport emoji, sport-color accent stripe,
//     compact location/schedule rows, chips for level/distance/elevation
//   - Identity card: "Par {pro name}" with thumbnail, tagline, chevron —
//     taps through to /pro/[id] where contact links live
//   - Tab bar: Infos / Photos / Avis (Photos + Avis are Phase 4)
//   - Infos tab: description + secondary meta (duration, max participants)
export default function ProOfferingDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { session, isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();
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

  return (
    <View style={styles.container}>
      {/* Tab bar — mirror the pro page's tab pattern. */}
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

      {/* INFO TAB */}
      {activeTab === 'info' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          {/* Banner */}
          {offering.image_url ? (
            <Image source={{ uri: offering.image_url }} style={styles.banner} resizeMode="cover" />
          ) : (
            <View style={[styles.banner, { backgroundColor: `${accentColor}22` }]}>
              <Text style={styles.bannerEmoji}>{getSportIcon(offering.sport_key)}</Text>
            </View>
          )}

          {/* Hero card — big title with sport emoji + accent stripe */}
          <View style={styles.heroCard}>
            <View style={[styles.accentStripe, { backgroundColor: accentColor }]} />
            <View style={styles.heroBody}>
              <View style={styles.heroHeader}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.heroTitle}>{offering.title}</Text>
                  <View style={styles.chipRow}>
                    <Text style={[styles.sportChip, { color: accentColor, borderColor: accentColor }]}>
                      {getSportIcon(offering.sport_key)}  {offering.level}
                    </Text>
                    {offering.distance_km != null && (
                      <Text style={styles.metaChip}>
                        <TrendingUp size={11} color={colors.textSecondary} />  {offering.distance_km} km
                      </Text>
                    )}
                    {offering.elevation_gain_m != null && (
                      <Text style={styles.metaChip}>
                        <Mountain size={11} color={colors.textSecondary} />  {offering.elevation_gain_m} m
                      </Text>
                    )}
                  </View>
                </View>
                {isOwner && (
                  <Pressable
                    onPress={() => router.push({ pathname: '/(auth)/pro/offering/edit', params: { id: offering.id } })}
                    hitSlop={10}
                  >
                    <Pencil size={18} color={colors.textSecondary} strokeWidth={2.2} />
                  </Pressable>
                )}
              </View>

              <View style={styles.heroRow}>
                <MapPin size={14} color={colors.textSecondary} strokeWidth={2.4} />
                <Text style={styles.heroRowText} numberOfLines={2}>{offering.location_name}</Text>
              </View>
              {offering.schedule_text && (
                <View style={styles.heroRow}>
                  <Calendar size={14} color={colors.textSecondary} strokeWidth={2.4} />
                  <Text style={styles.heroRowText}>{offering.schedule_text}</Text>
                </View>
              )}
            </View>
          </View>

          {/* Identity card — taps through to pro page where contact lives */}
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

          {/* Secondary meta — only rows not already in the hero card */}
          {(formattedDuration || offering.max_participants) && (
            <View style={styles.card}>
              {formattedDuration && (
                <Row icon={<Clock size={16} color={colors.textSecondary} />}
                     label={t('proOffering.duration')}
                     value={formattedDuration}
                     styles={styles} />
              )}
              {offering.max_participants != null && (
                <Row icon={<Users size={16} color={colors.textSecondary} />}
                     label={t('proOffering.maxParticipants')}
                     value={`${offering.max_participants}`}
                     styles={styles} />
              )}
            </View>
          )}
        </ScrollView>
      )}

      {/* PICTURES TAB — Phase 4 wires the gallery */}
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

      {/* REVIEWS TAB — Phase 4 wires the review system */}
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

function Row({
  icon,
  label,
  value,
  styles,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <View style={styles.row}>
      <View style={styles.rowIcon}>{icon}</View>
      <View style={{ flex: 1 }}>
        <Text style={styles.rowLabel}>{label}</Text>
        <Text style={styles.rowValue}>{value}</Text>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { paddingBottom: spacing.xl + 32 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  notFound: { color: colors.textSecondary, fontSize: fontSizes.md },

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

  banner: { width: '100%', aspectRatio: 3, alignItems: 'center', justifyContent: 'center' },
  bannerEmoji: { fontSize: 72 },

  heroCard: {
    flexDirection: 'row',
    marginTop: spacing.md,
    marginHorizontal: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
    overflow: 'hidden',
  },
  accentStripe: { width: 4 },
  heroBody: { flex: 1, padding: spacing.md },
  heroHeader: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm, marginBottom: spacing.sm },
  heroTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontFamily: fonts.title,
    lineHeight: 30,
    marginBottom: spacing.xs,
  },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs, marginTop: 2 },
  sportChip: {
    fontSize: fontSizes.xs,
    fontWeight: '700',
    paddingVertical: 3,
    paddingHorizontal: spacing.xs + 2,
    borderRadius: radius.sm,
    borderWidth: 1.5,
    overflow: 'hidden',
  },
  metaChip: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    paddingVertical: 3,
    paddingHorizontal: spacing.xs + 2,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    overflow: 'hidden',
  },
  heroRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginTop: spacing.xs },
  heroRowText: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },

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
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.xs },
  rowIcon: { width: 28, alignItems: 'center' },
  rowLabel: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
  },
  rowValue: { color: colors.textPrimary, fontSize: fontSizes.md, marginTop: 1 },
});
