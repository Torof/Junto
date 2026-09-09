import { useMemo, useState } from 'react';
import { View, Text, Pressable, FlatList, TextInput, StyleSheet, Modal } from 'react-native';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Search, Plus, Users, SlidersHorizontal, MapPin, X } from 'lucide-react-native';
import { useColors, useResolvedTheme } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { channelService, type ChannelListItem } from '@/services/channel-service';
import { SportDropdown } from '@/components/sport-dropdown';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { CollapsibleSection } from '@/components/collapsible-section';
import { LogoSpinner } from '@/components/logo-spinner';
import { sportCategoryColor, mixHex } from '@/utils/sport-category-color';
import { useSports } from '@/hooks/use-sports';
import { useInitialLocation } from '@/hooks/use-initial-location';

export function ChannelsView() {
  const colors = useColors();
  const resolvedTheme = useResolvedTheme();
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

  // Card tint: sport-universe colour blended 30% into an opaque base (white in
  // light, the surface in dark) — clearly marked, dark title still legible, and
  // OPAQUE so Android's elevation doesn't ghost a grey rectangle behind it.
  const tintBase = resolvedTheme === 'light' ? '#FFFFFF' : colors.surface;
  const neutralTint = resolvedTheme === 'light' ? '#E7DBC2' : colors.surface;

  const renderItem = ({ item }: { item: ChannelListItem }) => {
    const firstSport = item.sport_key;
    const cat = firstSport ? sportById.get(firstSport)?.category : undefined;
    const tint = firstSport ? sportCategoryColor(cat, colors.cta) : null;
    const sportName = firstSport ? t(`sports.${firstSport}`, { defaultValue: firstSport }) : null;
    const cardBg = tint ? mixHex(tint, tintBase, 0.3) : neutralTint;
    return (
      <Pressable
        style={[styles.card, { backgroundColor: cardBg }]}
        onPress={() => router.push(`/(auth)/conversation/${item.conversation_id}`)}
      >
        {!!item.photo_url && (
          <View style={styles.cardPhotoClip}>
            <Image source={{ uri: item.photo_url }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150} />
          </View>
        )}
        <Text style={styles.rowName} numberOfLines={2}>{item.name}</Text>
        <View style={styles.metaRow}>
          {sportName && tint && (
            <View style={[styles.sportPill, { backgroundColor: tint }]}>
              <Text style={styles.sportPillText} numberOfLines={1}>{sportName}</Text>
            </View>
          )}
          <View style={styles.metaItem}>
            <MapPin size={12} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.metaText} numberOfLines={1}>
              {item.base_label} · {item.radius_km} km{item.distance_km != null ? ` · ${t('channels.away', { defaultValue: 'à {{km}} km', km: Math.round(item.distance_km) })}` : ''}
            </Text>
          </View>
        </View>
        <View style={styles.footRow}>
          <View style={styles.metaItem}>
            <Users size={13} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.metaText}>{t('channels.memberCount', { count: item.member_count, defaultValue: '{{count}} membres' })}</Text>
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
  // Tinted card (variant A base): opaque sport-universe tint, full-width title
  // on up to 2 lines, meta line (sport · place · radius), and a footer with the
  // member count + Rejoindre/Membre. No emoji thumb (redundant with the pill).
  card: { borderRadius: 18, borderWidth: 1, borderColor: colors.border, paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 4, ...shadows.card },
  // Optional channel photo — faint behind the opaque tint (direction A); the
  // dark title stays legible. Clipped to the card radius in its own layer so
  // the card itself keeps overflow:visible (Android needs that to cast the
  // elevation shadow), and painted before the content so it sits underneath.
  cardPhotoClip: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, borderRadius: 18, overflow: 'hidden', opacity: 0.22 },
  rowName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800', letterSpacing: -0.2, lineHeight: 21 },
  metaRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 4, marginTop: 8 },
  metaItem: { flexDirection: 'row', alignItems: 'center', gap: 4, minWidth: 0, flexShrink: 1 },
  metaText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  sportPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 3, marginRight: spacing.xs + 2 },
  sportPillText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '800' },
  footRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 10 },
  tag: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 5 },
  tagMember: { backgroundColor: 'rgba(255,255,255,0.55)', borderWidth: 1, borderColor: colors.border },
  tagMemberText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800' },
  tagJoin: { backgroundColor: colors.cta },
  tagJoinText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '800' },
  fab: { position: 'absolute', right: spacing.md, bottom: spacing.lg, flexDirection: 'row', alignItems: 'center', gap: spacing.xs, backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.md + 2, paddingVertical: spacing.sm + 3, ...shadows.raised },
  fabText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
