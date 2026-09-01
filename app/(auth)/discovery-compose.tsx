import { useEffect, useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Platform, TextInput } from 'react-native';
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
import { discoveryService, type TransportMode, type DispoIntent } from '@/services/discovery-service';
import { getSportIcon } from '@/constants/sport-icons';
import { getLevelScale, OPEN_LEVEL } from '@/constants/sport-levels';
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
// Vibe pills grouped for the picker (shown flat on the card). Labels carry an
// emoji for the Tinder-like feel. i18n key discovery.intent.<key> overrides.
const VIBE_GROUPS: { group: string; groupKey: string; items: { key: DispoIntent; label: string }[] }[] = [
  { group: 'Ambiance', groupKey: 'ambiance', items: [
    { key: 'discovery', label: '🧭 Découverte' },
    { key: 'progression', label: '📈 Progression' },
    { key: 'performance', label: '🔥 Performance' },
    { key: 'detente', label: '🍃 Détente' },
    { key: 'conviviality', label: '🤝 Convivialité' },
    { key: 'nature', label: '🌲 Nature' },
    { key: 'challenge', label: '🎯 Défi' },
    { key: 'photo', label: '📷 Photo' },
  ] },
  { group: 'Compagnie', groupKey: 'compagnie', items: [
    { key: 'dog', label: '🐕 Chien' },
    { key: 'child', label: '👶 Enfant' },
    { key: 'group', label: '👥 En groupe' },
    { key: 'solo', label: '🧍 Solo' },
    { key: 'mixed', label: '⚥ Groupe mixte' },
    { key: 'same_level', label: '🎚️ Même niveau' },
    { key: 'beginners', label: '🌱 Débutants bienvenus' },
  ] },
  { group: 'Rythme', groupKey: 'rythme', items: [
    { key: 'active', label: '⚡ Actif' },
    { key: 'calm', label: '😌 Calme' },
    { key: 'early', label: '🌅 Matinal' },
    { key: 'long_outing', label: '🥾 Sortie longue' },
    { key: 'after_work', label: '🌆 Après le boulot' },
    { key: 'regular', label: '🔁 Partenaire régulier' },
  ] },
  { group: 'Profil / accès', groupKey: 'profil', items: [
    { key: 'adapted', label: '♿ Handi / adapté' },
    { key: 'training', label: '💪 Entraînement' },
    { key: 'experienced', label: '🎖️ Expérimenté' },
    { key: 'competition', label: '🏁 Prépa compét' },
  ] },
];
const MAX_VIBES = 10;

