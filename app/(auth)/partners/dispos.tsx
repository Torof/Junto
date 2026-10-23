import { useCallback, useMemo, useRef, useState } from 'react';
import { View, Text, FlatList, ScrollView, StyleSheet, Modal, Pressable, RefreshControl, useWindowDimensions, type NativeScrollEvent, type NativeSyntheticEvent } from 'react-native';
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, SlidersHorizontal, X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DispoIntent } from '@/services/discovery-service';
import { useSports } from '@/hooks/use-sports';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { SportIcon } from '@/components/sport-icon';
import { DispoCardCompact } from '@/components/partners/dispo-card-compact';
import { MyDispoHero } from '@/components/partners/my-dispo-hero';
import { ContourLines } from '@/components/partners/contour-lines';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { INTENT_LABEL, VIBE_FILTER_GROUPS, UNIVERSES, type Universe } from '@/constants/discovery-vibes';
import { usePartnersPagerStore } from '@/store/partners-pager-store';

// Découverte page (refonte 2026-10-23, hybrid): your dispo in full, the
// matching dispos as a horizontal carousel (vibes filter), and « Qui est
// dispo, par sport » as a grid — a tile filters the carousel to its universe.
const CARD_W = 280;
const GAP = 12;
const DOTS_MAX = 10;
const UNIVERSE_GLYPH: Record<Universe, string> = {
  mountain: 'mountaineering', 'on-foot': 'hiking', water: 'kayaking',
  air: 'paragliding', cycling: 'cycling', wellness: 'yoga',
};

