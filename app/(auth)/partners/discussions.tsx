import { useCallback, useMemo, useState } from 'react';
import { View, Text, FlatList, ScrollView, TextInput, StyleSheet, Modal, Pressable } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, Plus, Search, MapPin, X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius, glow } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { channelService } from '@/services/channel-service';
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
        <Text style={styles.title}>{t('partenaires.channels', { defaultValue: 'Discussions' })}</Text>
        <PressableScale style={styles.add} onPress={() => router.push('/(auth)/create-channel')} accessibilityRole="button" accessibilityLabel={t('partenaires.openDiscussion', { defaultValue: 'Ouvrir une discussion' })}>
          <Plus size={20} color="#FFFFFF" strokeWidth={2.8} />
        </PressableScale>
      </View>

      <View style={styles.search}>
        <Search size={16} color={colors.textSecondary} strokeWidth={2.2} />
        <TextInput
          style={styles.searchInput}
          value={query}
          onChangeText={setQuery}
          placeholder={t('channels.searchPlaceholder', { defaultValue: 'Chercher une discussion…' })}
          placeholderTextColor={colors.textMuted}
          returnKeyType="search"
        />
      </View>

      <View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.pills} keyboardShouldPersistTaps="handled">
          <PressableScale style={[styles.pill, styles.placePill]} onPress={() => setShowFilters(true)}>
            <MapPin size={13} color={colors.cta} strokeWidth={2.6} />
            <Text style={[styles.pillText, { color: colors.cta }]} numberOfLines={1}>
              {near ? near.label : t('partenaires.everywhere', { defaultValue: 'Partout' })}
              {sportKey ? ` · ${t(`sports.${sportKey}`, { defaultValue: sportKey })}` : ''}
            </Text>
          </PressableScale>
          {UNIVERSES.map((u) => {
            const c = sportCategoryColor(u, colors.cta);
            const on = universe === u;
            return (
              <PressableScale key={u} style={[styles.pill, { backgroundColor: on ? c : c + '1A' }]} onPress={() => setUniverse(on ? null : u)}>
                <Text style={[styles.pillText, { color: on ? '#FFFFFF' : c }]}>{t(`partenaires.universe.${u}`)}</Text>
              </PressableScale>
            );
          })}
        </ScrollView>
      </View>

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
          ListEmptyComponent={<Text style={styles.empty}>{t('channels.none', { defaultValue: 'Aucune discussion ici pour l’instant. Crée le premier !' })}</Text>}
        />
      )}

      {/* Place + sport sheet — as before. */}
      <Modal visible={showFilters} transparent animationType="slide" onRequestClose={() => setShowFilters(false)}>
        <Pressable style={styles.backdrop} onPress={() => setShowFilters(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.sheetHead}>
              <Text style={styles.sheetTitle}>{t('channels.filters', { defaultValue: 'Filtres' })}</Text>
              <Pressable onPress={() => setShowFilters(false)} hitSlop={8}><X size={22} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
            </View>
            <CollapsibleSection title={t('channels.filterLocation', { defaultValue: 'Localisation' })} summary={near?.label ?? null} defaultExpanded={!!near}>
              {near && (
                <View style={styles.chosenRow}>
                  <MapPin size={14} color={colors.cta} strokeWidth={2.4} />
                  <Text style={styles.chosen} numberOfLines={1}>{near.label}</Text>
                  <Text style={styles.clear} onPress={() => setNear(null)}>{t('channels.clear', { defaultValue: 'retirer' })}</Text>
                </View>
              )}
              <PlaceSearchBar onSelect={(p) => setNear({ lng: p.lng, lat: p.lat, label: p.label })} />
              {currentLocation && (
                <Pressable style={styles.myPos} onPress={useMyLocation}>
                  <MapPin size={15} color={colors.cta} strokeWidth={2.4} />
                  <Text style={styles.myPosText}>{t('channels.useMyLocation', { defaultValue: 'Autour de ma position' })}</Text>
                </Pressable>
              )}
            </CollapsibleSection>
            <CollapsibleSection title={t('channels.filterSport', { defaultValue: 'Sport' })} summary={sportKey ? t(`sports.${sportKey}`, { defaultValue: sportKey }) : null}>
              <SportDropdown selected={sportKey ? [sportKey] : []} onSelect={(k) => setSportKey((prev) => (prev === k ? null : k))} label={t('map.sportLabel')} />
            </CollapsibleSection>
            <PressableScale style={styles.apply} onPress={() => setShowFilters(false)}>
              <Text style={styles.applyText}>{t('channels.applyFilters', { defaultValue: 'Voir les discussions' })}</Text>
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
  search: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginHorizontal: spacing.md, marginTop: spacing.md,
    backgroundColor: colors.surfaceAlt, borderRadius: 14, paddingHorizontal: spacing.md - 2, height: 46,
  },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, padding: 0 },
  pills: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingHorizontal: spacing.md, paddingTop: spacing.sm + 4, paddingBottom: spacing.xs },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 5, borderRadius: radius.full, paddingHorizontal: spacing.sm + 6, paddingVertical: spacing.sm, maxWidth: 260 },
  placePill: { backgroundColor: colors.cta + '1A' },
  pillText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
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
