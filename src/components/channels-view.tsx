import { useMemo, useState } from 'react';
import { View, Text, Pressable, FlatList, TextInput, StyleSheet, Modal } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Search, Plus, Users, SlidersHorizontal, MapPin, X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { channelService, type ChannelListItem } from '@/services/channel-service';
import { SportDropdown } from '@/components/sport-dropdown';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { CollapsibleSection } from '@/components/collapsible-section';
import { LogoSpinner } from '@/components/logo-spinner';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';
import { useSports } from '@/hooks/use-sports';
import { useInitialLocation } from '@/hooks/use-initial-location';

export function ChannelsView() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();

  const { currentLocation } = useInitialLocation();

  const [query, setQuery] = useState('');
  const [sportKey, setSportKey] = useState<string | null>(null);
  const [near, setNear] = useState<{ lng: number; lat: number; label: string } | null>(null);
  const [showFilters, setShowFilters] = useState(false);


  const { data: sports } = useSports();
  const sportById = useMemo(() => new Map((sports ?? []).map((s) => [s.key, s])), [sports]);

  const activeFilters = (sportKey ? 1 : 0) + (near ? 1 : 0);
  const trimmed = query.trim();
  const { data: channels, isLoading } = useQuery({
    queryKey: ['channels', trimmed, sportKey, near?.lng, near?.lat],
    queryFn: () => channelService.search({
      query: trimmed || null,
      sportKey,
      nearLng: near?.lng ?? null,
      nearLat: near?.lat ?? null,
    }),
  });

  const useMyLocation = () => {
    if (!currentLocation) return;
    setNear({ lng: currentLocation[0], lat: currentLocation[1], label: t('channels.myLocation', { defaultValue: 'Ma position' }) });
  };

  const renderItem = ({ item }: { item: ChannelListItem }) => {
    const cat = sportById.get(item.sport_key)?.category;
    const tint = sportCategoryColor(cat, colors.cta);
    const zone = `${item.base_label} · ${item.radius_km} km${item.distance_km != null ? ` · ${t('channels.away', { defaultValue: 'à {{km}} km', km: Math.round(item.distance_km) })}` : ''}`;
    return (
      <Pressable style={styles.row} onPress={() => router.push(`/(auth)/conversation/${item.conversation_id}`)}>
        <View style={[styles.thumb, { backgroundColor: tint + '22' }]}>
          <Text style={styles.thumbIcon}>{getSportIcon(item.sport_key)}</Text>
        </View>
        <View style={styles.rowMain}>
          <Text style={styles.rowName} numberOfLines={1}>{item.name}</Text>
          <Text style={styles.rowPlace} numberOfLines={1}>{zone}</Text>
        </View>
        <View style={styles.rowRight}>
          <View style={styles.rowCount}>
            <Users size={13} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.rowCountText}>{item.member_count}</Text>
          </View>
          <View style={[styles.tag, item.is_member ? styles.tagMember : styles.tagJoin]}>
            <Text style={item.is_member ? styles.tagMemberText : styles.tagJoinText}>
              {item.is_member ? t('channels.member', { defaultValue: 'Membre' }) : t('channels.join', { defaultValue: 'Rejoindre' })}
            </Text>
          </View>
        </View>
      </Pressable>
    );
  };

  return (
    <View style={styles.container}>
      <View style={styles.filters}>
        <View style={styles.searchRow}>
          <View style={styles.searchBox}>
            <Search size={16} color={colors.textSecondary} strokeWidth={2.2} />
            <TextInput
              style={styles.searchInput}
              value={query}
              onChangeText={setQuery}
              placeholder={t('channels.searchPlaceholder', { defaultValue: 'Chercher un canal…' })}
              placeholderTextColor={colors.textMuted}
              returnKeyType="search"
            />
          </View>
          <Pressable style={[styles.filterBtn, activeFilters > 0 && styles.filterBtnActive]} onPress={() => setShowFilters(true)}>
            <SlidersHorizontal size={18} color={activeFilters > 0 ? '#FFFFFF' : colors.textPrimary} strokeWidth={2.2} />
            {activeFilters > 0 && <Text style={styles.filterBtnCount}>{activeFilters}</Text>}
          </Pressable>
        </View>
      </View>

      {/* Filter sheet — mirrors the map filter (Localisation / Rayon / Sport). */}
      <Modal visible={showFilters} transparent animationType="slide" onRequestClose={() => setShowFilters(false)}>
        <Pressable style={styles.sheetBackdrop} onPress={() => setShowFilters(false)}>
          <Pressable style={styles.sheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.sheetHeader}>
              <Text style={styles.sheetTitle}>{t('channels.filters', { defaultValue: 'Filtres' })}</Text>
              <Pressable onPress={() => setShowFilters(false)} hitSlop={8}><X size={22} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
            </View>

            <CollapsibleSection
              title={t('channels.filterLocation', { defaultValue: 'Localisation' })}
              summary={near?.label ?? null}
              defaultExpanded={!!near}
            >
              {near && (
                <View style={styles.chosenPlaceRow}>
                  <MapPin size={14} color={colors.cta} strokeWidth={2.4} />
                  <Text style={styles.chosenPlace} numberOfLines={1}>{near.label}</Text>
                  <Text style={styles.placeClear} onPress={() => setNear(null)}>{t('channels.clear', { defaultValue: 'retirer' })}</Text>
                </View>
              )}
              <PlaceSearchBar onSelect={(p) => setNear({ lng: p.lng, lat: p.lat, label: p.label })} />
              {currentLocation && (
                <Pressable style={styles.myPosBtn} onPress={useMyLocation}>
                  <MapPin size={15} color={colors.cta} strokeWidth={2.4} />
                  <Text style={styles.myPosText}>{t('channels.useMyLocation', { defaultValue: 'Autour de ma position' })}</Text>
                </Pressable>
              )}
            </CollapsibleSection>

            <CollapsibleSection
              title={t('channels.filterSport', { defaultValue: 'Sport' })}
              summary={sportKey ? t(`sports.${sportKey}`, { defaultValue: sportKey }) : null}
            >
              <SportDropdown
                selected={sportKey ? [sportKey] : []}
                onSelect={(k) => setSportKey((prev) => (prev === k ? null : k))}
                label={t('map.sportLabel')}
              />
            </CollapsibleSection>

            <Pressable style={styles.sheetApply} onPress={() => setShowFilters(false)}>
              <Text style={styles.sheetApplyText}>{t('channels.applyFilters', { defaultValue: 'Voir les canaux' })}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={40} /></View>
      ) : (
        <FlatList
          data={channels ?? []}
          keyExtractor={(i) => i.conversation_id}
          renderItem={renderItem}
          contentContainerStyle={styles.list}
          keyboardShouldPersistTaps="handled"
          ListEmptyComponent={
            <Text style={styles.empty}>{t('channels.none', { defaultValue: 'Aucun canal ici pour l’instant. Crée le premier !' })}</Text>
          }
        />
      )}

      <Pressable style={styles.fab} onPress={() => router.push('/(auth)/create-channel')}>
        <Plus size={20} color="#FFFFFF" strokeWidth={2.6} />
        <Text style={styles.fabText}>{t('channels.create', { defaultValue: 'Créer un canal' })}</Text>
      </Pressable>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  filters: { paddingHorizontal: spacing.md, paddingTop: spacing.sm, paddingBottom: spacing.sm },
  searchRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  searchBox: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: spacing.sm, backgroundColor: colors.surface, borderRadius: 14, paddingHorizontal: spacing.md, height: 46, ...shadows.card },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, padding: 0 },
  filterBtn: { flexDirection: 'row', alignItems: 'center', gap: 5, height: 46, paddingHorizontal: spacing.md, borderRadius: 14, backgroundColor: colors.surface, ...shadows.card },
  filterBtnActive: { backgroundColor: colors.cta },
  filterBtnCount: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  chip: { borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 5 },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipDisabled: { opacity: 0.4 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2 },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  chipTextOn: { color: '#FFFFFF' },
  sheetBackdrop: { flex: 1, backgroundColor: '#00000088', justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl, paddingHorizontal: spacing.lg, paddingBottom: spacing.xl },
  sheetHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: spacing.md },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  chosenPlaceRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginBottom: spacing.sm },
  chosenPlace: { flex: 1, minWidth: 0, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  placeClear: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', textDecorationLine: 'underline' },
  myPosBtn: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, paddingVertical: spacing.sm, marginTop: spacing.xs },
  myPosText: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '700' },
  radiusHint: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.sm },
  sheetApply: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, alignItems: 'center', marginTop: spacing.lg },
  sheetApplyText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: spacing.md, gap: spacing.sm + 2, paddingBottom: 100 },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, lineHeight: 22 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, borderRadius: 18, backgroundColor: colors.surface, padding: spacing.sm + 4, ...shadows.card },
  thumb: { width: 48, height: 48, borderRadius: 15, alignItems: 'center', justifyContent: 'center' },
  thumbIcon: { fontSize: 24 },
  rowMain: { flex: 1, minWidth: 0, gap: 2 },
  rowName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', letterSpacing: -0.2 },
  rowPlace: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600', flexShrink: 1 },
  rowRight: { alignItems: 'flex-end', gap: spacing.xs + 2 },
  rowCount: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  rowCountText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '800' },
  tag: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 1, paddingVertical: 3 },
  tagMember: { backgroundColor: colors.cta + '22' },
  tagMemberText: { color: colors.cta, fontSize: fontSizes.xs - 1, fontWeight: '800' },
  tagJoin: { backgroundColor: colors.cta },
  tagJoinText: { color: '#FFFFFF', fontSize: fontSizes.xs - 1, fontWeight: '800' },
  fab: { position: 'absolute', right: spacing.md, bottom: spacing.lg, flexDirection: 'row', alignItems: 'center', gap: spacing.xs, backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.md + 2, paddingVertical: spacing.sm + 3, ...shadows.raised },
  fabText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