export default function PartnersDiscoveryScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const { width: screenW } = useWindowDimensions();
  const setPagerIds = usePartnersPagerStore((s) => s.setUserIds);
  const params = useLocalSearchParams<{ universe?: string }>();
  const scrollRef = useRef<ScrollView>(null);

  const [universe, setUniverse] = useState<Universe | null>(
    UNIVERSES.includes(params.universe as Universe) ? (params.universe as Universe) : null,
  );
  const [vibes, setVibes] = useState<Set<DispoIntent>>(new Set());
  const [vibesOpen, setVibesOpen] = useState(false);
  const [page, setPage] = useState(0);
  const toggleVibe = (v: DispoIntent) => setVibes((prev) => {
    const n = new Set(prev); if (n.has(v)) n.delete(v); else n.add(v); return n;
  });

  const { data: sports } = useSports();
  const categoryOf = useCallback((key: string) => (sports ?? []).find((s) => s.key === key)?.category, [sports]);

  const { data: mine } = useQuery({ queryKey: ['my-dispo'], queryFn: () => discoveryService.getMyDispo() });
  const active = mine?.is_active === true;
  const { data: cards, isLoading } = useQuery({
    queryKey: ['discovery-cards'],
    queryFn: () => discoveryService.getCards(),
    enabled: active,
  });
  useFocusEffect(useCallback(() => {
    void queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
  }, [queryClient]));

  const allCards = useMemo(() => cards ?? [], [cards]);
  const filtered = useMemo(() => allCards.filter((c) =>
    (!universe || c.sport_keys.some((k) => categoryOf(k) === universe))
    && (vibes.size === 0 || (c.intent ?? []).some((i) => vibes.has(i))),
  ), [allCards, universe, vibes, categoryOf]);
  const universeCounts = useMemo(() => {
    const m = new Map<Universe, number>();
    for (const c of allCards) {
      const seen = new Set(c.sport_keys.map(categoryOf).filter(Boolean));
      for (const u of UNIVERSES) if (seen.has(u)) m.set(u, (m.get(u) ?? 0) + 1);
    }
    return m;
  }, [allCards, categoryOf]);

  const filterOn = !!universe || vibes.size > 0;
  const clearAll = () => { setUniverse(null); setVibes(new Set()); };
  const pickUniverse = (u: Universe) => {
    setUniverse((prev) => (prev === u ? null : u));
    setPage(0);
    scrollRef.current?.scrollTo({ y: 0, animated: true });
  };
  const open = (userId: string) => {
    setPagerIds(filtered.map((c) => c.user_id));
    router.push({ pathname: '/(auth)/partners/dispo', params: { userId } });
  };
  const onCarouselScroll = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    setPage(Math.round(e.nativeEvent.contentOffset.x / (CARD_W + GAP)));
  };
  const tileW = (screenW - spacing.md * 2 - GAP) / 2;

  return (
    <View style={[styles.container, { paddingTop: insets.top + spacing.sm }]}>
      <View style={styles.topBar}>
        <PressableScale style={styles.back} onPress={() => router.back()} accessibilityRole="button" accessibilityLabel={t('common.back', { defaultValue: 'Retour' })}>
          <ChevronLeft size={20} color={colors.textPrimary} strokeWidth={2.6} />
        </PressableScale>
        <Text style={styles.title} numberOfLines={1}>{t('partenaires.discovery', { defaultValue: 'Découverte' })}</Text>
      </View>

      <ScrollView
        ref={scrollRef}
        contentContainerStyle={{ paddingBottom: insets.bottom + spacing.xl }}
        refreshControl={<RefreshControl refreshing={false} onRefresh={() => { void queryClient.refetchQueries({ queryKey: ['my-dispo'] }); void queryClient.refetchQueries({ queryKey: ['discovery-cards'] }); }} tintColor={colors.cta} />}
      >
        <MyDispoHero mine={mine ?? null} categoryOf={categoryOf} />

        {/* Dispos qui collent */}
        <View style={styles.sectionHead}>
          <Text style={styles.sectionTitle} numberOfLines={1}>
            {t('partenaires.dispos', { defaultValue: 'Dispos qui collent' })}
            {active ? <Text style={styles.sectionCount}>{`  ${filtered.length}`}</Text> : null}
          </Text>
          {active ? (
            <PressableScale style={[styles.vibesBtn, vibes.size > 0 && styles.vibesBtnOn]} onPress={() => setVibesOpen(true)} accessibilityRole="button">
              <SlidersHorizontal size={13} color={vibes.size > 0 ? '#FFFFFF' : colors.textPrimary} strokeWidth={2.4} />
              <Text style={[styles.vibesBtnText, vibes.size > 0 && styles.vibesBtnTextOn]}>
                {t('partenaires.vibes', { defaultValue: 'Vibes' })}{vibes.size > 0 ? ` · ${vibes.size}` : ''}
              </Text>
            </PressableScale>
          ) : null}
        </View>
        {universe ? (
          <View style={styles.activeRow}>
            <PressableScale style={[styles.activeChip, { backgroundColor: sportCategoryColor(universe, colors.cta) }]} onPress={() => setUniverse(null)}>
              <Text style={styles.activeChipText}>{t(`partenaires.universe.${universe}`)}</Text>
              <X size={13} color="#FFFFFF" strokeWidth={2.8} />
            </PressableScale>
          </View>
        ) : null}

        {!active ? (
          <Text style={styles.note}>{t('partenaires.disposLocked', { defaultValue: 'Pose ta dispo pour voir qui cherche la même chose que toi.' })}</Text>
        ) : isLoading ? (
          <View style={styles.center}><LogoSpinner size={36} /></View>
        ) : filtered.length === 0 ? (
          <View style={styles.emptyBox}>
            <Text style={styles.note}>
              {filterOn
                ? t('discovery.filterEmptyTitle', { defaultValue: 'Aucun avec ces filtres' })
                : t('partenaires.disposEmpty', { defaultValue: 'Personne pour l’instant. Élargis ta zone ou tes dates pour croiser plus de monde.' })}
            </Text>
            {filterOn ? (
              <PressableScale onPress={clearAll} hitSlop={8}>
                <Text style={styles.clear}>{t('discovery.filterClear', { defaultValue: 'Effacer' })}</Text>
              </PressableScale>
            ) : null}
          </View>
        ) : (
          <>
            <FlatList
              horizontal
              data={filtered}
              keyExtractor={(c) => c.user_id}
              renderItem={({ item }) => <DispoCardCompact card={item} categoryOf={categoryOf} width={CARD_W} showVibes onPress={() => open(item.user_id)} />}
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.carousel}
              ItemSeparatorComponent={() => <View style={{ width: GAP }} />}
              snapToInterval={CARD_W + GAP}
              decelerationRate="fast"
              onMomentumScrollEnd={onCarouselScroll}
            />
            {filtered.length > 1 && filtered.length <= DOTS_MAX ? (
              <View style={styles.dots}>
                {filtered.map((c, i) => <View key={c.user_id} style={[styles.dot, i === page && styles.dotOn]} />)}
              </View>
            ) : null}
          </>
        )}

        {/* Qui est dispo, par sport — a tile filters the carousel above */}
        <Text style={[styles.sectionTitle, styles.gridTitle]}>{t('partenaires.byUniverse', { defaultValue: 'Qui est dispo, par sport' })}</Text>
        <View style={styles.grid}>
          {UNIVERSES.map((u) => {
            const n = universeCounts.get(u) ?? 0;
            const on = universe === u;
            return (
              <PressableScale
                key={u}
                style={[styles.tile, { width: tileW, backgroundColor: sportCategoryColor(u, colors.cta) }, on && styles.tileOn]}
                onPress={() => (active ? pickUniverse(u) : router.push('/(auth)/discovery-compose'))}
                accessibilityRole="button"
                accessibilityState={{ selected: on }}
              >
                <ContourLines width={tileW} height={96} opacity={0.2} />
                <View style={styles.tileGlyph}><SportIcon sportKey={UNIVERSE_GLYPH[u]} size={30} color="#FFFFFF" /></View>
                <Text style={styles.tileName}>{t(`partenaires.universe.${u}`)}</Text>
                <Text style={styles.tileCount} numberOfLines={1}>
                  {n > 0 ? t('partenaires.universeDispos', { count: n, defaultValue: '{{count}} dispos' }) : t('partenaires.universeNone', { defaultValue: 'Rien pour l’instant' })}
                </Text>
              </PressableScale>
            );
          })}
        </View>
      </ScrollView>

      {/* Vibes sheet */}
      <Modal visible={vibesOpen} transparent animationType="slide" onRequestClose={() => setVibesOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setVibesOpen(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.grab} />
            <View style={styles.sheetHead}>
              <Text style={styles.sheetTitle}>{t('partenaires.vibes', { defaultValue: 'Vibes' })}</Text>
              <Pressable onPress={() => setVibesOpen(false)} hitSlop={8}><X size={20} color={colors.textSecondary} strokeWidth={2.4} /></Pressable>
            </View>
            <ScrollView showsVerticalScrollIndicator={false}>
              {VIBE_FILTER_GROUPS.map((g) => (
                <View key={g.key} style={styles.group}>
                  <Text style={styles.groupLabel}>{t(`discovery.vibeGroup.${g.key}`, { defaultValue: g.key })}</Text>
                  <View style={styles.groupChips}>
                    {g.items.map((it) => {
                      const on = vibes.has(it);
                      return (
                        <PressableScale key={it} style={[styles.vibe, on && styles.vibeOn]} onPress={() => toggleVibe(it)}>
                          <Text style={[styles.vibeText, on && styles.vibeTextOn]}>{t(`discovery.intent.${it}`, { defaultValue: INTENT_LABEL[it] })}</Text>
                        </PressableScale>
                      );
                    })}
                  </View>
                </View>
              ))}
            </ScrollView>
            <View style={styles.sheetFoot}>
              <PressableScale style={styles.sheetClear} onPress={() => setVibes(new Set())}>
                <Text style={styles.sheetClearText}>{t('discovery.filterClear', { defaultValue: 'Effacer' })}</Text>
              </PressableScale>
              <PressableScale style={styles.sheetApply} onPress={() => { setVibesOpen(false); setPage(0); }}>
                <Text style={styles.sheetApplyText}>{t('discovery.filterResults', { defaultValue: 'Voir les {{count}} résultats', count: filtered.length })}</Text>
              </PressableScale>
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  topBar: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, paddingHorizontal: spacing.md },
  back: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.surfaceAlt, alignItems: 'center', justifyContent: 'center' },
  title: { flex: 1, color: colors.textPrimary, fontFamily: fonts.title, fontSize: 24 },
  sectionHead: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm,
    paddingHorizontal: spacing.md, marginTop: spacing.lg + 2, marginBottom: spacing.sm + 2,
  },
  sectionTitle: { flexShrink: 1, color: colors.textPrimary, fontFamily: fonts.title, fontSize: 20 },
  sectionCount: { color: colors.cta },
  vibesBtn: { flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 7 },
  vibesBtnOn: { backgroundColor: colors.textPrimary },
  vibesBtnText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  vibesBtnTextOn: { color: colors.background },
  activeRow: { flexDirection: 'row', paddingHorizontal: spacing.md, marginBottom: spacing.sm },
  activeChip: { flexDirection: 'row', alignItems: 'center', gap: 5, borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 6 },
  activeChipText: { color: '#FFFFFF', fontSize: fontSizes.sm - 1, fontWeight: '700' },
  note: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, paddingHorizontal: spacing.md },
  emptyBox: { gap: spacing.sm, alignItems: 'flex-start' },
  clear: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', marginLeft: spacing.md },
  center: { paddingVertical: spacing.xl, alignItems: 'center' },
  carousel: { paddingHorizontal: spacing.md, paddingVertical: 6 },
  dots: { flexDirection: 'row', justifyContent: 'center', gap: 5, marginTop: spacing.sm },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.lineStrong },
  dotOn: { width: 16, backgroundColor: colors.textPrimary },
  gridTitle: { paddingHorizontal: spacing.md, marginTop: spacing.lg + 6, marginBottom: spacing.sm + 4 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: GAP, paddingHorizontal: spacing.md },
  tile: { height: 96, borderRadius: 18, overflow: 'hidden', padding: spacing.sm + 6, justifyContent: 'flex-end' },
  tileOn: { borderWidth: 3, borderColor: colors.textPrimary },
  tileGlyph: { position: 'absolute', right: 14, top: 12, opacity: 0.95 },
  tileName: { color: '#FFFFFF', fontFamily: fonts.title, fontSize: 17 },
  tileCount: { color: 'rgba(255,255,255,0.88)', fontSize: fontSizes.xs, fontWeight: '600', marginTop: 2 },
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    maxHeight: '82%', backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    padding: spacing.lg, paddingBottom: spacing.xl, gap: spacing.sm,
  },
  grab: { width: 38, height: 5, borderRadius: 3, backgroundColor: colors.borderMuted, alignSelf: 'center' },
  sheetHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  group: { marginTop: spacing.sm + 2, gap: spacing.sm },
  groupLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.6 },
  groupChips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  vibe: { backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm },
  vibeOn: { backgroundColor: colors.cta },
  vibeText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  vibeTextOn: { color: '#FFFFFF', fontWeight: '700' },
  sheetFoot: { flexDirection: 'row', gap: spacing.sm, paddingTop: spacing.sm, borderTopWidth: 1, borderTopColor: colors.line },
  sheetClear: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingVertical: spacing.sm + 4 },
  sheetClearText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800' },
  sheetApply: { flex: 2, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 4 },
  sheetApplyText: { color: colors.onCta, fontSize: fontSizes.sm + 1, fontWeight: '700' },
});
