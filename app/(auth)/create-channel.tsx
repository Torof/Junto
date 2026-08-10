import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, TextInput, StyleSheet, Modal, KeyboardAvoidingView, Platform } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { X } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { SportDropdown } from '@/components/sport-dropdown';
import { PlaceSearchBar } from '@/components/place-search-bar';
import { channelService } from '@/services/channel-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { haptic } from '@/lib/haptics';

export default function CreateChannelScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const insets = useSafeAreaInsets();

  const [sportKeys, setSportKeys] = useState<string[]>([]);
  const [base, setBase] = useState<{ lng: number; lat: number; label: string } | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [saving, setSaving] = useState(false);
  const [dupId, setDupId] = useState<string | null>(null);

  const toggleSport = (k: string) => setSportKeys((prev) =>
    prev.includes(k) ? prev.filter((x) => x !== k) : prev.length >= 3 ? prev : [...prev, k]);

  // Place is optional (a channel can be a general topic with no precise spot).
  const ready = sportKeys.length >= 1 && name.trim().length >= 1;

  const goTo = (id: string) => {
    queryClient.invalidateQueries({ queryKey: ['channels'] });
    queryClient.invalidateQueries({ queryKey: ['conversations'] });
    router.replace(`/(auth)/conversation/${id}`);
  };

  const submit = async (force: boolean) => {
    if (!ready || saving) return;
    setSaving(true);
    try {
      haptic.success();
      const res = await channelService.create({
        sportKeys, name: name.trim(),
        baseLng: base?.lng ?? null, baseLat: base?.lat ?? null, baseLabel: base?.label ?? null,
        description: description.trim() || null, force,
      });
      if (res.duplicate) { setDupId(res.conversationId); setSaving(false); return; }
      goTo(res.conversationId);
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
      setSaving(false);
    }
  };

  const joinExisting = async () => {
    if (!dupId) return;
    try {
      await channelService.join(dupId);
      const id = dupId;
      setDupId(null);
      goTo(id);
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={8}><X size={24} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
        <Text style={styles.headerTitle}>{t('channels.createTitle', { defaultValue: 'Nouveau canal' })}</Text>
        <View style={{ width: 24 }} />
      </View>

      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Text style={styles.section}>{t('channels.sportLabel', { defaultValue: 'Sport(s) — 1 à 3' })}</Text>
        <SportDropdown selected={sportKeys} onSelect={toggleSport} multiSelect label={t('map.sportLabel')} />

        <Text style={styles.section}>{t('channels.placeLabelOpt', { defaultValue: 'Lieu / secteur (optionnel)' })}</Text>
        {base && (
          <View style={styles.chosenPlaceRow}>
            <Text style={styles.chosenPlace}>{base.label}</Text>
            <Text style={styles.placeClear} onPress={() => setBase(null)}>{t('channels.clearPlace', { defaultValue: 'retirer' })}</Text>
          </View>
        )}
        <PlaceSearchBar onSelect={(p) => setBase({ lng: p.lng, lat: p.lat, label: p.label })} />

        <Text style={styles.section}>{t('channels.nameLabel', { defaultValue: 'Nom du canal' })}</Text>
        <TextInput
          style={styles.input}
          value={name}
          onChangeText={setName}
          placeholder={t('channels.namePlaceholder', { defaultValue: 'Ex. Rando Briançonnais' })}
          placeholderTextColor={colors.textMuted}
          maxLength={60}
        />

        <Text style={styles.section}>{t('channels.descLabel', { defaultValue: 'Description (optionnel)' })}</Text>
        <TextInput
          style={[styles.input, styles.inputMulti]}
          value={description}
          onChangeText={setDescription}
          placeholder={t('channels.descPlaceholder', { defaultValue: 'De quoi on parle ici…' })}
          placeholderTextColor={colors.textMuted}
          multiline
          maxLength={500}
        />
      </ScrollView>
      </KeyboardAvoidingView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.sm }]}>
        <Pressable style={[styles.cta, !ready && styles.ctaDisabled]} disabled={!ready || saving} onPress={() => submit(false)}>
          <Text style={styles.ctaText}>{saving ? t('channels.creating', { defaultValue: 'Création…' }) : t('channels.createCta', { defaultValue: 'Créer le canal' })}</Text>
        </Pressable>
      </View>

      {/* Dedupe: an equivalent open channel already exists. */}
      <Modal visible={!!dupId} transparent animationType="fade" onRequestClose={() => setDupId(null)}>
        <Pressable style={styles.modalBackdrop} onPress={() => setDupId(null)}>
          <Pressable style={styles.modalCard} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.modalTitle}>{t('channels.dupTitle', { defaultValue: 'Un canal existe déjà' })}</Text>
            <Text style={styles.modalBody}>{t('channels.dupBody', { defaultValue: 'Un canal pour ce sport existe déjà dans cette zone. Rejoins-le plutôt que d’en créer un doublon.' })}</Text>
            <Pressable style={styles.modalPrimary} onPress={joinExisting}>
              <Text style={styles.modalPrimaryText}>{t('channels.dupJoin', { defaultValue: 'Rejoindre l’existant' })}</Text>
            </Pressable>
            <Pressable style={styles.modalSecondary} onPress={() => { setDupId(null); submit(true); }}>
              <Text style={styles.modalSecondaryText}>{t('channels.dupCreate', { defaultValue: 'Créer quand même' })}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md, paddingVertical: spacing.md },
  headerTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  content: { paddingHorizontal: spacing.md, paddingBottom: spacing.xl + 80 },
  section: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.lg, marginBottom: spacing.sm },
  chosenPlaceRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: spacing.sm },
  chosenPlace: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700', flexShrink: 1 },
  placeClear: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', textDecorationLine: 'underline' },
  input: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 2, color: colors.textPrimary, fontSize: fontSizes.md },
  inputMulti: { minHeight: 88, textAlignVertical: 'top' },
  footer: { borderTopWidth: 1, borderTopColor: colors.borderMuted, paddingHorizontal: spacing.md, paddingTop: spacing.sm },
  cta: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  ctaDisabled: { opacity: 0.4 },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  modalBackdrop: { flex: 1, backgroundColor: '#00000088', alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  modalCard: { backgroundColor: colors.background, borderRadius: radius.lg, padding: spacing.lg, gap: spacing.sm, width: '100%', maxWidth: 380 },
  modalTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  modalBody: { color: colors.textSecondary, fontSize: fontSizes.md, lineHeight: 22, marginBottom: spacing.sm },
  modalPrimary: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  modalPrimaryText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  modalSecondary: { paddingVertical: spacing.sm, alignItems: 'center' },
  modalSecondaryText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '700' },
});
