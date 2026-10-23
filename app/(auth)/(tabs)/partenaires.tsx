import { useCallback, useMemo } from 'react';
import { View, Text, ScrollView, FlatList, StyleSheet, RefreshControl, useWindowDimensions } from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { MapPin, ChevronDown, ChevronRight, Plus, Pause } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DiscoveryCard, type MyDispo } from '@/services/discovery-service';
import { channelService, type ChannelListItem } from '@/services/channel-service';
import { useSports } from '@/hooks/use-sports';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { ContourLines } from '@/components/partners/contour-lines';
import { DispoCardCompact, formatPeriod } from '@/components/partners/dispo-card-compact';
import { ChannelTile } from '@/components/partners/channel-tile';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getFriendlyError } from '@/utils/friendly-error';
import { UNIVERSES, type Universe } from '@/constants/discovery-vibes';
import { usePartnersPagerStore } from '@/store/partners-pager-store';

// Partenaires home (refonte 2026-10-23, canvas « Partenaires — refonte »,
// direction A): one page in sections instead of the Découverte / Discussions
// switch — your zone and dispo, a carousel of matching dispos, a carousel of
// discussions nearby, and the six universes. « Tout voir » opens each full list.
const CARD_W = 252;
const TILE_W = 168;
const GAP = 12;
const CAROUSEL_LIMIT = 10;
const UNIVERSE_W = 132;
const UNIVERSE_H = 84;
const UNIVERSE_GLYPH: Record<Universe, string> = {
  mountain: 'mountaineering', 'on-foot': 'hiking', water: 'kayaking',
  air: 'paragliding', cycling: 'cycling', wellness: 'yoga',
};

