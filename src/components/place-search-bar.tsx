import { useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, TextInput, Pressable, ActivityIndicator, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Search, X, MapPin, Pencil } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { geocodeService, type PlaceResult } from '@/services/geocode-service';

interface Props {
  onSelect: (place: PlaceResult) => void;
  bias?: { lat: number; lng: number } | null;
  // Opt-in free-text fallback: when provided, the user can keep their typed
  // text (no coords) — a "Utiliser « … »" row + keyboard submit. Callers that
  // need coordinates (map, discovery, channels) simply omit this.
  onFreeText?: (text: string) => void;
}

// Map place search (Photon). Type a place → pick → the map flies there and the
// activities around load via the existing bounds search.
export function PlaceSearchBar({ onSelect, bias, onFreeText }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [query, setQuery] = useState('');
  const [debounced, setDebounced] = useState('');
  const [focused, setFocused] = useState(false);
  const inputRef = useRef<TextInput>(null);

  useEffect(() => {
    const id = setTimeout(() => setDebounced(query.trim()), 300);
    return () => clearTimeout(id);
  }, [query]);

  const { data: results, isFetching } = useQuery({
    queryKey: ['geocode', debounced, bias?.lat ?? 0, bias?.lng ?? 0],
    queryFn: ({ signal }) => geocodeService.searchPlaces(debounced, bias ?? undefined, signal),
    enabled: debounced.length >= 2,
    staleTime: 5 * 60_000,
  });

  const showResults = focused && debounced.length >= 2;

  const reset = () => {
    setQuery('');
    setDebounced('');
    setFocused(false);
    inputRef.current?.blur();
  };
  const pick = (place: PlaceResult) => {
    onSelect(place);
    reset();
  };
  const useFree = () => {
    const v = query.trim();
    if (v && onFreeText) {
      onFreeText(v);
      reset();
    }
  };
  const freeText = query.trim();
  const showFreeRow = !!onFreeText && focused && freeText.length >= 1;

  return (
    <View style={styles.wrap}>
      <View style={styles.bar}>
        <Search size={18} color={colors.textSecondary} strokeWidth={2.2} />
        <TextInput
          ref={inputRef}
          style={styles.input}
          value={query}
          onChangeText={setQuery}
          onFocus={() => setFocused(true)}
          placeholder={t('map.searchPlace', { defaultValue: 'Rechercher un lieu…' })}
          placeholderTextColor={colors.textSecondary}
          returnKeyType={onFreeText ? 'done' : 'search'}
          onSubmitEditing={useFree}
          autoCorrect={false}
        />
        {isFetching && showResults && <ActivityIndicator size="small" color={colors.textSecondary} />}
        {query.length > 0 && (
          <Pressable onPress={() => { setQuery(''); setDebounced(''); }} hitSlop={8}>
            <X size={18} color={colors.textSecondary} strokeWidth={2.2} />
          </Pressable>
        )}
      </View>

      {((showResults && (results?.length ?? 0) > 0) || showFreeRow) && (
        <View style={styles.dropdown}>
          {showFreeRow && (
            <Pressable style={styles.row} onPress={useFree}>
              <Pencil size={15} color={colors.cta} strokeWidth={2.2} />
              <Text style={styles.freeRowText} numberOfLines={1}>
                {t('map.useFreeText', { defaultValue: 'Utiliser « {{text}} »', text: freeText })}
              </Text>
            </Pressable>
          )}
          {showResults && (results ?? []).map((item) => (
            <Pressable key={item.id} style={styles.row} onPress={() => pick(item)}>
              <MapPin size={16} color={colors.textSecondary} strokeWidth={2.2} />
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={styles.rowLabel} numberOfLines={1}>{item.label}</Text>
                {!!item.sublabel && <Text style={styles.rowSub} numberOfLines={1}>{item.sublabel}</Text>}
              </View>
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrap: { width: '100%' },
  bar: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.background, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.borderStrong,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
  },
  input: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, padding: 0 },
  dropdown: {
    marginTop: spacing.xs, backgroundColor: colors.background,
    borderRadius: radius.md, borderWidth: 1, borderColor: colors.borderStrong,
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderBottomWidth: 1, borderBottomColor: colors.borderMuted,
  },
  rowLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  rowSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  freeRowText: { flex: 1, color: colors.cta, fontSize: fontSizes.sm, fontWeight: '800' },
});