export default function DiscoveryComposeScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const insets = useSafeAreaInsets();

  const [sportKeys, setSportKeys] = useState<string[]>([]);
  const [levels, setLevels] = useState<Record<string, string>>({});
  const [intent, setIntent] = useState<DispoIntent[]>([]);
  const [base, setBase] = useState<{ lng: number; lat: number; label: string } | null>(null);
  const [radiusKm, setRadiusKm] = useState<number | null>(30);
  const [modes, setModes] = useState<TransportMode[]>(['car']);
  const [windowStart, setWindowStart] = useState<Date>(new Date());
  const [windowEnd, setWindowEnd] = useState<Date>(dayjs().add(7, 'day').toDate());
  const [about, setAbout] = useState('');
  const [showStart, setShowStart] = useState(false);
  const [showEnd, setShowEnd] = useState(false);
  const [saving, setSaving] = useState(false);

  // Prefill from an existing dispo (edit).
  const { data: mine } = useQuery({ queryKey: ['my-dispo'], queryFn: () => discoveryService.getMyDispo() });
  useEffect(() => {
    if (!mine) return;
    setSportKeys(mine.sport_keys);
    setLevels(mine.levels ?? {});
    setIntent(mine.intent ?? []);
    setBase({ lng: mine.base_lng, lat: mine.base_lat, label: mine.base_label });
    setRadiusKm(mine.radius_km);
    setModes(mine.transport_modes);
    setWindowStart(new Date(mine.window_start));
    setWindowEnd(new Date(mine.window_end));
    setAbout(mine.about ?? '');
  }, [mine]);

  const toggleSport = (key: string) => setSportKeys((prev) => {
    if (prev.includes(key)) {
      setLevels((lv) => { const next = { ...lv }; delete next[key]; return next; }); // prune orphan grade
      return prev.filter((k) => k !== key);
    }
    return prev.length >= 3 ? prev : [...prev, key];
  });
  const setSportLevel = (sport: string, label: string) => setLevels((prev) => {
    const next = { ...prev };
    if (label === OPEN_LEVEL) delete next[sport]; else next[sport] = label; // "Tous niveaux" = unset
    return next;
  });
  const toggleMode = (m: TransportMode) => setModes((prev) =>
    prev.includes(m) ? prev.filter((x) => x !== m) : [...prev, m]);
  const toggleIntent = (k: DispoIntent) => setIntent((prev) =>
    prev.includes(k) ? prev.filter((x) => x !== k) : prev.length >= MAX_VIBES ? prev : [...prev, k]);

  const aboutWords = about.trim() ? about.trim().split(/\s+/).length : 0;
  const aboutOk = aboutWords <= 250;
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
    if (!ready || !aboutOk || saving) return;
    setSaving(true);
    try {
      haptic.success();
      await discoveryService.upsert({
        sportKeys, levels, intent, baseLng: base!.lng, baseLat: base!.lat, baseLabel: base!.label,
        radiusKm, transportModes: modes, windowStart: windowStart.toISOString(), windowEnd: windowEnd.toISOString(),
        about,
      });
      await discoveryService.activate();
      await queryClient.invalidateQueries({ queryKey: ['my-dispo'] });
      await queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
      Burnt.toast({ title: t('discovery.activated', { defaultValue: 'Ta dispo est active' }), preset: 'done' });
      router.replace('/(auth)/(tabs)/partenaires?tab=discovery');
    } catch (e) {
      // TEMP diag (Scott 2026-09-01): raw error in the TITLE (guaranteed visible) to pin down the save bug.
      const x = (e ?? {}) as { message?: string; code?: string; details?: string };
      Burnt.toast({ title: `DIAG ${x.code ?? ''} ${x.message ?? x.details ?? String(e)}`.slice(0, 150) });
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

        {sportKeys.length > 0 && (
          <>
            <Text style={styles.section}>{t('discovery.levelLabel', { defaultValue: 'Niveau par sport (optionnel)' })}</Text>
            {sportKeys.map((sk) => (
              <View key={sk} style={styles.levelBlock}>
                <Text style={styles.levelSport}>{getSportIcon(sk)} {t(`sports.${sk}`, { defaultValue: sk })}</Text>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} keyboardShouldPersistTaps="handled" contentContainerStyle={styles.levelChips}>
                  {getLevelScale(sk).map((opt) => {
                    const sel = (levels[sk] ?? OPEN_LEVEL) === opt.label;
                    return (
                      <Pressable key={opt.label} style={[styles.levelChip, sel && styles.chipActive]} onPress={() => setSportLevel(sk, opt.label)}>
                        <Text style={[styles.levelChipText, sel && styles.chipTextActive]}>{opt.label}</Text>
                      </Pressable>
                    );
                  })}
                </ScrollView>
              </View>
            ))}
          </>
        )}

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

        <Text style={styles.section}>{t('discovery.vibesLabel', { defaultValue: 'Toi & ta sortie (optionnel)' })}</Text>
        {VIBE_GROUPS.map(({ group, groupKey, items }) => (
          <View key={groupKey} style={styles.vibeGroup}>
            <Text style={styles.vibeGroupLabel}>{t(`discovery.vibeGroup.${groupKey}`, { defaultValue: group })}</Text>
            <View style={styles.chipRow}>
              {items.map(({ key, label }) => {
                const on = intent.includes(key);
                return (
                  <Pressable key={key} style={[styles.chip, on && styles.chipActive]} onPress={() => toggleIntent(key)}>
                    <Text style={[styles.chipText, on && styles.chipTextActive]}>{t(`discovery.intent.${key}`, { defaultValue: label })}</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        ))}

        <Text style={styles.section}>{t('discovery.aboutLabel', { defaultValue: 'Présentation (optionnel)' })}</Text>
        <TextInput
          style={styles.aboutInput}
          value={about}
          onChangeText={setAbout}
          multiline
          textAlignVertical="top"
          placeholder={t('discovery.aboutPlaceholder', { defaultValue: 'Présente-toi en quelques lignes : qui tu es, ce que tu cherches, tes attentes…' })}
          placeholderTextColor={colors.textMuted}
          maxLength={1600}
        />
        <Text style={[styles.aboutCounter, !aboutOk && styles.aboutCounterOver]}>
          {t('discovery.aboutCounter', { defaultValue: '{{count}}/250 mots', count: aboutWords })}
        </Text>
      </ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.sm }]}>
        <Text style={styles.counter}>{counterText()}</Text>
        <Pressable style={[styles.cta, (!ready || !aboutOk) && styles.ctaDisabled]} disabled={!ready || !aboutOk || saving} onPress={handleActivate}>
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
  aboutInput: { backgroundColor: colors.surface, borderRadius: 14, borderWidth: 1, borderColor: colors.borderMuted, padding: spacing.sm + 2, minHeight: 110, color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  aboutCounter: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '700', alignSelf: 'flex-end', marginTop: spacing.xs },
  aboutCounterOver: { color: colors.error },
  vibeGroup: { marginBottom: spacing.sm + 2 },
  vibeGroupLabel: { color: colors.textMuted, fontSize: fontSizes.xs - 1, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.4, marginBottom: spacing.xs + 1 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2, alignItems: 'center' },
  chip: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.full, paddingHorizontal: spacing.md, paddingVertical: spacing.sm - 1 },
  chipActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  chipTextActive: { color: '#FFFFFF' },
  levelBlock: { marginBottom: spacing.sm },
  levelSport: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700', marginBottom: spacing.xs },
  levelChips: { gap: spacing.xs + 2, paddingRight: spacing.md },
  levelChip: { borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.xs + 1 },
  levelChipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  dateChip: { borderWidth: 1, borderColor: colors.borderStrong, borderRadius: radius.sm, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  dateChipText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  dateArrow: { color: colors.textSecondary, fontSize: fontSizes.lg },
  footer: { borderTopWidth: 1, borderTopColor: colors.borderMuted, paddingHorizontal: spacing.md, paddingTop: spacing.sm, gap: spacing.sm },
  counter: { color: colors.textPrimary, fontSize: fontSizes.sm, textAlign: 'center' },
  cta: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  ctaDisabled: { opacity: 0.4 },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