export default function PartenairesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const setPagerIds = usePartnersPagerStore((s) => s.setUserIds);

  const { data: sports } = useSports();
  const categoryOf = useCallback(
    (key: string) => (sports ?? []).find((s) => s.key === key)?.category,
    [sports],
  );

  const { data: mine } = useQuery({ queryKey: ['my-dispo'], queryFn: () => discoveryService.getMyDispo() });
  const active = mine?.is_active === true;
  const { data: cards } = useQuery({
    queryKey: ['discovery-cards'],
    queryFn: () => discoveryService.getCards(),
    enabled: active,
  });

  // Discussions: yours first (wherever they are), then those around the
  // dispo's base (else around me), then the most active elsewhere — one goes
  // to channels for the places one travels to, not only home (Scott 2026-10-23).
  const { currentLocation } = useInitialLocation();
  const center = useMemo(
    () => (mine ? { lng: mine.base_lng, lat: mine.base_lat } : currentLocation ? { lng: currentLocation[0], lat: currentLocation[1] } : null),
    [mine, currentLocation],
  );
  const { data: nearChannels } = useQuery({
    queryKey: ['channels', '', null, center?.lng, center?.lat],
    queryFn: () => channelService.search({ query: null, sportKey: null, nearLng: center?.lng ?? null, nearLat: center?.lat ?? null }),
    enabled: !!center,
  });
  const { data: allChannels } = useQuery({
    queryKey: ['channels', '', null, undefined, undefined],
    queryFn: () => channelService.search({ query: null, sportKey: null, nearLng: null, nearLat: null }),
  });

  // The list refreshes on focus (« Envoyée » must become « Discuter », audit M1).
  useFocusEffect(useCallback(() => {
    void queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
  }, [queryClient]));

  const refresh = () => {
    void queryClient.refetchQueries({ queryKey: ['my-dispo'] });
    void queryClient.refetchQueries({ queryKey: ['discovery-cards'] });
    void queryClient.refetchQueries({ queryKey: ['channels'] });
  };

  const radiusText = (km: number | null) => (km ? `${km} km` : t('discovery.radiusAny', { defaultValue: 'Peu importe' }));
  const zoneLabel = mine
    ? t('partenaires.zoneAround', { defaultValue: 'Autour de {{place}} · {{radius}}', place: mine.base_label, radius: radiusText(mine.radius_km) })
    : t('partenaires.zoneMe', { defaultValue: 'Autour de toi' });

  const setActive = async (on: boolean) => {
    try {
      if (on) await discoveryService.activate(); else await discoveryService.deactivate();
      await queryClient.invalidateQueries({ queryKey: ['my-dispo'] });
      await queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  const allCards = useMemo(() => cards ?? [], [cards]);
  const carouselCards = allCards.slice(0, CAROUSEL_LIMIT);
  const discussionItems = useMemo(() => {
    const seen = new Set<string>();
    const out: { item: ChannelListItem; badge: 'member' | 'near' | 'elsewhere' }[] = [];
    const push = (c: ChannelListItem, badge: 'member' | 'near' | 'elsewhere') => {
      if (seen.has(c.conversation_id)) return;
      seen.add(c.conversation_id);
      out.push({ item: c, badge });
    };
    const near = center ? nearChannels ?? [] : [];
    [...near, ...(allChannels ?? [])].filter((c) => c.is_member).forEach((c) => push(c, 'member'));
    near.forEach((c) => push(c, 'near'));
    (allChannels ?? []).forEach((c) => push(c, 'elsewhere'));
    return out.slice(0, CAROUSEL_LIMIT);
  }, [center, nearChannels, allChannels]);

  const openCard = (list: DiscoveryCard[], userId: string) => {
    setPagerIds(list.map((c) => c.user_id));
    router.push({ pathname: '/(auth)/partners/dispo', params: { userId } });
  };

  // « Qui est dispo, par sport »: matching dispos with at least one sport of the universe.
  const universeCounts = useMemo(() => {
    const m = new Map<Universe, number>();
    for (const u of UNIVERSES) m.set(u, 0);
    for (const c of allCards) {
      const seen = new Set(c.sport_keys.map(categoryOf).filter(Boolean));
      for (const u of UNIVERSES) if (seen.has(u)) m.set(u, (m.get(u) ?? 0) + 1);
    }
    return m;
  }, [allCards, categoryOf]);

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={{ paddingTop: insets.top + spacing.md, paddingBottom: spacing.xl }}
      refreshControl={<RefreshControl refreshing={false} onRefresh={refresh} tintColor={colors.cta} />}
    >
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>{t('partenaires.title', { defaultValue: 'Partenaires' })}</Text>
        <PressableScale style={styles.zonePill} onPress={() => router.push('/(auth)/discovery-compose')} accessibilityRole="button">
          <MapPin size={15} color={colors.cta} strokeWidth={2.4} />
          <Text style={styles.zonePillText} numberOfLines={1}>{zoneLabel}</Text>
          <ChevronDown size={14} color={colors.cta} strokeWidth={2.6} />
        </PressableScale>
      </View>

      {/* Ta dispo */}
      <MyDispoHero mine={mine ?? null} styles={styles} colors={colors} categoryOf={categoryOf} radiusText={radiusText}
        onEdit={() => router.push('/(auth)/discovery-compose')} onToggle={setActive} />

      {/* Dispos qui collent */}
      <SectionHead
        styles={styles}
        accent={colors.cta}
        title={t('partenaires.dispos', { defaultValue: 'Dispos qui collent' })}
        count={active && allCards.length > 0 ? allCards.length : undefined}
        onSeeAll={active && allCards.length > 0 ? () => router.push('/(auth)/partners/dispos') : undefined}
        seeAllLabel={t('partenaires.seeAll', { defaultValue: 'Tout voir' })}
      />
      {!active ? (
        <Text style={styles.note}>{t('partenaires.disposLocked', { defaultValue: 'Pose ta dispo pour voir qui cherche la même chose que toi.' })}</Text>
      ) : carouselCards.length === 0 ? (
        <Text style={styles.note}>{t('partenaires.disposEmpty', { defaultValue: 'Personne pour l’instant. Élargis ta zone ou tes dates pour croiser plus de monde.' })}</Text>
      ) : (
        <FlatList
          horizontal
          data={carouselCards}
          keyExtractor={(c) => c.user_id}
          renderItem={({ item }) => (
            <DispoCardCompact card={item} categoryOf={categoryOf} width={CARD_W} onPress={() => openCard(allCards, item.user_id)} />
          )}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.carousel}
          ItemSeparatorComponent={() => <View style={{ width: GAP }} />}
          snapToInterval={CARD_W + GAP}
          decelerationRate="fast"
        />
      )}

      {/* Qui est dispo, par sport — right under the dispos it extends, one scrolling row. */}
      <SectionHead
        styles={styles}
        accent={colors.cta}
        title={t('partenaires.byUniverse', { defaultValue: 'Qui est dispo, par sport' })}
        subtitle={t('partenaires.byUniverseSub', { defaultValue: 'Les personnes dispos, sport par sport.' })}
      />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.carousel}>
        {UNIVERSES.map((u, i) => {
          const n = universeCounts.get(u) ?? 0;
          const target = active
            ? { pathname: '/(auth)/partners/dispos' as const, params: { universe: u } }
            : { pathname: '/(auth)/discovery-compose' as const };
          return (
            <PressableScale
              key={u}
              style={[styles.universe, i > 0 && { marginLeft: 10 }, { backgroundColor: sportCategoryColor(u, colors.cta) }]}
              onPress={() => router.push(target)}
              accessibilityRole="button"
            >
              <ContourLines width={UNIVERSE_W} height={UNIVERSE_H} opacity={0.2} />
              <View style={styles.universeGlyph}><SportIcon sportKey={UNIVERSE_GLYPH[u]} size={26} color="#FFFFFF" /></View>
              <Text style={styles.universeName}>{t(`partenaires.universe.${u}`)}</Text>
              <Text style={styles.universeCount} numberOfLines={1}>
                {n > 0 ? t('partenaires.universeDispos', { count: n, defaultValue: '{{count}} dispos' }) : t('partenaires.universeNone', { defaultValue: 'Rien pour l’instant' })}
              </Text>
            </PressableScale>
          );
        })}
      </ScrollView>

      {/* Discussions — yours, near you, elsewhere. */}
      <SectionHead
        styles={styles}
        accent={colors.cta}
        title={t('partenaires.discussions', { defaultValue: 'Discussions' })}
        subtitle={t('partenaires.discussionsSub', { defaultValue: 'Les tiennes, près de chez toi, et ailleurs.' })}
        onSeeAll={() => router.push('/(auth)/partners/discussions')}
        seeAllLabel={t('partenaires.seeAll', { defaultValue: 'Tout voir' })}
      />
      {discussionItems.length === 0 ? (
        <Text style={styles.note}>{t('partenaires.discussionsEmpty', { defaultValue: 'Aucune discussion pour l’instant. Ouvre la première !' })}</Text>
      ) : (
        <FlatList
          horizontal
          data={discussionItems}
          keyExtractor={(d) => d.item.conversation_id}
          renderItem={({ item: d }) => (
            <ChannelTile
              item={d.item}
              categoryOf={categoryOf}
              width={TILE_W}
              badge={d.badge === 'member'
                ? t('channels.member', { defaultValue: 'Membre' })
                : d.badge === 'near'
                  ? t('partenaires.badgeNear', { defaultValue: 'Près de toi' })
                  : t('partenaires.badgeElsewhere', { defaultValue: 'Ailleurs' })}
              onPress={() => router.push(`/(auth)/conversation/${d.item.conversation_id}`)}
            />
          )}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.carousel}
          ItemSeparatorComponent={() => <View style={{ width: GAP }} />}
          snapToInterval={TILE_W + GAP}
          decelerationRate="fast"
        />
      )}
      <PressableScale style={styles.linkRow} onPress={() => router.push('/(auth)/create-channel')} accessibilityRole="button">
        <Plus size={16} color={colors.textSecondary} strokeWidth={2.6} />
        <Text style={styles.linkRowText}>{t('partenaires.openDiscussion', { defaultValue: 'Ouvrir une discussion' })}</Text>
      </PressableScale>
    </ScrollView>
  );
}

