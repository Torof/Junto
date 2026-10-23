import { useCallback, useMemo } from 'react';
import { View, Text, ScrollView, FlatList, StyleSheet, RefreshControl } from 'react-native';
import { useRouter, useFocusEffect } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { MapPin, ChevronRight, Plus } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DiscoveryCard } from '@/services/discovery-service';
import { channelService, type ChannelListItem } from '@/services/channel-service';
import { useSports } from '@/hooks/use-sports';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { PressableScale } from '@/components/pressable-scale';
import { DispoCardCompact, formatPeriod } from '@/components/partners/dispo-card-compact';
import { ChannelTile } from '@/components/partners/channel-tile';
import { radiusLabel } from '@/components/partners/my-dispo-hero';
import { usePartnersPagerStore } from '@/store/partners-pager-store';

// Partenaires home (refonte 2026-10-23, canvas « Partenaires — refonte »,
// hybrid option 2): everything essential on the first screen — your dispo as
// one line (it opens the Découverte page), the matching dispos, then the
// discussions. Each family has its own full page behind « Tout voir ».
const CARD_W = 252;
const TILE_W = 160;
const GAP = 12;
const CAROUSEL_LIMIT = 10;

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
  // dispo's base (else around me), then the most followed elsewhere — one
  // joins channels for the places one travels to, not only home.
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

  const openDiscovery = () => router.push(mine ? '/(auth)/partners/dispos' : '/(auth)/discovery-compose');
  const openCard = (list: DiscoveryCard[], userId: string) => {
    setPagerIds(list.map((c) => c.user_id));
    router.push({ pathname: '/(auth)/partners/dispo', params: { userId } });
  };

  const zoneLabel = mine
    ? `${mine.base_label} · ${radiusLabel(mine.radius_km, t('discovery.radiusAny', { defaultValue: 'Peu importe' }))}`
    : t('partenaires.zoneMe', { defaultValue: 'Autour de toi' });
  const sportNames = (mine?.sport_keys ?? []).map((k) => t(`sports.${k}`, { defaultValue: k })).join(', ');

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={{ paddingTop: insets.top + spacing.md, paddingBottom: spacing.xl }}
      refreshControl={<RefreshControl refreshing={false} onRefresh={refresh} tintColor={colors.cta} />}
    >
      {/* Title + zone on one line */}
      <View style={styles.header}>
        <Text style={styles.title} numberOfLines={1}>{t('partenaires.title', { defaultValue: 'Partenaires' })}</Text>
        <PressableScale style={styles.zonePill} onPress={() => router.push('/(auth)/discovery-compose')} accessibilityRole="button">
          <MapPin size={14} color={colors.cta} strokeWidth={2.4} />
          <Text style={styles.zonePillText} numberOfLines={1}>{zoneLabel}</Text>
        </PressableScale>
      </View>

      {/* Ta dispo, one line — the full card lives on the Découverte page */}
      <PressableScale style={[styles.dispoLine, !mine && styles.dispoLineEmpty]} onPress={openDiscovery} accessibilityRole="button">
        <View style={[styles.dot, { backgroundColor: active ? colors.cta : mine ? colors.textMuted : colors.cta }]} />
        <View style={styles.dispoLineText}>
          <Text style={[styles.dispoLineTitle, !mine && styles.dispoLineTitleEmpty]} numberOfLines={1}>
            {!mine
              ? t('partenaires.noDispoTitle', { defaultValue: 'Pose ta dispo' })
              : active
                ? t('partenaires.lineLive', { defaultValue: 'Ta dispo · en ligne' })
                : t('partenaires.linePaused', { defaultValue: 'Ta dispo · en pause' })}
          </Text>
          <Text style={[styles.dispoLineSub, !mine && styles.dispoLineSubEmpty]} numberOfLines={1}>
            {mine
              ? `${formatPeriod(mine.window_start, mine.window_end)} · ${sportNames}`
              : t('partenaires.lineEmptySub', { defaultValue: 'Un sport, une zone, des dates — et vois qui cherche la même chose.' })}
          </Text>
        </View>
        <ChevronRight size={18} color={mine ? '#FFFFFF' : colors.cta} strokeWidth={2.6} />
      </PressableScale>

      {/* Dispos qui collent */}
      <SectionHead
        styles={styles}
        accent={colors.cta}
        title={t('partenaires.dispos', { defaultValue: 'Dispos qui collent' })}
        count={active && allCards.length > 0 ? allCards.length : undefined}
        onSeeAll={mine ? openDiscovery : undefined}
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

      {/* Discussions — yours, near you, elsewhere */}
      <SectionHead
        styles={styles}
        accent={colors.cta}
        title={t('partenaires.discussions', { defaultValue: 'Discussions' })}
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

function SectionHead({ styles, accent, title, count, onSeeAll, seeAllLabel }: {
  styles: ReturnType<typeof createStyles>;
  accent: string;
  title: string;
  count?: number;
  onSeeAll?: () => void;
  seeAllLabel?: string;
}) {
  return (
    <View style={styles.sectionHead}>
      <Text style={styles.sectionTitle}>
        {title}{count !== undefined ? <Text style={styles.sectionCount}>{`  ${count}`}</Text> : null}
      </Text>
      {onSeeAll ? (
        <PressableScale style={styles.seeAll} onPress={onSeeAll} hitSlop={8} accessibilityRole="button">
          <Text style={styles.seeAllText}>{seeAllLabel}</Text>
          <ChevronRight size={15} color={accent} strokeWidth={2.6} />
        </PressableScale>
      ) : null}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm, paddingHorizontal: spacing.md },
  title: { flexShrink: 0, color: colors.textPrimary, fontFamily: fonts.title, fontSize: 28, letterSpacing: -0.4 },
  zonePill: {
    flexDirection: 'row', alignItems: 'center', gap: 5, flexShrink: 1,
    backgroundColor: colors.cta + '1A', borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 7,
  },
  zonePillText: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700', flexShrink: 1 },

  dispoLine: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, marginHorizontal: spacing.md, marginTop: spacing.md - 2,
    paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm + 4, borderRadius: 16, backgroundColor: colors.heroInk,
  },
  dispoLineEmpty: { backgroundColor: colors.cta + '1A' },
  dot: { width: 10, height: 10, borderRadius: 5 },
  dispoLineText: { flex: 1, minWidth: 0, gap: 2 },
  dispoLineTitle: { color: '#FFFFFF', fontSize: fontSizes.md - 1, fontWeight: '700' },
  dispoLineTitleEmpty: { color: colors.textPrimary },
  dispoLineSub: { color: 'rgba(255,255,255,0.72)', fontSize: fontSizes.xs },
  dispoLineSubEmpty: { color: colors.textSecondary },

  sectionHead: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, marginTop: spacing.lg - 2, marginBottom: spacing.sm + 2,
  },
  sectionTitle: { flexShrink: 1, color: colors.textPrimary, fontFamily: fonts.title, fontSize: 20 },
  sectionCount: { color: colors.cta },
  seeAll: { flexDirection: 'row', alignItems: 'center', gap: 2 },
  seeAllText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  note: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, paddingHorizontal: spacing.md },
  carousel: { paddingHorizontal: spacing.md, paddingVertical: 6 },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', marginLeft: spacing.md, marginTop: spacing.sm, paddingVertical: spacing.xs },
  linkRowText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
});
