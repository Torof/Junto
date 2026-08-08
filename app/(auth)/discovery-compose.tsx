import { useEffect, useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Platform } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { X, Car, Bike, Footprints, Bus, Zap } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { SportDropdown } from '@/components/sport-dropdown';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { discoveryService, type TransportMode } from '@/services/discovery-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { haptic } from '@/lib/haptics';

const RADII: (number | null)[] = [5, 10, 15, 30, 50, null];
const MODES: { key: TransportMode; icon: typeof Car; label: string }[] = [
  { key: 'car', icon: Car, label: 'Voiture' },
  { key: 'motorbike', icon: Zap, label: 'Moto' },
  { key: 'bike', icon: Bike, label: 'Vélo' },
  { key: 'on_foot', icon: Footprints, label: 'À pied' },
  { key: 'public_transport', icon: Bus, label: 'Transports' },
];

export default function DiscoveryComposeScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const insets = useSafeAreaInsets();

  const [sportKeys, setSportKeys] = useState<string[]>([]);
  const [base, setBase] = useState<{ lng: number; lat: number; label: string } | null>(null);
  const [radiusKm, setRadiusKm] = useState<number | null>(30);
  const [modes, setModes] = useState<TransportMode[]>(['car']);
  const [windowStart, setWindowStart] = useState<Date>(new Date());
  const [windowEnd, setWindowEnd] = useState<Date>(dayjs().add(7, 'day').toDate());
  const [showStart, setShowStart] = useState(false);
  const [showEnd, setShowEnd] = useState(false);
  const [saving, setSaving] = useState(false);

  // Prefill from an existing dispo (edit).
  const { data: mine } = useQuery({ queryKey: ['my-dispo'], queryFn: () => discoveryService.getMyDispo() });
  useEffect(() => {
    if (!mine) return;
    setSportKeys(mine.sport_keys);
    setBase({ lng: mine.base_lng, lat: mine.base_lat, label: mine.base_label });
    setRadiusKm(mine.radius_km);
    setModes(mine.transport_modes);
    setWindowStart(new Date(mine.window_start));
    setWindowEnd(new Date(mine.window_end));
  }, [mine]);

  const toggleSport = (key: string) => setSportKeys((prev) =>
    prev.includes(key) ? prev.filter((k) => k !== key) : prev.length >= 3 ? prev : [...prev, key]);
  const toggleMode = (m: TransportMode) => setModes((prev) =>
    prev.includes(m) ? prev.filter((x) => x !== m) : [...prev, m]);

  const ready = sportKeys.length >= 1 && !!base && modes.length >= 1 && windowEnd > windowStart;

  // Live counter (debounced) — free during compose; seeing people needs activating.
  const { data: count } = useQuery({
    queryKey: ['discovery-count', sportKeys, base?.lng, base?.lat, radiusKm, windowStart.toISOString(), windowEnd.toISOString()],
    queryFn: () => discoveryService.getCount({
      sportKeys, baseLng: base!.lng, baseLat: base!.lat, radiusKm,
      windowStart: windowStart.toISOString(), windowEnd: windowEnd.toISOString(),
    }),
    enabled: ready,
    staleTime: 30_000,
  });

  const counterText = () => {
    if (!ready) return t('discovery.counterIncomplete', { defaultValue: 'Complète tes critères pour voir combien de passionnés correspondent.' });
    if (count === undefined) return '…';
    if (count === -1) return t('discovery.counterFew', { defaultValue: 'Quelques personnes correspondent dans ta zone.' });
    if (count === 0) return t('discovery.counterNone', { defaultValue: 'Personne pour l’instant — élargis ta zone ou tes dates.' });
    return t('discovery.counterN', { defaultValue: '{{count}} personnes correspondent dans ta zone.', count });
  };

  const handleActivate = async () => {
    if (!ready || saving) return;
    setSaving(true);
    try {
      haptic.success();
      await discoveryService.upsert({
        sportKeys, levels: {}, baseLng: base!.lng, baseLat: base!.lat, baseLabel: base!.label,
        radiusKm, transportModes: modes, windowStart: windowStart.toISOString(), windowEnd: windowEnd.toISOString(),
      });
      await discoveryService.activate();
      await queryClient.invalidateQueries({ queryKey: ['my-dispo'] });
      await queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
      Burnt.toast({ title: t('discovery.activated', { defaultValue: 'Ta dispo est active' }), preset: 'done' });
      router.replace('/(auth)/discovery');
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
      setSaving(false);
    }
  };

  const fmt = (d: Date) => dayjs(d).locale(i18n.language).format('ddd D MMM');

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={8}><X size={24} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
        <Text style={styles.headerTitle}>{t('discovery.composeTitle', { defaultValue: 'Ma dispo' })}</Text>
        <View style={{ width: 24 }} />
      </View>

      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Text style={styles.section}>{t('discovery.sportsLabel', { defaultValue: 'Sport(s) — 1 à 3' })}</Text>
        <SportDropdown selected={sportKeys} onSelect={toggleSport} multiSelect label={t('map.sportLabel')} />

        <Text style={styles.section}>{t('discovery.placeLabel', { defaultValue: 'Autour de quel lieu ?' })}</Text>
        {base && <Text style={styles.chosenPlace}>{base.label}</Text>}
        <PlaceSearchBar onSelect={(p) => setBase({ lng: p.lng, lat: p.lat, label: p.label })} />

        <Text style={styles.section}>{t('discovery.radiusLabel', { defaultValue: 'Rayon' })}</Text>
        <View style={styles.chipRow}>
          {RADII.map((r) => (
            <Pressable key={String(r)} style={[styles.chip, radiusKm === r && styles.chipActive]} onPress={() => setRadiusKm(r)}>
              <Text style={[styles.chipText, radiusKm === r && styles.chipTextActive]}>
                {r === null ? t('discovery.radiusAny', { defaultValue: 'Peu importe' }) : `${r} km`}
              </Text>
            </Pressable>
          ))}
        </View>

        <Text style={styles.section}>{t('discovery.whenLabel', { defaultValue: 'Quand ?' })}</Text>
        <View style={styles.chipRow}>
          <Pressable style={styles.dateChip} onPress={() => setShowStart(true)}>
            <Text style={styles.dateChipText}>{fmt(windowStart)}</Text>
          </Pressable>
          <Text style={styles.dateArrow}>→</Text>
          <Pressable style={styles.dateChip} onPress={() => setShowEnd(true)}>
            <Text style={styles.dateChipText}>{fmt(windowEnd)}</Text>
          </Pressable>
        </View>
        {showStart && (
          <DateTimePicker value={windowStart} mode="date" minimumDate={new Date()}
            onChange={(_e, d) => { setShowStart(Platform.OS === 'ios'); if (d) { setWindowStart(d); if (d >= windowEnd) setWindowEnd(dayjs(d).add(3, 'day').toDate()); } }} />
        )}
        {showEnd && (
          <DateTimePicker value={windowEnd} mode="date" minimumDate={windowStart}
            onChange={(_e, d) => { setShowEnd(Platform.OS === 'ios'); if (d) setWindowEnd(d); }} />
        )}

        <Text style={styles.section}>{t('discovery.transportLabel', { defaultValue: 'Comment tu te déplaces' })}</Text>
        <View style={styles.chipRow}>
          {MODES.map(({ key, icon: Icon, label }) => {
            const on = modes.includes(key);
            return (
              <Pressable key={key} style={[styles.chip, on && styles.chipActive]} onPress={() => toggleMode(key)}>
                <Icon size={14} color={on ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.2} />
                <Text style={[styles.chipText, on && styles.chipTextActive]}>{label}</Text>
              </Pressable>
            );
          })}
        </View>
      </ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.sm }]}>
        <Text style={styles.counter}>{counterText()}</Text>
        <Pressable style={[styles.cta, !ready && styles.ctaDisabled]} disabled={!ready || saving} onPress={handleActivate}>
          <Text style={styles.ctaText}>{saving ? t('discovery.activating', { defaultValue: 'Activation…' }) : t('discovery.activateCta', { defaultValue: 'Activer ma dispo' })}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md, paddingVertical: spacing.md },
  headerTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  content: { paddingHorizontal: spacing.md, paddingBottom: spacing.xl },
  section: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.lg, marginBottom: spacing.sm },
  chosenPlace: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', marginBottom: spacing.sm },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2, alignItems: 'center' },
  chip: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.full, paddingHorizontal: spacing.md, paddingVertical: spacing.sm - 1 },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  chipTextActive: { color: '#FFFFFF' },
  dateChip: { borderWidth: 1, borderColor: colors.borderStrong, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  dateChipText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  dateArrow: { color: colors.textSecondary, fontSize: fontSizes.lg },
  footer: { borderTopWidth: 1, borderTopColor: colors.borderMuted, paddingHorizontal: spacing.md, paddingTop: spacing.sm, gap: spacing.sm },
  counter: { color: colors.textPrimary, fontSize: fontSizes.sm, textAlign: 'center' },
  cta: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  ctaDisabled: { opacity: 0.4 },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