function SectionHead({ styles, accent, title, subtitle, count, onSeeAll, seeAllLabel }: {
  styles: ReturnType<typeof createStyles>;
  accent: string;
  title: string;
  subtitle?: string;
  count?: number;
  onSeeAll?: () => void;
  seeAllLabel?: string;
}) {
  return (
    <View style={styles.sectionHead}>
      <View style={styles.sectionHeadText}>
        <Text style={styles.sectionTitle}>
          {title}{count !== undefined ? <Text style={styles.sectionCount}>{`  ${count}`}</Text> : null}
        </Text>
        {subtitle ? <Text style={styles.sectionSub}>{subtitle}</Text> : null}
      </View>
      {onSeeAll ? (
        <PressableScale style={styles.seeAll} onPress={onSeeAll} hitSlop={8} accessibilityRole="button">
          <Text style={styles.seeAllText}>{seeAllLabel}</Text>
          <ChevronRight size={15} color={accent} strokeWidth={2.6} />
        </PressableScale>
      ) : null}
    </View>
  );
}

// « Ta dispo » — three states: live, paused, none yet.
function MyDispoHero({ mine, styles, colors, categoryOf, radiusText, onEdit, onToggle }: {
  mine: MyDispo | null;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
  categoryOf: (k: string) => string | undefined;
  radiusText: (km: number | null) => string;
  onEdit: () => void;
  onToggle: (on: boolean) => void;
}) {
  const { t } = useTranslation();
  const { width: screenW } = useWindowDimensions();
  const heroW = screenW - spacing.md * 2;

  if (!mine) {
    return (
      <View style={styles.heroEmpty}>
        <Text style={styles.heroEmptyTitle}>{t('partenaires.noDispoTitle', { defaultValue: 'Pose ta dispo' })}</Text>
        <Text style={styles.heroEmptyBody}>{t('discovery.onbBody', { defaultValue: 'Publie ta dispo — un sport, une zone, des dates — et vois qui cherche la même chose.' })}</Text>
        <PressableScale style={styles.heroCta} onPress={onEdit} accessibilityRole="button">
          <Text style={styles.heroCtaText}>{t('discovery.composeDispo', { defaultValue: 'Composer ma dispo' })}</Text>
        </PressableScale>
      </View>
    );
  }

  const live = mine.is_active;
  return (
    <View style={[styles.hero, !live && styles.heroPaused]}>
      <ContourLines width={heroW} height={170} opacity={0.08} />
      <View style={styles.heroTop}>
        <Text style={styles.heroTitle}>
          {live ? t('discovery.myDispoTitle', { defaultValue: 'Ta dispo' }) : t('partenaires.pausedTitle', { defaultValue: 'Ta dispo est en pause' })}
        </Text>
        {live ? (
          <View style={styles.livePill}><Text style={styles.livePillText}>{t('discovery.live', { defaultValue: 'En ligne' })}</Text></View>
        ) : null}
      </View>
      <Text style={styles.heroSub} numberOfLines={1}>
        {formatPeriod(mine.window_start, mine.window_end)} · {mine.base_label} · {radiusText(mine.radius_km)}
      </Text>
      <View style={styles.heroBottom}>
        <View style={styles.heroSports}>
          {mine.sport_keys.map((k) => (
            <View key={k} style={[styles.heroSport, { backgroundColor: sportCategoryColor(categoryOf(k), colors.cta) }]}>
              <SportIcon sportKey={k} size={13} color="#FFFFFF" />
              <Text style={styles.heroSportText} numberOfLines={1}>{t(`sports.${k}`, { defaultValue: k })}</Text>
            </View>
          ))}
        </View>
      </View>
      <View style={styles.heroActions}>
        {live ? (
          <PressableScale style={[styles.heroBtn, styles.heroPause]} onPress={() => onToggle(false)} accessibilityRole="button">
            <Pause size={14} color="#FFFFFF" fill="#FFFFFF" strokeWidth={2} />
            <Text style={styles.heroPauseText}>{t('partenaires.pause', { defaultValue: 'Mettre en pause' })}</Text>
          </PressableScale>
        ) : (
          <PressableScale style={[styles.heroBtn, styles.heroResume]} onPress={() => onToggle(true)} accessibilityRole="button">
            <Text style={styles.heroResumeText}>{t('partenaires.resume', { defaultValue: 'Remettre en ligne' })}</Text>
          </PressableScale>
        )}
        <PressableScale style={[styles.heroBtn, styles.heroEdit]} onPress={onEdit} accessibilityRole="button">
          <Text style={styles.heroEditText}>{t('discovery.edit', { defaultValue: 'Modifier' })}</Text>
        </PressableScale>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  header: { paddingHorizontal: spacing.md, gap: spacing.sm + 2 },
  title: { color: colors.textPrimary, fontFamily: fonts.title, fontSize: 30, letterSpacing: -0.4 },
  zonePill: {
    alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', gap: 6, maxWidth: '100%',
    backgroundColor: colors.cta + '1A', borderRadius: radius.full, paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm,
  },
  zonePillText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', flexShrink: 1 },

  hero: {
    marginHorizontal: spacing.md, marginTop: spacing.md + 2, padding: spacing.md, borderRadius: 18,
    backgroundColor: colors.heroInk, overflow: 'hidden', gap: spacing.sm,
  },
  heroPaused: { opacity: 0.88 },
  heroTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  heroTitle: { color: '#FFFFFF', fontFamily: fonts.title, fontSize: fontSizes.lg },
  livePill: { backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: 9, paddingVertical: 3 },
  livePillText: { color: '#FFFFFF', fontSize: 11, fontWeight: '800', letterSpacing: 0.4, textTransform: 'uppercase' },
  heroSub: { color: 'rgba(255,255,255,0.8)', fontSize: fontSizes.sm },
  heroBottom: { flexDirection: 'row', alignItems: 'center' },
  heroSports: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, flex: 1 },
  heroSport: { flexDirection: 'row', alignItems: 'center', gap: 4, borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 6 },
  heroSportText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '600' },
  heroActions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
  heroBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, borderRadius: radius.full, paddingVertical: spacing.sm + 2 },
  heroPause: { backgroundColor: 'rgba(255,255,255,0.15)' },
  heroPauseText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '700' },
  heroResume: { backgroundColor: colors.cta },
  heroResumeText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '700' },
  heroEdit: { backgroundColor: '#FFFFFF' },
  heroEditText: { color: '#1F1A15', fontSize: fontSizes.sm, fontWeight: '700' },
  heroEmpty: {
    marginHorizontal: spacing.md, marginTop: spacing.md + 2, padding: spacing.md + 2, borderRadius: 18,
    backgroundColor: colors.cta + '1A', gap: spacing.sm,
  },
  heroEmptyTitle: { color: colors.textPrimary, fontFamily: fonts.title, fontSize: fontSizes.lg },
  heroEmptyBody: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  heroCta: { alignSelf: 'flex-start', backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.md + 2, paddingVertical: spacing.sm + 2, marginTop: spacing.xs },
  heroCtaText: { color: '#FFFFFF', fontSize: fontSizes.sm + 1, fontWeight: '700' },

  sectionHead: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, marginTop: spacing.lg + 4, marginBottom: spacing.sm + 4,
  },
  sectionHeadText: { flexShrink: 1, gap: 3 },
  sectionTitle: { color: colors.textPrimary, fontFamily: fonts.title, fontSize: 20 },
  sectionSub: { color: colors.textSecondary, fontSize: fontSizes.sm - 1 },
  sectionCount: { color: colors.cta },
  seeAll: { flexDirection: 'row', alignItems: 'center', gap: 2 },
  seeAllText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  note: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, paddingHorizontal: spacing.md },
  carousel: { paddingHorizontal: spacing.md, paddingVertical: 6 },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', marginLeft: spacing.md, marginTop: spacing.sm, paddingVertical: spacing.xs },
  linkRowText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },

  universe: { width: UNIVERSE_W, height: UNIVERSE_H, borderRadius: 16, overflow: 'hidden', padding: spacing.sm + 4, justifyContent: 'flex-end' },
  universeGlyph: { position: 'absolute', right: 10, top: 10, opacity: 0.95 },
  universeName: { color: '#FFFFFF', fontFamily: fonts.title, fontSize: 15 },
  universeCount: { color: 'rgba(255,255,255,0.88)', fontSize: fontSizes.xs, fontWeight: '600', marginTop: 1 },
});
