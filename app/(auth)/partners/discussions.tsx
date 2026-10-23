import { useCallback, useMemo, useState } from 'react';
import { View, FlatList, ScrollView, StyleSheet, Modal, Pressable } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronDown, Plus, Search, MapPin, X, Globe } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius, glow, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { channelService } from '@/services/channel-service';
import { discoveryService } from '@/services/discovery-service';
import { useSports } from '@/hooks/use-sports';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { SportDropdown } from '@/components/sport-dropdown';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { CollapsibleSection } from '@/components/collapsible-section';
import { ChannelTile } from '@/components/partners/channel-tile';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { UNIVERSES, type Universe } from '@/constants/discovery-vibes';

// « Tout voir » — discussions: search, filters as pills (place, universes, a
// precise sport in the sheet), full-width tiles (channel photo, else the
// universe colour + glyph). Search and place filter run server-side as before;
// the universe is a client-side filter on the results.
export default function PartnersDiscussionsScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ universe?: string }>();
  const { currentLocation } = useInitialLocation();

  const [query, setQuery] = useState('');
  const [sportKey, setSportKey] = useState<string | null>(null);
  const [near, setNear] = useState<{ lng: number; lat: number; label: string } | null>(null);
  const [universe, setUniverse] = useState<Universe | null>(
    UNIVERSES.includes(params.universe as Universe) ? (params.universe as Universe) : null,
  );
  const [showFilters, setShowFilters] = useState(false);

  const { data: mine } = useQuery({ queryKey: ['my-dispo'], queryFn: () => discoveryService.getMyDispo() });
  const { data: sports } = useSports();
  const categoryOf = useCallback((key: string) => (sports ?? []).find((s) => s.key === key)?.category, [sports]);

  const trimmed = query.trim();
  const { data: channels, isLoading } = useQuery({
    queryKey: ['channels', trimmed, sportKey, near?.lng, near?.lat],
    queryFn: () => channelService.search({ query: trimmed || null, sportKey, nearLng: near?.lng ?? null, nearLat: near?.lat ?? null }),
  });
  const shown = useMemo(
    () => (channels ?? []).filter((c) => !universe || (c.sport_key ? categoryOf(c.sport_key) === universe : false)),
    [channels, universe, categoryOf],
  );

  const useMyLocation = () => {
    if (!currentLocation) return;
    setNear({ lng: currentLocation[0], lat: currentLocation[1], label: t('channels.myLocation', { defaultValue: 'Ma position' }) });
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top + spacing.sm }]}>
      <View style={styles.topBar}>
        <PressableScale style={styles.back} onPress={() => router.back()} accessibilityRole="button" accessibilityLabel={t('common.back', { defaultValue: 'Retour' })}>
          <ChevronLeft size={20} color={colors.textPrimary} strokeWidth={2.6} />
        </PressableScale>
        <AppText style={styles.title}>{t('partenaires.channels', { defaultValue: 'Discussions' })}</AppText>
        <PressableScale style={styles.add} onPress={() => router.push('/(auth)/create-channel')} accessibilityRole="button" accessibilityLabel={t('partenaires.openDiscussion', { defaultValue: 'Ouvrir une discussion' })}>
          <Plus size={20} color="#FFFFFF" strokeWidth={2.8} />
        </PressableScale>
      </View>

      {/* Searching anywhere is the main action (Scott 2026-10-23: one joins
          channels for the places one goes to, not only home). */}
      <View style={styles.searchBlock}>
        <View style={styles.search}>
          <Search size={18} color={colors.textPrimary} strokeWidth={2.4} />
          <AppTextInput
            style={styles.searchInput}
            value={query}
            onChangeText={setQuery}
            placeholder={t('partenaires.searchEverywhere', { defaultValue: 'Cherche partout : un lieu, un sport, un nom…' })}
            placeholderTextColor={colors.textMuted}
            returnKeyType="search"
          />
        </View>
        <View style={styles.whereRow}>
          <AppText style={styles.whereLabel}>{t('partenaires.where', { defaultValue: 'Où ?' })}</AppText>
          <PressableScale style={styles.wherePill} onPress={() => setShowFilters(true)} accessibilityRole="button">
            {near ? <MapPin size={14} color={colors.cta} strokeWidth={2.6} /> : <Globe size={14} color={colors.cta} strokeWidth={2.4} />}
            <AppText style={styles.wherePillText} numberOfLines={1}>
              {near ? near.label : t('partenaires.everywhere', { defaultValue: 'Partout' })}
              {sportKey ? ` · ${t(`sports.${sportKey}`, { defaultValue: sportKey })}` : ''}
            </AppText>
            <ChevronDown size={14} color={colors.textPrimary} strokeWidth={2.6} />
          </PressableScale>
          {near ? (
            <PressableScale onPress={() => setNear(null)} hitSlop={8} accessibilityRole="button" accessibilityLabel={t('partenaires.everywhere', { defaultValue: 'Partout' })}>
              <X size={16} color={colors.textSecondary} strokeWidth={2.6} />
            </PressableScale>
          ) : null}
        </View>
        <View style={styles.shortcuts}>
          {currentLocation ? (
            <PressableScale style={styles.shortcut} onPress={useMyLocation}>
              <AppText style={styles.shortcutText}>{t('partenaires.aroundMe', { defaultValue: 'Autour de moi' })}</AppText>
            </PressableScale>
          ) : null}
          {mine ? (
            <PressableScale style={styles.shortcut} onPress={() => setNear({ lng: mine.base_lng, lat: mine.base_lat, label: mine.base_label })}>
              <AppText style={styles.shortcutText}>{t('partenaires.aroundMyDispo', { defaultValue: 'Autour de ma dispo' })}</AppText>
            </PressableScale>
          ) : null}
        </View>
      </View>

      <View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.pills} keyboardShouldPersistTaps="handled">
          <PressableScale style={[styles.pill, !universe ? styles.pillOn : styles.pillOff]} onPress={() => setUniverse(null)}>
            <AppText style={[styles.pillText, !universe && styles.pillTextOn]}>{t('partenaires.all', { defaultValue: 'Tous' })}</AppText>
          </PressableScale>
          {UNIVERSES.map((u) => {
            const c = sportCategoryColor(u, colors.cta);
            const on = universe === u;
            return (
              <PressableScale key={u} style={[styles.pill, { backgroundColor: on ? c : c + '1A' }]} onPress={() => setUniverse(on ? null : u)}>
                <AppText style={[styles.pillText, { color: on ? '#FFFFFF' : c }]}>{t(`partenaires.universe.${u}`)}</AppText>
              </PressableScale>
            );
          })}
        </ScrollView>
      </View>
      <AppText style={styles.sortLine}>
        {near
          ? t('partenaires.sortNear', { defaultValue: 'Autour de {{place}} · les plus proches d’abord', place: near.label })
          : t('partenaires.sortActive', { defaultValue: 'Partout · les plus suivies d’abord' })}
      </AppText>

      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={40} /></View>
      ) : (
        <FlatList
          data={shown}
          keyExtractor={(c) => c.conversation_id}
          renderItem={({ item }) => (
            <ChannelTile item={item} categoryOf={categoryOf} onPress={() => router.push(`/(auth)/conversation/${item.conversation_id}`)} />
          )}
          contentContainerStyle={styles.list}
          ItemSeparatorComponent={() => <View style={{ height: 14 }} />}
          keyboardShouldPersistTaps="handled"
          ListEmptyComponent={<AppText style={styles.empty}>{t('channels.none', { defaultValue: 'Aucune discussion ici pour l’instant. Crée le premier !' })}</AppText>}
        />
      )}

      {/* Place + sport sheet — as before. */}
      <Modal visible={showFilters} transparent animationType="slide" onRequestClose={() => setShowFilters(false)}>
        <Pressable style={styles.backdrop} onPress={() => setShowFilters(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.sheetHead}>
              <AppText style={styles.sheetTitle}>{t('channels.filters', { defaultValue: 'Filtres' })}</AppText>
              <Pressable onPress={() => setShowFilters(false)} hitSlop={8}><X size={22} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
            </View>
            <CollapsibleSection title={t('channels.filterLocation', { defaultValue: 'Localisation' })} summary={near?.label ?? null} defaultExpanded={!!near}>
              {near && (
                <View style={styles.chosenRow}>
                  <MapPin size={14} color={colors.cta} strokeWidth={2.4} />
                  <AppText style={styles.chosen} numberOfLines={1}>{near.label}</AppText>
                  <AppText style={styles.clear} onPress={() => setNear(null)}>{t('channels.clear', { defaultValue: 'retirer' })}</AppText>
                </View>
              )}
              <PlaceSearchBar onSelect={(p) => setNear({ lng: p.lng, lat: p.lat, label: p.label })} />
              {currentLocation && (
                <Pressable style={styles.myPos} onPress={useMyLocation}>
                  <MapPin size={15} color={colors.cta} strokeWidth={2.4} />
                  <AppText style={styles.myPosText}>{t('channels.useMyLocation', { defaultValue: 'Autour de ma position' })}</AppText>
                </Pressable>
              )}
            </CollapsibleSection>
            <CollapsibleSection title={t('channels.filterSport', { defaultValue: 'Sport' })} summary={sportKey ? t(`sports.${sportKey}`, { defaultValue: sportKey }) : null}>
              <SportDropdown selected={sportKey ? [sportKey] : []} onSelect={(k) => setSportKey((prev) => (prev === k ? null : k))} label={t('map.sportLabel')} />
            </CollapsibleSection>
            <PressableScale style={styles.apply} onPress={() => setShowFilters(false)}>
              <AppText style={styles.applyText}>{t('channels.applyFilters', { defaultValue: 'Voir les discussions' })}</AppText>
            </PressableScale>
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
  add: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center', ...glow(colors.cta) },
  searchBlock: { marginHorizontal: spacing.md, marginTop: spacing.md, padding: spacing.sm + 6, borderRadius: 18, backgroundColor: colors.surfaceAlt, gap: spacing.sm + 4 },
  search: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, backgroundColor: colors.surface,
    borderRadius: 14, paddingHorizontal: spacing.md - 2, height: 50, ...shadows.card,
  },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md - 1, padding: 0 },
  whereRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  whereLabel: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '700', letterSpacing: 0.4, textTransform: 'uppercase' },
  wherePill: {
    flexDirection: 'row', alignItems: 'center', gap: 6, flexShrink: 1, backgroundColor: colors.surface,
    borderRadius: radius.full, paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm, ...shadows.card,
  },
  wherePillText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700', flexShrink: 1 },
  shortcuts: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  shortcut: { backgroundColor: colors.cta + '1A', borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 7 },
  shortcutText: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  pills: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingHorizontal: spacing.md, paddingTop: spacing.sm + 6, paddingBottom: spacing.xs },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 5, borderRadius: radius.full, paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm },
  pillOn: { backgroundColor: colors.textPrimary },
  pillOff: { backgroundColor: colors.surfaceAlt },
  pillText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  pillTextOn: { color: colors.background },
  sortLine: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, paddingHorizontal: spacing.md, paddingTop: spacing.sm },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: spacing.md, paddingBottom: spacing.xl * 2 },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, lineHeight: 22 },
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl, paddingHorizontal: spacing.lg, paddingBottom: spacing.xl },
  sheetHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: spacing.md },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  chosenRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginBottom: spacing.sm },
  chosen: { flex: 1, minWidth: 0, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  clear: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', textDecorationLine: 'underline' },
  myPos: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, paddingVertical: spacing.sm, marginTop: spacing.xs },
  myPosText: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '700' },
  apply: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 4, alignItems: 'center', marginTop: spacing.lg },
  applyText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
