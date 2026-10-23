import { useCallback, useMemo, useState } from 'react';
import { View, Text, FlatList, ScrollView, StyleSheet, Modal, Pressable, RefreshControl } from 'react-native';
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, SlidersHorizontal, X, Telescope } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DispoIntent } from '@/services/discovery-service';
import { useSports } from '@/hooks/use-sports';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { DispoCardCompact } from '@/components/partners/dispo-card-compact';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { INTENT_LABEL, VIBE_FILTER_GROUPS, UNIVERSES, type Universe } from '@/constants/discovery-vibes';
import { usePartnersPagerStore } from '@/store/partners-pager-store';

// « Tout voir » — every matching dispo, full-width compact cards, filters as
// pills on top: my dispo's sports, a universe (from the « Explorer par sport »
// grid), and the vibes sheet (client-side, OR logic — any selected vibe).
export default function PartnersDisposScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const setPagerIds = usePartnersPagerStore((s) => s.setUserIds);
  const params = useLocalSearchParams<{ universe?: string }>();

  const [universe, setUniverse] = useState<Universe | null>(
    UNIVERSES.includes(params.universe as Universe) ? (params.universe as Universe) : null,
  );
  const [sportKey, setSportKey] = useState<string | null>(null);
  const [vibes, setVibes] = useState<Set<DispoIntent>>(new Set());
  const [vibesOpen, setVibesOpen] = useState(false);
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

  const filtered = useMemo(() => (cards ?? []).filter((c) =>
    (!universe || c.sport_keys.some((k) => categoryOf(k) === universe))
    && (!sportKey || c.sport_keys.includes(sportKey))
    && (vibes.size === 0 || (c.intent ?? []).some((i) => vibes.has(i))),
  ), [cards, universe, sportKey, vibes, categoryOf]);

  const noFilter = !universe && !sportKey && vibes.size === 0;
  const clearAll = () => { setUniverse(null); setSportKey(null); setVibes(new Set()); };

  const open = (userId: string) => {
    setPagerIds(filtered.map((c) => c.user_id));
    router.push({ pathname: '/(auth)/partners/dispo', params: { userId } });
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top + spacing.sm }]}>
      <View style={styles.topBar}>
        <PressableScale style={styles.back} onPress={() => router.back()} accessibilityRole="button" accessibilityLabel={t('common.back', { defaultValue: 'Retour' })}>
          <ChevronLeft size={20} color={colors.textPrimary} strokeWidth={2.6} />
        </PressableScale>
        <Text style={styles.title} numberOfLines={1}>
          {t('partenaires.dispos', { defaultValue: 'Dispos qui collent' })}
          <Text style={styles.titleCount}>{`  ${filtered.length}`}</Text>
        </Text>
      </View>

      {/* Filter pills */}
      <View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.pills}>
          <PressableScale style={[styles.pill, noFilter ? styles.pillOn : styles.pillOff]} onPress={clearAll}>
            <Text style={[styles.pillText, noFilter && styles.pillTextOn]}>{t('partenaires.all', { defaultValue: 'Tous' })}</Text>
          </PressableScale>
          {universe ? (
            <PressableScale style={[styles.pill, { backgroundColor: sportCategoryColor(universe, colors.cta) }]} onPress={() => setUniverse(null)}>
              <Text style={[styles.pillText, styles.pillTextOn]}>{t(`partenaires.universe.${universe}`)}</Text>
              <X size={13} color="#FFFFFF" strokeWidth={2.8} />
            </PressableScale>
          ) : null}
          {(mine?.sport_keys ?? []).map((k) => {
            const c = sportCategoryColor(categoryOf(k), colors.cta);
            const on = sportKey === k;
            return (
              <PressableScale key={k} style={[styles.pill, { backgroundColor: on ? c : c + '1A' }]} onPress={() => setSportKey(on ? null : k)}>
                <Text style={[styles.pillText, { color: on ? '#FFFFFF' : c }]}>{t(`sports.${k}`, { defaultValue: k })}</Text>
              </PressableScale>
            );
          })}
          <View style={styles.pillSep} />
          <PressableScale style={[styles.pill, vibes.size > 0 ? styles.pillOn : styles.pillOff]} onPress={() => setVibesOpen(true)}>
            <SlidersHorizontal size={13} color={vibes.size > 0 ? '#FFFFFF' : colors.textPrimary} strokeWidth={2.4} />
            <Text style={[styles.pillText, vibes.size > 0 && styles.pillTextOn]}>
              {t('partenaires.vibes', { defaultValue: 'Vibes' })}{vibes.size > 0 ? ` · ${vibes.size}` : ''}
            </Text>
          </PressableScale>
        </ScrollView>
      </View>

      {active && isLoading ? (
        <View style={styles.center}><LogoSpinner size={40} /></View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(c) => c.user_id}
          renderItem={({ item }) => <DispoCardCompact card={item} categoryOf={categoryOf} onPress={() => open(item.user_id)} />}
          contentContainerStyle={styles.list}
          ItemSeparatorComponent={() => <View style={{ height: 14 }} />}
          refreshControl={<RefreshControl refreshing={false} onRefresh={() => void queryClient.refetchQueries({ queryKey: ['discovery-cards'] })} tintColor={colors.cta} />}
          ListEmptyComponent={(
            <View style={styles.empty}>
              <Telescope size={30} color={colors.textMuted} strokeWidth={2} />
              <Text style={styles.emptyTitle}>
                {!active
                  ? t('partenaires.noDispoTitle', { defaultValue: 'Pose ta dispo' })
                  : noFilter
                    ? t('discovery.noMatchesTitle', { defaultValue: 'Personne pour l’instant' })
                    : t('discovery.filterEmptyTitle', { defaultValue: 'Aucun avec ces filtres' })}
              </Text>
              {!active ? (
                <PressableScale onPress={() => router.push('/(auth)/discovery-compose')} hitSlop={8}>
                  <Text style={styles.emptyLink}>{t('discovery.composeDispo', { defaultValue: 'Composer ma dispo' })}</Text>
                </PressableScale>
              ) : !noFilter ? (
                <PressableScale onPress={clearAll} hitSlop={8}>
                  <Text style={styles.emptyLink}>{t('discovery.filterClear', { defaultValue: 'Effacer' })}</Text>
                </PressableScale>
              ) : null}
            </View>
          )}
        />
      )}

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
              <PressableScale style={styles.sheetApply} onPress={() => setVibesOpen(false)}>
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
  title: { flex: 1, color: colors.textPrimary, fontFamily: fonts.title, fontSize: 22 },
  titleCount: { color: colors.cta },
  pills: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingHorizontal: spacing.md, paddingTop: spacing.md, paddingBottom: spacing.xs },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 5, borderRadius: radius.full, paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm },
  pillOn: { backgroundColor: colors.textPrimary },
  pillOff: { backgroundColor: colors.surfaceAlt },
  pillText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  pillTextOn: { color: colors.background, fontWeight: '700' },
  pillSep: { width: 1, height: 22, backgroundColor: colors.lineStrong },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: spacing.md, paddingBottom: spacing.xl * 2 },
  empty: { alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xl },
  emptyTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', textAlign: 'center' },
  emptyLink: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '700' },
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
