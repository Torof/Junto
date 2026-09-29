import { useMemo, useState, useEffect } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput } from 'react-native';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { Send } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, glow, shadows } from '@/constants/theme';
import { bookingService, type ParticipantEntry } from '@/services/booking-service';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

// Fiche du groupe (chantier B) — le client remplit, APRÈS confirmation, les
// infos par participant demandées par l'offre (pointure/taille/poids/âge/
// niveau + questions libres). Visible du pro concerné uniquement.
const STD_LABELS: Record<string, { key: string; fallback: string; keyboard?: 'number-pad' }> = {
  shoe_size: { key: 'booking.fShoe', fallback: 'Pointure', keyboard: 'number-pad' },
  height: { key: 'booking.fHeight', fallback: 'Taille (cm)', keyboard: 'number-pad' },
  weight: { key: 'booking.fWeight', fallback: 'Poids (kg)', keyboard: 'number-pad' },
  age: { key: 'booking.fAge', fallback: 'Âge', keyboard: 'number-pad' },
  level: { key: 'booking.fLevel', fallback: 'Niveau' },
};

export default function BookingFormScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { bookingId } = useLocalSearchParams<{ bookingId: string }>();

  const { data: bookings, isLoading } = useQuery({
    queryKey: ['my-bookings'],
    queryFn: () => bookingService.getMyBookings(),
  });
  const booking = (bookings ?? []).find((b) => b.id === bookingId) ?? null;

  const stdFields = booking?.participant_fields?.std ?? [];
  const customQs = booking?.participant_fields?.custom ?? [];
  const count = booking?.party_size ?? 0;

  const [entries, setEntries] = useState<ParticipantEntry[]>([]);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    if (!booking) return;
    const existing = booking.participant_info ?? [];
    setEntries(Array.from({ length: booking.party_size }, (_, i) => existing[i] ?? {}));
  }, [booking]);

  const setField = (idx: number, key: string, value: string) => {
    setEntries((prev) => prev.map((e, i) => (i === idx ? { ...e, [key]: value } : e)));
  };
  const setCustom = (idx: number, q: string, value: string) => {
    setEntries((prev) => prev.map((e, i) =>
      i === idx ? ({ ...e, custom: { ...(e.custom ?? {}), [q]: value } } as ParticipantEntry) : e,
    ));
  };

  const submit = async () => {
    if (!bookingId) return;
    // N'envoyer que les valeurs non vides (la RPC valide clés + longueurs).
    const clean: ParticipantEntry[] = entries.map((e) => {
      const out: ParticipantEntry = {};
      for (const f of stdFields) {
        const v = (e[f] ?? '').trim();
        if (v) out[f] = v;
      }
      const cust: Record<string, string> = {};
      for (const q of customQs) {
        const v = (e.custom?.[q] ?? '').trim();
        if (v) cust[q] = v;
      }
      if (Object.keys(cust).length > 0) out.custom = cust;
      return out;
    });
    setSending(true);
    try {
      await bookingService.setParticipantInfo(bookingId, clean);
      await queryClient.invalidateQueries({ queryKey: ['my-bookings'] });
      Burnt.toast({ title: t('booking.formSent', { defaultValue: 'Fiche envoyée au professionnel' }), preset: 'done' });
      router.back();
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
    } finally {
      setSending(false);
    }
  };

  if (isLoading || !booking) {
    return (
      <View style={styles.center}>
        <Stack.Screen options={{ title: t('booking.formTitle', { defaultValue: 'Fiche du groupe' }) }} />
        {isLoading ? <LogoSpinner size={36} /> : <Text style={styles.intro}>{t('booking.offeringGone', { defaultValue: 'Offre indisponible.' })}</Text>}
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('booking.formTitle', { defaultValue: 'Fiche du groupe' }) }} />
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <Text style={styles.intro}>
          {t('booking.formIntro', {
            defaultValue: '{{pro}} a besoin de quelques infos pour préparer le matériel de ton groupe ({{count}} pers.).',
            pro: booking.pro_name ?? t('booking.thePro', { defaultValue: 'Le professionnel' }),
            count,
          })}
        </Text>

        {entries.map((entry, idx) => (
          <View key={idx} style={styles.card}>
            <Text style={styles.pTitle}>
              {idx === 0
                ? t('booking.participantYou', { defaultValue: 'Participant 1 · toi' })
                : t('booking.participantN', { defaultValue: 'Participant {{n}}', n: idx + 1 })}
            </Text>
            <View style={styles.fieldsRow}>
              {stdFields.map((f) => {
                const meta = STD_LABELS[f];
                if (!meta) return null;
                return (
                  <View key={f} style={styles.fieldBox}>
                    <Text style={styles.fieldLabel}>{t(meta.key, { defaultValue: meta.fallback })}</Text>
                    <TextInput
                      style={styles.fieldInput}
                      value={entry[f] ?? ''}
                      onChangeText={(v) => setField(idx, f, v)}
                      keyboardType={meta.keyboard}
                      maxLength={30}
                      placeholder="—"
                      placeholderTextColor={colors.textMuted}
                    />
                  </View>
                );
              })}
            </View>
            {customQs.map((q) => (
              <View key={q} style={{ marginTop: spacing.sm }}>
                <Text style={styles.fieldLabel}>{q}</Text>
                <TextInput
                  style={[styles.fieldInput, styles.customInput]}
                  value={entry.custom?.[q] ?? ''}
                  onChangeText={(v) => setCustom(idx, q, v)}
                  maxLength={120}
                  placeholder={t('booking.answerPlaceholder', { defaultValue: 'Ta réponse…' })}
                  placeholderTextColor={colors.textMuted}
                />
              </View>
            ))}
          </View>
        ))}

        <PressableScale style={[styles.submit, glow(colors.cta), sending && styles.disabled]} onPress={submit} disabled={sending}>
          <Send size={15} color={colors.onCta} strokeWidth={2.4} />
          <Text style={styles.submitText}>{sending ? '…' : t('booking.formSubmit', { defaultValue: 'Envoyer la fiche' })}</Text>
        </PressableScale>
        <Text style={styles.fine}>
          {t('booking.formPrivacy', { defaultValue: 'Ces infos ne sont visibles que du professionnel, pour cette sortie.' })}
        </Text>
      </ScrollView>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', padding: spacing.lg },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl + 24 },
  intro: { color: colors.textSecondary, fontSize: fontSizes.sm + 1, lineHeight: 21, marginBottom: spacing.md },
  card: {
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md,
    marginBottom: spacing.sm + 2, borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card,
  },
  pTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800', marginBottom: spacing.sm },
  fieldsRow: { flexDirection: 'row', gap: spacing.sm, flexWrap: 'wrap' },
  fieldBox: { flexGrow: 1, flexBasis: '28%' },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs - 1, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 3,
  },
  fieldInput: {
    backgroundColor: colors.surfaceAlt, borderWidth: 1, borderColor: colors.lineStrong,
    borderRadius: radius.md, paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '600',
  },
  customInput: { fontWeight: '400' },
  submit: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 5, marginTop: spacing.sm,
  },
  submitText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  disabled: { opacity: 0.45 },
  fine: { color: colors.textMuted, fontSize: fontSizes.xs + 1, textAlign: 'center', marginTop: spacing.sm },
});
