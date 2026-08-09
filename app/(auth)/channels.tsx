import { useLayoutEffect, useMemo, useState } from 'react';
import { View, Text, Pressable, FlatList, TextInput, StyleSheet } from 'react-native';
import { useRouter, useNavigation } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Search, Plus, Users } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { channelService, type ChannelListItem } from '@/services/channel-service';
import { SportDropdown } from '@/components/sport-dropdown';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { LogoSpinner } from '@/components/logo-spinner';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';
import { useSports } from '@/hooks/use-sports';

export default function ChannelsScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();

  const [query, setQuery] = useState('');
  const [sportKey, setSportKey] = useState<string | null>(null);
  const [near, setNear] = useState<{ lng: number; lat: number; label: string } | null>(null);

  useLayoutEffect(() => {
    navigation.setOptions({ title: t('channels.title', { defaultValue: 'Canaux' }) });
  }, [navigation, t]);

  const { data: sports } = useSports();
  const sportById = useMemo(() => new Map((sports ?? []).map((s) => [s.key, s])), [sports]);

  const trimmed = query.trim();
  const { data: channels, isLoading } = useQuery({
    queryKey: ['channels', trimmed, sportKey, near?.lng, near?.lat],
    queryFn: () => channelService.search({
      query: trimmed || null,
      sportKey,
      nearLng: near?.lng ?? null,
      nearLat: near?.lat ?? null,
      radiusKm: null,
    }),
  });

  const renderItem = ({ item }: { item: ChannelListItem }) => {
    const cat = sportById.get(item.sport_key)?.category;
    return (
      <Pressable style={styles.row} onPress={() => router.push(`/(auth)/conversation/${item.conversation_id}`)}>
        <View style={styles.rowMain}>
          <Text style={styles.rowName} numberOfLines={1}>{item.name}</Text>
          <View style={styles.rowMeta}>
            <View style={[styles.sportPill, { backgroundColor: sportCategoryColor(cat, colors.cta) }]}>
              <Text style={styles.sportPillText}>{getSportIcon(item.sport_key)} {t(`sports.${item.sport_key}`, { defaultValue: item.sport_key })}</Text>
            </View>
            <Text style={styles.rowPlace} numberOfLines={1}>
              {item.base_label}{item.distance_km != null ? ` · ${Math.round(item.distance_km)} km` : ''}
            </Text>
          </View>
        </View>
        <View style={styles.rowCount}>
          <Users size={13} color={colors.textSecondary} strokeWidth={2.2} />
          <Text style={styles.rowCountText}>{item.member_count}</Text>
          {item.is_member && <View style={styles.memberDot} />}
        </View>
      </Pressable>
    );
  };

  return (
    <View style={styles.container}>
      <View style={styles.filters}>
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

        <SportDropdown
          selected={sportKey ? [sportKey] : []}
          onSelect={(k) => setSportKey((prev) => (prev === k ? null : k))}
          label={t('map.sportLabel')}
        />

        {near && <Text style={styles.nearLabel}>{t('channels.around', { defaultValue: 'Autour de' })} {near.label} · <Text style={styles.nearClear} onPress={() => setNear(null)}>{t('channels.clear', { defaultValue: 'retirer' })}</Text></Text>}
        <PlaceSearchBar onSelect={(p) => setNear({ lng: p.lng, lat: p.lat, label: p.label })} />
      </View>

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
  filters: { paddingHorizontal: spacing.md, paddingTop: spacing.sm, gap: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.borderMuted, paddingBottom: spacing.sm },
  searchBox: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md, paddingHorizontal: spacing.md, height: 42 },
  searchInput: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, padding: 0 },
  sportChips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  chip: { borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700' },
  chipTextOn: { color: '#FFFFFF' },
  nearLabel: { color: colors.textSecondary, fontSize: fontSizes.sm },
  nearClear: { color: colors.cta, fontWeight: '700', textDecorationLine: 'underline' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: spacing.md, paddingBottom: 96 },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, lineHeight: 22 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.lg, backgroundColor: colors.surface, padding: spacing.md, marginBottom: spacing.sm },
  rowMain: { flex: 1, minWidth: 0, gap: spacing.xs },
  rowName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  rowMeta: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  sportPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 3 },
  sportPillText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '700' },
  rowPlace: { color: colors.textSecondary, fontSize: fontSizes.sm, flexShrink: 1 },
  rowCount: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  rowCountText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  memberDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: colors.cta, marginLeft: 4 },
  fab: { position: 'absolute', right: spacing.md, bottom: spacing.lg, flexDirection: 'row', alignItems: 'center', gap: spacing.xs, backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.md + 2, paddingVertical: spacing.sm + 2, ...(colors ? {} : {}) },
  fabText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
